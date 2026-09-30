import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A live, cross-platform entry point for invitations. Native app links will
/// replace this only after iOS and Android association files are configured.
String mozaqueInviteLink(String code) => Uri.https(
  'joeldickinsonuk.github.io',
  '/mozaque/',
  {'invite': code},
).toString();

class MozaqueRepository {
  MozaqueRepository(this.db);
  final SupabaseClient db;
  String get uid => db.auth.currentUser!.id;

  Future<Map<String, dynamic>?> profile() async =>
      db.from('profiles').select().eq('id', uid).maybeSingle();
  Future<void> saveName(String value) async =>
      db.from('profiles').update({'display_name': value.trim()}).eq('id', uid);
  Future<List<Map<String, dynamic>>> galleries() async =>
      List<Map<String, dynamic>>.from(
        await db
            .from('galleries')
            .select()
            .order('created_at', ascending: false)
            .limit(60),
      );
  Future<Map<String, dynamic>> createGallery(
    Map<String, dynamic> values,
  ) async {
    final user = await db.auth.getUser();
    final ownerId = user.user?.id;
    if (ownerId == null || ownerId.isEmpty) {
      throw StateError('Your session has expired. Please sign in again.');
    }
    final result = await db.rpc(
      'create_gallery',
      params: {
        'p_title': values['title'],
        'p_description': values['description'],
        'p_event_type': values['event_type'],
        'p_event_date': values['event_date'],
        'p_is_recurring': values['is_recurring'],
        'p_upload_policy': values['upload_policy'],
        'p_audience': values['audience'],
      },
    );
    final gallery = Map<String, dynamic>.from(result as Map);
    if (gallery['owner_id'] != ownerId) {
      throw StateError(
        'The signed-in account did not match the gallery owner.',
      );
    }
    return gallery;
  }

  Future<Map<String, dynamic>> gallery(String id) async =>
      await db.from('galleries').select().eq('id', id).single();
  Future<List<Map<String, dynamic>>> members(String galleryId) async =>
      List<Map<String, dynamic>>.from(
        await db
            .from('gallery_members')
            .select('user_id,role,profiles(display_name)')
            .eq('gallery_id', galleryId),
      );
  Future<void> addConnectionToGallery(String galleryId, String userId) async =>
      db.rpc(
        'add_connection_to_gallery',
        params: {'target_gallery': galleryId, 'target_user': userId},
      );
  Future<List<Map<String, dynamic>>> photos({
    String? galleryId,
    bool pieces = false,
  }) async {
    var query = db
        .from('photos')
        .select(
          '*,profiles!photos_uploader_id_fkey(display_name),galleries(id,title,event_date,is_recurring,event_type)',
        );
    if (galleryId != null) query = query.eq('gallery_id', galleryId);
    if (pieces) {
      final rows = await db
          .from('pieces')
          .select('photo_id')
          .eq('user_id', uid);
      final ids = List<String>.from(rows.map((r) => r['photo_id'] as String));
      if (ids.isEmpty) return [];
      query = query.inFilter('id', ids);
    }
    final result = List<Map<String, dynamic>>.from(
      await query.order('created_at', ascending: false).limit(100),
    );
    if (result.isEmpty) return result;
    final ids = result.map((p) => p['id'] as String).toList();
    final glowRows = await db
        .from('glows')
        .select('photo_id,user_id')
        .inFilter('photo_id', ids);
    final pieceRows = await db
        .from('pieces')
        .select('photo_id')
        .eq('user_id', uid)
        .inFilter('photo_id', ids);
    final counts = <String, int>{};
    final mine = <String>{};
    for (final row in glowRows) {
      final id = row['photo_id'] as String;
      counts[id] = (counts[id] ?? 0) + 1;
      if (row['user_id'] == uid) mine.add(id);
    }
    final kept = pieceRows.map<String>((r) => r['photo_id'] as String).toSet();
    for (final p in result) {
      p['glow_count'] = counts[p['id']] ?? 0;
      p['my_glow'] = mine.contains(p['id']);
      p['my_piece'] = kept.contains(p['id']);
    }
    return result;
  }

  Future<String> photoUrl(String path) =>
      db.storage.from('mozaque-photos').createSignedUrl(path, 3600);
  Future<List<Map<String, dynamic>>> feed() => photos();
  Future<bool> canUpload(Map<String, dynamic> gallery) async {
    if (gallery['owner_id'] == uid) return gallery['frozen_at'] == null;
    if (gallery['frozen_at'] != null) return false;
    final member = await db
        .from('gallery_members')
        .select('role')
        .eq('gallery_id', gallery['id'])
        .eq('user_id', uid)
        .maybeSingle();
    if (gallery['upload_policy'] == 'owner') return false;
    if (gallery['upload_policy'] == 'selected')
      return member?['role'] == 'contributor';
    if (member != null) return true;
    if (gallery['audience'] == 'connections')
      return (await db.rpc(
            'are_connected',
            params: {'other_user': gallery['owner_id']},
          ))
          as bool;
    return false;
  }

  Future<void> upload(
    String galleryId,
    Uint8List bytes,
    String fileName,
    String caption,
  ) async {
    final extension = fileName.split('.').last.toLowerCase();
    final mime = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
    if (mime == null)
      throw const FormatException('Choose a JPG, PNG or WebP photo.');
    final size = bytes.length;
    if (size == 0 || size > 10 * 1024 * 1024)
      throw const FormatException('Each photo must be smaller than 10 MB.');
    final photoId = const UuidLike().next();
    final path = '$galleryId/$uid/$photoId.$extension';
    await db.storage
        .from('mozaque-photos')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
    try {
      await db.from('photos').insert({
        'id': photoId,
        'gallery_id': galleryId,
        'uploader_id': uid,
        'storage_path': path,
        'caption': caption.trim(),
        'mime_type': mime,
        'byte_size': size,
      });
    } catch (_) {
      await db.storage.from('mozaque-photos').remove([path]);
      rethrow;
    }
  }

  Future<void> keepPiece(String photoId, bool keep) async {
    if (keep) {
      await db
          .from('pieces')
          .upsert(
            {'user_id': uid, 'photo_id': photoId},
            onConflict: 'user_id,photo_id',
            ignoreDuplicates: true,
          );
    } else {
      await db
          .from('pieces')
          .delete()
          .eq('user_id', uid)
          .eq('photo_id', photoId);
    }
  }

  Future<void> glow(String photoId, bool active) async {
    if (active) {
      await db
          .from('glows')
          .upsert(
            {'user_id': uid, 'photo_id': photoId},
            onConflict: 'user_id,photo_id',
            ignoreDuplicates: true,
          );
    } else {
      await db
          .from('glows')
          .delete()
          .eq('user_id', uid)
          .eq('photo_id', photoId);
    }
  }

  Future<int> glowCount(String photoId) async =>
      (await db.from('glows').select('photo_id').eq('photo_id', photoId))
          .length;
  Future<bool> hasGlow(String photoId) async =>
      await db
          .from('glows')
          .select('photo_id')
          .eq('photo_id', photoId)
          .eq('user_id', uid)
          .maybeSingle() !=
      null;
  Future<bool> hasPiece(String photoId) async =>
      await db
          .from('pieces')
          .select('photo_id')
          .eq('photo_id', photoId)
          .eq('user_id', uid)
          .maybeSingle() !=
      null;
  Future<void> freeze(String galleryId) async =>
      db.rpc('freeze_gallery', params: {'target_gallery': galleryId});
  Future<void> setRole(String galleryId, String target, String role) async =>
      db.rpc(
        'set_gallery_member_role',
        params: {
          'target_gallery': galleryId,
          'target_user': target,
          'target_role': role,
        },
      );
  Future<void> updateGallery(String id, Map<String, dynamic> fields) async =>
      db.from('galleries').update(fields).eq('id', id);
  Future<List<Map<String, dynamic>>> connections() async {
    final rows = await db
        .from('connections')
        .select()
        .or('user_a.eq.$uid,user_b.eq.$uid');
    final ids = rows
        .map<String>((r) => r['user_a'] == uid ? r['user_b'] : r['user_a'])
        .toList();
    if (ids.isEmpty) return [];
    return List<Map<String, dynamic>>.from(
      await db
          .from('profiles')
          .select()
          .inFilter('id', ids)
          .order('display_name'),
    );
  }

  Future<String> invite({String? galleryId}) async {
    final bytes = List<int>.generate(24, (_) => Random.secure().nextInt(256));
    final code = base64Url.encode(bytes).replaceAll('=', '');
    final hash = sha256.convert(utf8.encode(code)).toString();
    if (galleryId == null) {
      await db.rpc('create_connection_invite', params: {'invite_hash': hash});
    } else {
      await db.rpc(
        'create_gallery_invite',
        params: {'target_gallery': galleryId, 'invite_hash': hash},
      );
    }
    return code;
  }

  Future<Map<String, dynamic>> acceptInvite(String code) async {
    final hash = sha256.convert(utf8.encode(code.trim())).toString();
    final result = await db.rpc('accept_invite', params: {'invite_hash': hash});
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> revokeInvite(String id) async =>
      db.rpc('revoke_gallery_invite', params: {'invite_id': id});
}

class UuidLike {
  const UuidLike();
  String next() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}
