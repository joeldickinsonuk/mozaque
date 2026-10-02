import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// A live, cross-platform entry point for invitations. Native app links will
/// replace this only after iOS and Android association files are configured.
String mozaqueInviteLink(String code) =>
    Uri.https('mozaque.com', '/', {'invite': code}).toString();

String mozaqueProfileLink(String slug) =>
    Uri.https('mozaque.com', '/${Uri.encodeComponent(slug)}').toString();

/// Keeps auth confirmation on the existing root redirect and resumes the
/// connection request after the visitor confirms their email.
String mozaqueProfileSignupRedirect(String slug) =>
    Uri.https('mozaque.com', '/', {'person': slug, 'connect': '1'}).toString();

/// Reads both clean profile paths and older query-based profile links.
String? mozaqueProfileSlugFromUri(Uri uri) {
  final legacySlug = uri.queryParameters['person'];
  if (legacySlug != null && legacySlug.isNotEmpty) return legacySlug;
  if (uri.pathSegments.length != 1) return null;
  final slug = uri.pathSegments.single;
  const reservedPaths = {
    'feed',
    'people',
    'settings',
    'auth',
    'invite',
    'privacy',
    'terms',
    'profile',
    'mozaques',
    'pieces',
    'login',
    'signup',
    'join',
    'about',
  };
  if (slug.isEmpty || slug.contains('.') || reservedPaths.contains(slug)) {
    return null;
  }
  return slug;
}

class MozaqueRepository {
  MozaqueRepository(this.db);
  final SupabaseClient db;
  String get uid => db.auth.currentUser!.id;

  Future<Map<String, dynamic>?> profile() async {
    final row = await db.from('profiles').select().eq('id', uid).maybeSingle();
    if (row == null) return null;
    final result = Map<String, dynamic>.from(row);
    final preferences = await db
        .from('user_preferences')
        .select('memory_reminders_enabled')
        .eq('user_id', uid)
        .maybeSingle();
    result['memory_reminders_enabled'] =
        preferences?['memory_reminders_enabled'] ?? true;
    return result;
  }

  Future<void> saveName(String value) async =>
      db.from('profiles').update({'display_name': value.trim()}).eq('id', uid);

  Future<void> setGalleryPublic(String galleryId, bool isPublic) async =>
      db.rpc(
        'set_gallery_visibility',
        params: {'target_gallery': galleryId, 'make_public': isPublic},
      );

  Future<String?> saveProfileSlug(String value) async {
    final saved = await db.rpc(
      'set_my_profile_slug',
      params: {'requested_slug': value},
    );
    return saved is String && saved.isNotEmpty ? saved : null;
  }

  Future<Map<String, dynamic>?> lookupProfileSlug(String slug) async {
    final rows = await db.rpc(
      'lookup_profile_slug',
      params: {'target_slug': slug},
    );
    if (rows is! List || rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first as Map);
  }

  Future<List<Map<String, dynamic>>> publicProfileGalleries(String slug) async {
    final result = await db.rpc(
      'public_profile_galleries',
      params: {'target_slug': slug},
    );
    return result is List
        ? result.map((row) => Map<String, dynamic>.from(row as Map)).toList()
        : <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>?> publicProfileGalleryDetail(
    String slug,
    String galleryId,
  ) async {
    final result = await db.rpc(
      'public_profile_gallery_detail',
      params: {'target_slug': slug, 'target_gallery': galleryId},
    );
    return result is Map ? Map<String, dynamic>.from(result) : null;
  }

  Future<String> requestConnectionBySlug(String slug) async => (await db.rpc(
    'request_connection_by_slug',
    params: {'target_slug': slug},
  )).toString();

  Future<String> respondToConnectionRequest(
    String requestId, {
    required bool accept,
  }) async => (await db.rpc(
    'respond_to_connection_request',
    params: {'request_id': requestId, 'accept_request': accept},
  )).toString();

  Future<List<Map<String, dynamic>>>
  incomingConnectionRequests() async => List<Map<String, dynamic>>.from(
    await db
        .from('connection_requests')
        .select(
          'id,requester_id,created_at,profiles!connection_requests_requester_id_fkey(display_name,avatar_path)',
        )
        .eq('recipient_id', uid)
        .eq('status', 'pending')
        .order('created_at', ascending: false),
  );

  Future<String> connectionStatus(String otherUserId) async {
    final links = await db
        .from('connections')
        .select('user_a,user_b')
        .or('user_a.eq.$uid,user_b.eq.$uid');
    if (links.any(
      (row) => row['user_a'] == otherUserId || row['user_b'] == otherUserId,
    )) {
      return 'connected';
    }
    final requests = await db
        .from('connection_requests')
        .select('requester_id,recipient_id,status')
        .or('requester_id.eq.$uid,recipient_id.eq.$uid');
    for (final row in requests) {
      if (row['requester_id'] == uid &&
          row['recipient_id'] == otherUserId &&
          row['status'] == 'pending') {
        return 'outgoing';
      }
      if (row['recipient_id'] == uid &&
          row['requester_id'] == otherUserId &&
          row['status'] == 'pending') {
        return 'incoming';
      }
    }
    return 'none';
  }

  Future<void> setMemoryReminders(bool enabled) async =>
      db.from('user_preferences').upsert({
        'user_id': uid,
        'memory_reminders_enabled': enabled,
      }, onConflict: 'user_id');

  Future<String> saveAvatar({
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    final oldPath = (await profile())?['avatar_path'] as String?;
    final path = '$uid/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await db.storage
        .from('profile-photos')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            cacheControl: '3600',
            upsert: false,
          ),
        );
    try {
      await db.from('profiles').update({'avatar_path': path}).eq('id', uid);
    } catch (_) {
      try {
        await db.storage.from('profile-photos').remove([path]);
      } catch (_) {}
      rethrow;
    }
    if (oldPath != null && oldPath.isNotEmpty) {
      try {
        await db.storage.from('profile-photos').remove([oldPath]);
      } catch (_) {}
    }
    return path;
  }

  Future<void> removeAvatar(String path) async {
    await db.from('profiles').update({'avatar_path': null}).eq('id', uid);
    try {
      await db.storage.from('profile-photos').remove([path]);
    } catch (_) {}
  }

  Future<void> deleteAccount() async {
    await db.functions.invoke('delete-account', body: const {});
    // Auth user deletion does not revoke an already-issued JWT immediately.
    // Clear this device's local session as soon as the server confirms deletion.
    try {
      await db.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
  }

  Future<String> avatarUrl(String path) =>
      db.storage.from('profile-photos').createSignedUrl(path, 3600);

  Future<List<Map<String, dynamic>>> galleries() async {
    final galleries = List<Map<String, dynamic>>.from(
      await db
          .from('galleries')
          .select()
          .order('created_at', ascending: false)
          .limit(60),
    );
    final coverIds = galleries
        .map((gallery) => gallery['cover_photo_id'])
        .whereType<String>()
        .toSet()
        .toList();
    if (coverIds.isEmpty) return galleries;

    final covers = List<Map<String, dynamic>>.from(
      await db
          .from('photos')
          .select('id,storage_path')
          .inFilter('id', coverIds),
    );
    final paths = {
      for (final photo in covers) photo['id']: photo['storage_path'],
    };
    for (final gallery in galleries) {
      gallery['cover_storage_path'] = paths[gallery['cover_photo_id']];
    }
    return galleries;
  }

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
    if (values['is_public'] == true) {
      await setGalleryPublic(gallery['id'] as String, true);
      gallery['is_public'] = true;
    }
    return gallery;
  }

  Future<Map<String, dynamic>> gallery(String id) async =>
      await db.from('galleries').select().eq('id', id).single();
  Future<List<Map<String, dynamic>>> members(String galleryId) async =>
      List<Map<String, dynamic>>.from(
        await db
            .from('gallery_members')
            .select('user_id,role,profiles(display_name,avatar_path)')
            .eq('gallery_id', galleryId),
      );
  Future<void> addConnectionToGallery(String galleryId, String userId) async =>
      db.rpc(
        'add_connection_to_gallery',
        params: {'target_gallery': galleryId, 'target_user': userId},
      );
  Future<void> setGalleryCoverPhoto(String galleryId, String photoId) async =>
      db.rpc(
        'set_gallery_cover_photo',
        params: {'target_gallery': galleryId, 'target_photo': photoId},
      );
  Future<List<Map<String, dynamic>>> photos({
    String? galleryId,
    bool pieces = false,
  }) async {
    var query = db
        .from('photos')
        .select(
          '*,profiles!photos_uploader_id_fkey(display_name,avatar_path),galleries!photos_gallery_id_fkey(id,title,event_date,is_recurring,event_type)',
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

  Future<List<Map<String, dynamic>>> photoNotes(
    String photoId,
  ) async => List<Map<String, dynamic>>.from(
    await db
        .from('photo_notes')
        .select(
          'id,photo_id,author_id,body,created_at,profiles!photo_notes_author_id_fkey(display_name,avatar_path)',
        )
        .eq('photo_id', photoId)
        .order('created_at'),
  );

  Future<List<Map<String, dynamic>>> guestbookEntries(String galleryId) async {
    final entries = List<Map<String, dynamic>>.from(
      await db
          .from('guestbook_entries')
          .select(
            'id,gallery_id,parent_id,author_id,body,created_at,profiles!guestbook_entries_author_id_fkey(display_name,avatar_path)',
          )
          .eq('gallery_id', galleryId)
          .order('created_at'),
    );
    if (entries.isEmpty) return entries;
    final ids = entries.map((entry) => entry['id'] as String).toList();
    final glows = await db
        .from('guestbook_glows')
        .select('entry_id,user_id')
        .inFilter('entry_id', ids);
    final counts = <String, int>{};
    final mine = <String>{};
    for (final glow in glows) {
      final id = glow['entry_id'] as String;
      counts[id] = (counts[id] ?? 0) + 1;
      if (glow['user_id'] == uid) mine.add(id);
    }
    for (final entry in entries) {
      entry['glow_count'] = counts[entry['id']] ?? 0;
      entry['my_glow'] = mine.contains(entry['id']);
    }
    return entries;
  }

  Future<void> addPhotoNote(String photoId, String body) async => db
      .from('photo_notes')
      .insert({'photo_id': photoId, 'author_id': uid, 'body': body.trim()});

  Future<void> addGuestbookEntry(
    String galleryId,
    String body, {
    String? parentId,
  }) async => db.from('guestbook_entries').insert({
    'gallery_id': galleryId,
    'author_id': uid,
    'body': body.trim(),
    'parent_id': parentId,
  });

  Future<void> guestbookGlow(String entryId, bool active) async {
    if (active) {
      await db
          .from('guestbook_glows')
          .upsert(
            {'entry_id': entryId, 'user_id': uid},
            onConflict: 'entry_id,user_id',
            ignoreDuplicates: true,
          );
    } else {
      await db
          .from('guestbook_glows')
          .delete()
          .eq('entry_id', entryId)
          .eq('user_id', uid);
    }
  }

  Future<void> deletePhotoNote(String id) async =>
      db.from('photo_notes').delete().eq('id', id);

  Future<void> deleteGuestbookEntry(String id) async =>
      db.from('guestbook_entries').delete().eq('id', id);

  Future<String> photoUrl(String path) =>
      db.storage.from('mozaque-photos').createSignedUrl(path, 3600);
  Future<String> publicPhotoUrl(String path) =>
      db.storage.from('mozaque-photos').createSignedUrl(path, 300);
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
    String caption, {
    void Function(int sent, int total)? onProgress,
  }) async {
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
    await _uploadWithProgress(path, bytes, mime, onProgress);
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

  Future<void> _uploadWithProgress(
    String path,
    Uint8List bytes,
    String mime,
    void Function(int sent, int total)? onProgress,
  ) async {
    final bucket = db.storage.from('mozaque-photos');
    final encodedPath = Uri(pathSegments: path.split('/')).path;
    final uri = Uri.parse('${bucket.url}/object/mozaque-photos/$encodedPath');
    final accessToken = (await db.auth.getSession())?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Please sign in again before adding photos.');
    }
    final request = http.StreamedRequest('POST', uri)
      ..headers.addAll(bucket.headers)
      // This progress-aware request bypasses Supabase's auth-aware HTTP
      // client, so explicitly use the current user's JWT for Storage RLS.
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..headers['Content-Type'] = mime
      ..headers['Cache-Control'] = '3600'
      ..headers['x-upsert'] = 'false'
      ..contentLength = bytes.length;
    final client = http.Client();
    try {
      final responseFuture = client.send(request);
      const chunkSize = 64 * 1024;
      var sent = 0;
      onProgress?.call(0, bytes.length);
      for (var start = 0; start < bytes.length; start += chunkSize) {
        final end = (start + chunkSize).clamp(0, bytes.length).toInt();
        request.sink.add(bytes.sublist(start, end));
        sent = end;
        onProgress?.call(sent, bytes.length);
        // Yield between chunks so progress can paint during larger uploads.
        await Future<void>.delayed(Duration.zero);
      }
      await request.sink.close();
      final response = await responseFuture;
      final body = await response.stream.bytesToString();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FormatException(_storageErrorMessage(body, response.statusCode));
      }
    } finally {
      client.close();
    }
  }

  String _storageErrorMessage(String body, int statusCode) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final message =
            decoded['message'] ?? decoded['error'] ?? decoded['msg'];
        if (message is String && message.isNotEmpty) {
          final normalized = message.toLowerCase();
          if (statusCode == 401 || normalized.contains('authorization')) {
            return 'Your sign-in needs refreshing. Please sign out and back in, then try again.';
          }
          return message;
        }
      }
    } catch (_) {}
    return 'Photo upload failed (HTTP $statusCode). Please try again.';
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

  Future<List<Map<String, dynamic>>>
  notifications() async => List<Map<String, dynamic>>.from(
    await db
        .from('notifications')
        .select(
          'id,kind,actor_name,detail,gallery_id,photo_id,created_at,galleries!notifications_gallery_id_fkey(id,title)',
        )
        .order('created_at', ascending: false)
        .limit(30),
  );

  Future<void> deletePhoto(Map<String, dynamic> photo) async {
    final path = photo['storage_path'] as String;
    await db.storage.from('mozaque-photos').remove([path]);
    final deleted = await db
        .from('photos')
        .delete()
        .eq('id', photo['id'])
        .select('id');
    if (deleted.isEmpty) {
      throw StateError('This photo can no longer be deleted.');
    }
  }

  Future<void> deleteGallery(String galleryId) async {
    final rows = await db
        .from('photos')
        .select('storage_path')
        .eq('gallery_id', galleryId);
    final paths = rows
        .map((row) => row['storage_path'] as String)
        .toList(growable: false);

    // This owner-only row temporarily blocks new uploads and authorizes
    // cleanup of stored images, including images in a preserved Mozaque.
    await db
        .from('gallery_deletion_requests')
        .upsert(
          {'gallery_id': galleryId, 'owner_id': uid},
          onConflict: 'gallery_id',
          ignoreDuplicates: true,
        );

    for (var start = 0; start < paths.length; start += 100) {
      final end = (start + 100).clamp(0, paths.length).toInt();
      await db.storage.from('mozaque-photos').remove(paths.sublist(start, end));
    }

    final deleted = await db
        .from('galleries')
        .delete()
        .eq('id', galleryId)
        .eq('owner_id', uid)
        .select('id');
    if (deleted.isEmpty) {
      throw StateError('Only the Mozaque owner can delete this gallery.');
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
