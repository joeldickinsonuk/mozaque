import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'data/mozaque_repository.dart';
import 'theme.dart';

final _db = Supabase.instance.client;
MozaqueRepository get repo => MozaqueRepository(_db);
const _typeLabels = {
  'everyday': 'Everyday',
  'birthday': 'Birthday',
  'wedding': 'Wedding',
  'christmas': 'Christmas',
  'anniversary': 'Anniversary',
  'holiday': 'Holiday',
  'other': 'Another moment',
};

enum _InviteAction { copy, share }

class MozaqueApp extends StatelessWidget {
  const MozaqueApp({super.key, required this.configured});
  final bool configured;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mozaque',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: configured ? const AuthGate() : const SetupScreen(),
  );
}

class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 410),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BrandMark(),
                const SizedBox(height: 35),
                const Text(
                  'Your people.\nYour memories.',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 39,
                    height: 1.13,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 13),
                const Text(
                  'Mozaque needs its Supabase project connection before you can sign in. Check the project setup and run this app again.',
                  style: TextStyle(color: muted, fontSize: 16, height: 1.55),
                ),
                const SizedBox(height: 26),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFFE6E8EF)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quick setup',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 9),
                      Text(
                        '1. Open the Mozaque Supabase project\n2. Check that its schema migration has completed\n3. Launch the app with the configured project URL and publishable key',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.8,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 19),
                const Text(
                  'The photo bucket is private. Row Level Security keeps each Mozaque and upload limited to its members.',
                  style: TextStyle(color: muted, fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: _db.auth.onAuthStateChange,
    initialData: AuthState(
      AuthChangeEvent.initialSession,
      _db.auth.currentSession,
    ),
    builder: (context, snapshot) {
      final session = snapshot.data?.session;
      if (session != null &&
          snapshot.data?.event == AuthChangeEvent.passwordRecovery) {
        return const _PasswordRecoveryScreen();
      }
      if (session == null) return const SignInScreen();
      return const HomeShell();
    },
  );
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _new = false, _busy = false, _obscure = true;
  bool _resetSent = false;
  bool _confirmationSent = false;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (_new) {
        String? emailRedirectTo;
        if (kIsWeb && Uri.base.queryParameters.containsKey('invite')) {
          emailRedirectTo = Uri.base.toString();
        } else if (!kIsWeb) {
          try {
            final pendingLink = await AppLinks().getInitialLink();
            if (pendingLink?.scheme == 'mozaque' &&
                pendingLink?.host == 'invite') {
              emailRedirectTo = pendingLink.toString();
            }
          } catch (_) {}
        }
        final r = await _db.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          emailRedirectTo: emailRedirectTo,
          data: {'display_name': _name.text.trim()},
        );
        if (r.session == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your Mozaque is nearly ready. Check your inbox to confirm your email, then come back to sign in.',
              ),
            ),
          );
          setState(() => _new = false);
        }
      } else {
        await _db.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(
        () => _error =
            'Could not connect right now. Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(
        () =>
            _error = 'Add your email above and we’ll send a secure reset link.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _resetSent = false;
    });
    try {
      final redirectTo = kIsWeb
          ? Uri.base.replace(query: '', fragment: '').toString()
          : 'mozaque://recovery';
      await _db.auth.resetPasswordForEmail(email, redirectTo: redirectTo);
      if (mounted) setState(() => _resetSent = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'We couldn’t send the reset link just now. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendConfirmation() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(
        () => _error =
            'Add your email above and we’ll resend the confirmation link.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _confirmationSent = false;
    });
    try {
      final redirectTo = kIsWeb
          ? Uri.base.toString()
          : 'https://joeldickinsonuk.github.io/mozaque/';
      await _db.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: redirectTo,
      );
      if (mounted) setState(() => _confirmationSent = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'We couldn’t resend the link just now. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(25),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 410),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrandMark(),
                    const SizedBox(height: 35),
                    Text(
                      _new
                          ? 'A home for your people'
                          : 'Your people.\nYour memories.',
                      style: const TextStyle(
                        fontFamily: 'serif',
                        fontSize: 38,
                        height: 1.14,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _new
                          ? 'Create a private space for the moments you share.'
                          : 'Sign in to find the memories you share.',
                      style: const TextStyle(fontSize: 15, color: muted),
                    ),
                    const SizedBox(height: 27),
                    if (_new) ...[
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Your name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Add your name'
                            : v.trim().length > 60
                            ? 'Keep it under 60 characters'
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      validator: (v) => v == null || !v.contains('@')
                          ? 'Enter a valid email'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (v) => v == null || v.length < 8
                          ? 'Use at least 8 characters'
                          : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (!_new)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _busy ? null : _sendPasswordReset,
                              child: const Text('Forgot your password?'),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _busy ? null : _resendConfirmation,
                              child: const Text('Resend confirmation email'),
                            ),
                          ),
                        ],
                      ),
                    if (_confirmationSent)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 5),
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDF7F3),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'If this account still needs confirmation, a fresh link is on its way. It will return you to Mozaque.',
                          style: TextStyle(
                            color: Color(0xFF306C5A),
                            height: 1.4,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    if (_resetSent)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 5),
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDF7F3),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'If there’s a Mozaque account for that address, a private reset link is on its way. It will bring you back here to choose a new password.',
                          style: TextStyle(
                            color: Color(0xFF306C5A),
                            height: 1.4,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Color(0xFFB34842)),
                        ),
                      ),
                    const SizedBox(height: 19),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 19,
                                height: 19,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_new ? 'Create account' : 'Sign in'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton(
                        onPressed: () => setState(() => _new = !_new),
                        child: Text(
                          _new
                              ? 'Already have an account? Sign in'
                              : 'New to Mozaque? Create an account',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'Private by nature · No public discovery · No DMs',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordRecoveryScreen extends StatefulWidget {
  const _PasswordRecoveryScreen();
  @override
  State<_PasswordRecoveryScreen> createState() =>
      _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<_PasswordRecoveryScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false, _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _db.auth.updateUser(UserAttributes(password: _password.text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your Mozaque password has been updated.'),
          ),
        );
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'We couldn’t update your password. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(25),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 410),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BrandMark(),
                  const SizedBox(height: 34),
                  const Text(
                    'A fresh start.',
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 38,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose a new password for your Mozaque account.',
                    style: TextStyle(color: muted, fontSize: 15),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => value == null || value.length < 8
                        ? 'Use at least 8 characters'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmation,
                    obscureText: _obscure,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (value) => value != _password.text
                        ? 'Those passwords don’t match'
                        : null,
                    onFieldSubmitted: (_) => _save(),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFFB34842)),
                      ),
                    ),
                  const SizedBox(height: 19),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _save,
                      child: _busy
                          ? const SizedBox(
                              width: 19,
                              height: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Save new password'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  List<Map<String, dynamic>> _galleries = [],
      _feed = [],
      _pieces = [],
      _connections = [];
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;
  StreamSubscription<Uri>? _linkSub;
  bool _joining = false;
  @override
  void initState() {
    super.initState();
    _load();
    _links();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  Future<void> _links() async {
    final links = AppLinks();
    try {
      final initial = await links.getInitialLink();
      if (kIsWeb) {
        await _handleLink(Uri.base);
      } else if (initial != null) {
        await _handleLink(initial);
      }
    } catch (_) {}
    _linkSub = links.uriLinkStream.listen(_handleLink);
  }

  Future<void> _handleLink(Uri uri) async {
    final isAppInvite = uri.scheme == 'mozaque' && uri.host == 'invite';
    final isWebInvite = kIsWeb && uri.queryParameters.containsKey('invite');
    if (!isAppInvite && !isWebInvite) return;
    final code = isWebInvite
        ? uri.queryParameters['invite'] ?? ''
        : uri.queryParameters['code'] ??
              (uri.pathSegments.isEmpty ? '' : uri.pathSegments.last);
    if (code.isEmpty || _joining) return;
    _joining = true;
    try {
      final result = await repo.acceptInvite(code);
      if (!mounted) return;
      await _load();
      if (result['kind'] == 'gallery') {
        final id = result['gallery_id'] as String;
        final g = _galleries.where((x) => x['id'] == id).firstOrNull;
        if (g != null) {
          _notice(
            'You’re in “${g['title']}”. Your shared memories are waiting.',
          );
          _openGallery(g);
        }
      } else {
        setState(() => _tab = 2);
        _notice('You’re connected. You can now share privately on Mozaque.');
      }
    } catch (e) {
      if (mounted) _notice(_message(e));
    } finally {
      _joining = false;
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final p = await repo.profile();
      if (p == null)
        throw StateError(
          'Your profile is still being created. Please sign out and back in.',
        );
      final g = await repo.galleries();
      final f = await repo.feed();
      final pieces = await repo.photos(pieces: true);
      final connections = await repo.connections();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _galleries = g;
        _feed = f;
        _pieces = pieces;
        _connections = connections;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object e) => e is PostgrestException
      ? e.message
      : e is AuthException
      ? e.message
      : e is FormatException
      ? e.message
      : 'Something went wrong. Please try again.';
  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _create() async {
    final created = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreateGallerySheet(),
    );
    if (created != null && mounted) {
      await _load();
      _openGallery(created);
    }
  }

  Future<void> _joinWithCode() async {
    final controller = TextEditingController();
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(21, 19, 21, 25),
          decoration: const BoxDecoration(
            color: paper,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'JOIN YOUR PEOPLE',
                style: TextStyle(
                  color: muted,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Enter an invitation code',
                style: TextStyle(fontFamily: 'serif', fontSize: 27, color: ink),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Paste your private code',
                ),
                textCapitalization: TextCapitalization.none,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                  child: const Text('Accept invitation'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (code == null || code.trim().isEmpty) return;
    try {
      final r = await repo.acceptInvite(code);
      await _load();
      if (r['kind'] == 'gallery') {
        final g = _galleries
            .where((x) => x['id'] == r['gallery_id'])
            .firstOrNull;
        if (g != null) {
          _notice(
            'You’re in “${g['title']}”. Your shared memories are waiting.',
          );
          _openGallery(g);
        }
      } else {
        setState(() => _tab = 2);
        _notice('You’re connected. You can now share privately on Mozaque.');
      }
    } catch (e) {
      _notice(_message(e));
    }
  }

  Future<void> _invite({String? galleryId}) async {
    try {
      final code = await repo.invite(galleryId: galleryId);
      final sender = (_profile?['display_name'] as String?)?.trim();
      final senderName = sender == null || sender.isEmpty
          ? 'Someone you know'
          : sender;
      final gallery = _galleries.where((g) => g['id'] == galleryId).firstOrNull;
      final galleryTitle = gallery == null
          ? 'my Mozaque'
          : _presentMozaqueTitle(gallery['title']?.toString() ?? 'my Mozaque');
      final subject = galleryId == null
          ? '$senderName would love to connect on Mozaque'
          : 'An invitation from $senderName to $galleryTitle';
      // Use the live web app as the universal invite destination until the
      // native apps have verified iOS Universal Links / Android App Links.
      final joinLink = mozaqueInviteLink(code);
      final message = galleryId == null
          ? 'Hi — it’s $senderName. I’m using Mozaque to keep shared photos in a private place for people we know, and I’d love you to join my circle.\n\nJoin me here: $joinLink\n\nIf the link doesn’t open, enter this private code in People: $code\n\nThe invitation expires in seven days.'
          : 'Hi — it’s $senderName. I’ve made a private Mozaque for “$galleryTitle” and would love you to be part of it. It’s a place for the photos and little moments we want to keep together.\n\nJoin “$galleryTitle”: $joinLink\n\nIf the link doesn’t open, enter this private code in People: $code\n\nThe invitation expires in seven days.';
      if (!mounted) return;
      final action = await showDialog<_InviteAction>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            galleryId == null
                ? 'Invite to your circle'
                : 'Invite to $galleryTitle',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Share this private invitation with someone you know. It expires in seven days.',
                ),
                const SizedBox(height: 12),
                SelectableText(message, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(dialogContext, _InviteAction.copy),
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy invite'),
            ),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.pop(dialogContext, _InviteAction.share),
              icon: const Icon(Icons.ios_share),
              label: const Text('Share…'),
            ),
          ],
        ),
      );
      if (!mounted || action == null) return;
      if (action == _InviteAction.copy) {
        await Clipboard.setData(ClipboardData(text: message));
        _notice('Invitation copied. Paste it into a message or email.');
      } else {
        try {
          await SharePlus.instance.share(
            ShareParams(subject: subject, text: message),
          );
        } catch (_) {
          await Clipboard.setData(ClipboardData(text: message));
          _notice('Sharing is unavailable here, so the invitation was copied.');
        }
      }
    } catch (e) {
      _notice(_message(e));
    }
  }

  void _openGallery(Map<String, dynamic> gallery) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => GalleryScreen(
              gallery: gallery,
              onInvite: () => _invite(galleryId: gallery['id']),
              onChanged: _load,
            ),
          ),
        )
        .then((_) {
          _load();
        });
  }

  Future<void> _editName() async {
    final controller = TextEditingController(
      text: _profile?['display_name'] ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty) return;
    try {
      await repo.saveName(value);
      await _load();
    } catch (e) {
      _notice(_message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _FeedPage(
        galleries: _galleries,
        feed: _feed,
        profile: _profile,
        loading: _loading,
        error: _error,
        onRefresh: _load,
        onCreate: _create,
        onOpen: _openGallery,
      ),
      _PiecesPage(
        photos: _pieces,
        loading: _loading,
        onRefresh: _load,
        onOpenGallery: _openGallery,
        galleries: _galleries,
      ),
      _ConnectionsPage(
        connections: _connections,
        onInvite: () => _invite(),
        onJoin: _joinWithCode,
        onRefresh: _load,
      ),
      _MemoryPage(
        galleries: _galleries,
        currentUserId: _db.auth.currentUser?.id ?? '',
        onCreate: _create,
        onJoin: _joinWithCode,
        onOpen: _openGallery,
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(onProfile: _editName, onSignOut: () => _db.auth.signOut()),
            Expanded(child: pages[_tab]),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dynamic_feed_outlined),
            selectedIcon: Icon(Icons.dynamic_feed),
            label: 'Feed',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Pieces',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'People',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: 'Mozaques',
          ),
        ],
      ),
      floatingActionButton: _tab == 0 || _tab == 3
          ? MediaQuery.sizeOf(context).width < 600
                ? FloatingActionButton(
                    tooltip: 'New Mozaque',
                    onPressed: _create,
                    child: const Icon(Icons.add),
                  )
                : FloatingActionButton.extended(
                    onPressed: _create,
                    icon: const Icon(Icons.add),
                    label: const Text('New Mozaque'),
                  )
          : null,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onProfile, required this.onSignOut});
  final VoidCallback onProfile, onSignOut;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(19, 9, 16, 7),
    child: Row(
      children: [
        const BrandMark(compact: true),
        const SizedBox(width: 9),
        const Text(
          'Mozaque',
          style: TextStyle(
            color: ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -.45,
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Your profile',
          onPressed: onProfile,
          icon: const Icon(Icons.account_circle_outlined),
        ),
        IconButton(
          tooltip: 'Sign out',
          onPressed: onSignOut,
          icon: const Icon(Icons.logout_rounded, color: muted),
        ),
      ],
    ),
  );
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: compact ? 34 : 47,
        height: compact ? 34 : 47,
        padding: EdgeInsets.all(compact ? 5 : 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F2FF),
          borderRadius: BorderRadius.circular(compact ? 11 : 15),
        ),
        child: Transform.rotate(
          angle: -.08,
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              BrandTile(const Color(0xFF4A61F0)),
              BrandTile(Color(0xFFA36CE3)),
              BrandTile(Color(0xFFE8B640)),
              BrandTile(Color(0xFF42AA9B)),
            ],
          ),
        ),
      ),
      if (!compact) ...[
        const SizedBox(width: 11),
        const Text(
          'Mozaque',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -.6,
            color: ink,
          ),
        ),
      ],
    ],
  );
}

class BrandTile extends StatelessWidget {
  const BrandTile(this.color, {super.key});
  final Color color;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}

class _FeedPage extends StatelessWidget {
  const _FeedPage({
    required this.galleries,
    required this.feed,
    required this.profile,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onCreate,
    required this.onOpen,
  });
  final List<Map<String, dynamic>> galleries, feed;
  final Map<String, dynamic>? profile;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final VoidCallback onCreate;
  final ValueChanged<Map<String, dynamic>> onOpen;
  @override
  Widget build(BuildContext context) {
    final name =
        (profile?['display_name'] as String?)?.split(' ').first ?? 'friend';
    final echoes = _echoes(galleries, feed);
    final showEventPreview =
        Uri.base.queryParameters['previewFeedEvents'] == '1';
    final upcoming = _upcomingOccasions(galleries);
    final shared = galleries
        .where((g) => g['audience'] == 'connections')
        .toList();
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 22, 0, 120),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 940),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'YOUR PEOPLE, YOUR MOMENTS',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: muted,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Good to see you, $name.',
                      style: const TextStyle(
                        fontFamily: 'serif',
                        fontSize: 34,
                        height: 1.16,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your memories stay with the people who were there.',
                      style: TextStyle(color: muted, fontSize: 14),
                    ),
                    const SizedBox(height: 7),
                    const Row(
                      children: [
                        Icon(Icons.lock_outline, size: 14, color: muted),
                        SizedBox(width: 5),
                        Text(
                          'A private feed for your circle',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    if (showEventPreview) ...[
                      _EventPreview(),
                      const SizedBox(height: 20),
                    ],
                    ...echoes.map(
                      (e) => _TimelineCard(
                        kind: 'ECHO',
                        title: 'One year ago this week',
                        detail:
                            '${_presentMozaqueTitle(e['title']?.toString() ?? 'A Mozaque')} · ${e['echo_years']} ${e['echo_years'] == 1 ? 'year' : 'years'} ago',
                        icon: Icons.history,
                        accent: const Color(0xFF8B62D8),
                        onTap: () => onOpen(e),
                      ),
                    ),
                    ...upcoming.map(
                      (event) => _TimelineCard(
                        kind: event['kind'] as String,
                        title: event['title'] as String,
                        detail: event['detail'] as String,
                        icon: event['icon'] as IconData,
                        accent: event['accent'] as Color,
                        onTap: () {
                          final gallery = event['gallery'];
                          if (gallery is Map<String, dynamic>) onOpen(gallery);
                        },
                      ),
                    ),
                    ...shared.map(
                      (g) => _TimelineCard(
                        kind: 'SHARED WITH YOUR CIRCLE',
                        title: _presentMozaqueTitle(
                          g['title']?.toString() ?? 'A Mozaque',
                        ),
                        detail: 'A private Mozaque shared with connections',
                        icon: Icons.people_outline,
                        accent: const Color(0xFF3A9B8B),
                        onTap: () => onOpen(g),
                      ),
                    ),
                    if (echoes.isNotEmpty ||
                        upcoming.isNotEmpty ||
                        shared.isNotEmpty)
                      const SizedBox(height: 18),
                    Row(
                      children: [
                        const Text(
                          'Your feed',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${feed.length} ${feed.length == 1 ? 'photo' : 'photos'}',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (error != null)
                      _ErrorCard(message: error!, onRetry: onRefresh)
                    else if (loading && feed.isEmpty)
                      const _LoadingCards()
                    else if (feed.isEmpty)
                      _EmptyCard(
                        icon: Icons.photo_camera_back_outlined,
                        title: 'Your feed is ready',
                        copy:
                            'Create your first Mozaque, invite your people, and add a photo when you’re ready.',
                        action: 'Create a Mozaque',
                        onAction: onCreate,
                      )
                    else
                      ...feed.map(
                        (photo) => _PhotoCard(
                          photo: photo,
                          onGallery: () {
                            final id = photo['gallery_id'];
                            final g = galleries
                                .where((x) => x['id'] == id)
                                .firstOrNull;
                            if (g != null) onOpen(g);
                          },
                          onRefresh: onRefresh,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<Map<String, dynamic>> _upcomingOccasions(
  List<Map<String, dynamic>> galleries,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final events = <Map<String, dynamic>>[];
  for (final gallery in galleries) {
    final date = DateTime.tryParse('${gallery['event_date']}');
    if (date == null) continue;
    final next = DateTime(now.year, date.month, date.day);
    final days = next.difference(today).inDays;
    if (days < 0 || days > 30) continue;
    final years = now.year - date.year;
    final isMilestone =
        days == 0 && gallery['is_recurring'] == true && years > 0;
    if (days == 0 && !isMilestone) continue;
    events.add({
      'gallery': gallery,
      'kind': isMilestone ? 'MILESTONE' : 'COMING UP',
      'title': isMilestone
          ? 'This Mozaque turns $years today'
          : '${_presentMozaqueTitle(gallery['title']?.toString() ?? 'A Mozaque')} is in $days ${days == 1 ? 'day' : 'days'}',
      'detail': _presentMozaqueTitle(
        gallery['title']?.toString() ?? 'A Mozaque',
      ),
      'icon': isMilestone ? Icons.celebration_outlined : Icons.event_outlined,
      'accent': isMilestone ? const Color(0xFFE1A735) : const Color(0xFF4A61F0),
    });
  }
  events.sort((a, b) {
    final aDate = DateTime.tryParse('${(a['gallery'] as Map)['event_date']}')!;
    final bDate = DateTime.tryParse('${(b['gallery'] as Map)['event_date']}')!;
    final aDays = DateTime(
      now.year,
      aDate.month,
      aDate.day,
    ).difference(today).inDays;
    final bDays = DateTime(
      now.year,
      bDate.month,
      bDate.day,
    ).difference(today).inDays;
    return aDays.compareTo(bDays);
  });
  return events;
}

String _presentMozaqueTitle(String value) =>
    value == 'Kobies Birthday' ? "Kobie's Birthday" : value;

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.kind,
    required this.title,
    required this.detail,
    required this.icon,
    required this.accent,
    this.onTap,
  });
  final String kind, title, detail;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 11),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: accent, size: 21),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kind,
                    style: TextStyle(
                      color: accent,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      fontSize: 9,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: const TextStyle(
                      color: ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (onTap != null) const Icon(Icons.chevron_right, color: muted),
          ],
        ),
      ),
    ),
  );
}

class _EventPreview extends StatelessWidget {
  const _EventPreview();
  static const _examples = [
    (
      'NEW MEMORY',
      'Joel added 8 photos',
      "Kobie's Birthday",
      Icons.photo_library_outlined,
      Color(0xFF4A61F0),
    ),
    (
      'INVITATION',
      'Debbie invited you',
      'Christmas 2026',
      Icons.mail_outline,
      Color(0xFF3A9B8B),
    ),
    (
      'ECHO',
      'One year ago today…',
      'Spain, together again',
      Icons.history,
      Color(0xFF8B62D8),
    ),
    (
      'MILESTONE',
      'This Mozaque turns 2 today',
      'A little more of your story',
      Icons.celebration_outlined,
      Color(0xFFE1A735),
    ),
    (
      'COMING UP',
      "Sarah & James' anniversary in 14 days",
      'A date worth keeping close',
      Icons.event_outlined,
      Color(0xFFE07968),
    ),
    (
      'SHARED WITH YOUR CIRCLE',
      'Simon shared Spain 2026',
      'A private memory from his people',
      Icons.people_outline,
      Color(0xFF3A9B8B),
    ),
  ];
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF2E7CA)),
        ),
        child: const Row(
          children: [
            Icon(Icons.visibility_outlined, size: 16, color: Color(0xFF987230)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Design preview · sample moments',
                style: TextStyle(
                  color: Color(0xFF80622E),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth > 720
              ? (constraints.maxWidth - 12) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 0,
            children: [
              for (final e in _examples)
                SizedBox(
                  width: width,
                  child: _TimelineCard(
                    kind: e.$1,
                    title: e.$2,
                    detail: e.$3,
                    icon: e.$4,
                    accent: e.$5,
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

List<Map<String, dynamic>> _echoes(
  List<Map<String, dynamic>> galleries,
  List<Map<String, dynamic>> feed,
) {
  final now = DateTime.now();
  final output = <Map<String, dynamic>>[];
  for (final g in galleries) {
    if (!g['is_recurring'] || !feed.any((p) => p['gallery_id'] == g['id']))
      continue;
    final d = DateTime.tryParse(g['event_date']);
    if (d == null || now.year - d.year < 1) continue;
    final day = d.day.clamp(1, DateTime(now.year, d.month + 1, 0).day);
    final date = DateTime(now.year, d.month, day);
    final diff = now
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;
    if (diff >= 0 && diff < 7) {
      output.add({...g, 'echo_years': now.year - d.year});
    }
  }
  output.sort(
    (a, b) => (a['event_date'] as String).compareTo(b['event_date'] as String),
  );
  return output;
}

class _PhotoCard extends StatefulWidget {
  const _PhotoCard({
    required this.photo,
    required this.onGallery,
    required this.onRefresh,
  });
  final Map<String, dynamic> photo;
  final VoidCallback onGallery;
  final Future<void> Function() onRefresh;
  @override
  State<_PhotoCard> createState() => _PhotoCardState();
}

class _PhotoCardState extends State<_PhotoCard> {
  bool _busy = false;
  Future<void> _toggle(String table, bool active) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (table == 'piece') {
        await repo.keepPiece(widget.photo['id'], active);
      } else {
        await repo.glow(widget.photo['id'], active);
      }
      await widget.onRefresh();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is PostgrestException
                  ? e.message
                  : 'Could not save that change.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.photo;
    final gallery = p['galleries'] as Map<String, dynamic>?;
    final galleryTitle = _presentMozaqueTitle(
      gallery?['title']?.toString() ?? 'A Mozaque',
    );
    final uploader =
        (p['profiles'] as Map<String, dynamic>?)?['display_name'] ?? 'Someone';
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(19, 18, 19, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: widget.onGallery,
                        child: Text(
                          galleryTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ink,
                            fontSize: 19,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${uploader.toString()} added a photo · ${_relativeDate(p['created_at'])}',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                      if ((p['caption'] as String? ?? '').isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          p['caption'] as String,
                          style: const TextStyle(
                            color: Color(0xFF596176),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _Avatar(name: uploader.toString()),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) => _PhotoImage(
              path: p['storage_path'],
              height: (constraints.maxWidth * .68).clamp(260, 600).toDouble(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 5),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _toggle('glow', p['my_glow'] != true),
                  icon: Icon(
                    Icons.local_fire_department_outlined,
                    color: p['my_glow'] == true
                        ? const Color(0xFFE5953D)
                        : muted,
                    size: 19,
                  ),
                  label: Text(
                    p['my_glow'] == true ? 'Glowed' : 'Glow',
                    style: TextStyle(
                      color: p['my_glow'] == true
                          ? const Color(0xFFE5953D)
                          : muted,
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _toggle('piece', p['my_piece'] != true),
                  icon: Icon(
                    p['my_piece'] == true
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                    color: p['my_piece'] == true ? blue : muted,
                    size: 19,
                  ),
                  label: Text(
                    p['my_piece'] == true ? 'Piece kept' : 'Take Piece',
                    style: TextStyle(
                      color: p['my_piece'] == true ? blue : muted,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: widget.onGallery,
                  child: const Text(
                    'View Mozaque',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _shortDate(dynamic value) {
  final d = DateTime.tryParse('$value')?.toLocal();
  if (d == null) return '';
  return '${_months[d.month - 1]} ${d.day}';
}

String _relativeDate(dynamic value) {
  final date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final difference = today.difference(day).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  if (difference > 1 && difference < 7) return '$difference days ago';
  return _shortDate(date.toIso8601String());
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

class _PhotoImage extends StatelessWidget {
  const _PhotoImage({required this.path, this.height = 240});
  final String path;
  final double height;
  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: repo.photoUrl(path),
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return SizedBox(
          height: height,
          child: const Center(
            child: Icon(Icons.broken_image_outlined, color: muted, size: 32),
          ),
        );
      if (!snapshot.hasData)
        return SizedBox(
          height: height,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      return Image.network(
        snapshot.data!,
        width: double.infinity,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => SizedBox(
          height: height,
          child: const Center(
            child: Icon(Icons.broken_image_outlined, color: muted, size: 32),
          ),
        ),
      );
    },
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 34,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFE9EDFF),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      name.isEmpty ? '?' : name[0].toUpperCase(),
      style: const TextStyle(color: blue, fontWeight: FontWeight.w800),
    ),
  );
}

class _PiecesPage extends StatelessWidget {
  const _PiecesPage({
    required this.photos,
    required this.loading,
    required this.onRefresh,
    required this.onOpenGallery,
    required this.galleries,
  });
  final List<Map<String, dynamic>> photos;
  final bool loading;
  final Future<void> Function() onRefresh;
  final ValueChanged<Map<String, dynamic>> onOpenGallery;
  final List<Map<String, dynamic>> galleries;
  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 100),
      children: [
        const Text(
          'YOUR PERSONAL COLLECTION',
          style: TextStyle(
            color: muted,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'My Pieces',
          style: TextStyle(fontFamily: 'serif', fontSize: 34, color: ink),
        ),
        const SizedBox(height: 5),
        const Text(
          'The moments you’ve kept, gathered in one place.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 17),
        if (photos.isEmpty)
          _EmptyCard(
            icon: Icons.bookmark_border,
            title: 'Keep a piece',
            copy: 'Save a photo from any Mozaque and find it here.',
            onAction: onRefresh,
            action: loading ? 'Loading…' : 'Refresh',
          )
        else
          ...photos.map(
            (p) => _PhotoCard(
              photo: p,
              onGallery: () {
                final g = galleries
                    .where((g) => g['id'] == p['gallery_id'])
                    .firstOrNull;
                if (g != null) onOpenGallery(g);
              },
              onRefresh: onRefresh,
            ),
          ),
      ],
    ),
  );
}

class _ConnectionsPage extends StatelessWidget {
  const _ConnectionsPage({
    required this.connections,
    required this.onInvite,
    required this.onJoin,
    required this.onRefresh,
  });
  final List<Map<String, dynamic>> connections;
  final VoidCallback onInvite, onJoin;
  final Future<void> Function() onRefresh;
  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 100),
      children: [
        const Text(
          'YOUR CIRCLE',
          style: TextStyle(
            color: muted,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'People you share with',
          style: TextStyle(fontFamily: 'serif', fontSize: 31, color: ink),
        ),
        const SizedBox(height: 6),
        const Text(
          'Connections are private. No followers or public profiles.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onInvite,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Invite someone'),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onJoin,
                icon: const Icon(Icons.key_outlined),
                label: const Text('Join with code'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        if (connections.isEmpty)
          _EmptyCard(
            icon: Icons.people_outline,
            title: 'Your circle starts here',
            copy: 'Invite someone you know to connect on Mozaque.',
            action: 'Invite someone',
            onAction: onInvite,
          )
        else
          ...connections.map(
            (c) => ListTile(
              leading: _Avatar(name: c['display_name'] ?? '?'),
              title: Text(c['display_name'] ?? 'Mozaque member'),
              subtitle: const Text('Connected privately'),
            ),
          ),
      ],
    ),
  );
}

class _MemoryPage extends StatelessWidget {
  const _MemoryPage({
    required this.galleries,
    required this.currentUserId,
    required this.onCreate,
    required this.onJoin,
    required this.onOpen,
  });
  final List<Map<String, dynamic>> galleries;
  final String currentUserId;
  final VoidCallback onCreate, onJoin;
  final ValueChanged<Map<String, dynamic>> onOpen;
  @override
  Widget build(BuildContext context) {
    final mine = galleries
        .where((g) => g['owner_id'] == currentUserId)
        .toList();
    // The galleries query is already filtered by Supabase RLS. Include every
    // visible gallery owned by someone else, even when access comes from the
    // owner's connections rather than a direct gallery_members row.
    final shared = galleries
        .where((g) => g['owner_id'] != currentUserId)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 100),
      children: [
        const Text(
          'YOUR MOZAQUES',
          style: TextStyle(
            color: muted,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Your Mozaques',
          style: TextStyle(fontFamily: 'serif', fontSize: 34, color: ink),
        ),
        const SizedBox(height: 23),
        _CollectionHeading(title: 'Created by you', count: mine.length),
        const SizedBox(height: 11),
        if (mine.isEmpty)
          _EmptyCard(
            icon: Icons.photo_library_outlined,
            title: 'Make a place for a memory',
            copy: 'A gathering, a birthday, a holiday, or an ordinary Tuesday.',
            action: 'Create a Mozaque',
            onAction: onCreate,
          )
        else
          ...mine.map((g) => _GalleryCard(gallery: g, onTap: () => onOpen(g))),
        const SizedBox(height: 21),
        _CollectionHeading(title: 'Shared with you', count: shared.length),
        const SizedBox(height: 5),
        const Text(
          'Private Mozaques shared with you by invitation or through your circle.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 11),
        if (shared.isEmpty)
          _EmptyCard(
            icon: Icons.mail_outline,
            title: 'Shared Mozaques will find a home here',
            copy:
                'Open a private invite link or enter its code to join a Mozaque.',
            action: 'Enter invite code',
            onAction: onJoin,
          )
        else
          ...shared.map(
            (g) => _GalleryCard(gallery: g, onTap: () => onOpen(g)),
          ),
      ],
    );
  }
}

class _CollectionHeading extends StatelessWidget {
  const _CollectionHeading({required this.title, required this.count});
  final String title;
  final int count;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        title,
        style: const TextStyle(
          color: ink,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      const Spacer(),
      Text('$count', style: const TextStyle(color: muted, fontSize: 12)),
    ],
  );
}

class _GalleryCard extends StatelessWidget {
  const _GalleryCard({required this.gallery, required this.onTap});
  final Map<String, dynamic> gallery;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = _colorFor(gallery['title'] as String);
    return Card(
      margin: const EdgeInsets.only(bottom: 11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 67,
                height: 67,
                decoration: BoxDecoration(
                  color: color.withOpacity(.12),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(
                  Icons.photo_library_outlined,
                  color: color,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            gallery['title'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (gallery['frozen_at'] != null)
                          const Icon(
                            Icons.lock_outline,
                            size: 16,
                            color: muted,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_typeLabels[gallery['event_type']] ?? 'Moment'} · ${_shortDate(gallery['event_date'])}',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(Icons.lock_outline, size: 13, color: muted),
                        const SizedBox(width: 4),
                        Text(
                          gallery['audience'] == 'connections'
                              ? 'Shared with connections'
                              : 'Invite only',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

Color _colorFor(String title) {
  const colors = [
    Color(0xFF5369E9),
    Color(0xFF9A69D6),
    Color(0xFFDBA832),
    Color(0xFF389B8B),
    Color(0xFFE07968),
  ];
  return colors[title.length % colors.length];
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.copy,
    this.action,
    this.onAction,
  });
  final IconData icon;
  final String title, copy;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 31),
        child: Column(
          children: [
            Container(
              width: 49,
              height: 49,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF1FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: blue),
            ),
            const SizedBox(height: 13),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              copy,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 13, height: 1.5),
            ),
            if (action != null) ...[
              const SizedBox(height: 13),
              OutlinedButton(onPressed: onAction, child: Text(action!)),
            ],
          ],
        ),
      ),
    ),
  );
}

class _LoadingCards extends StatelessWidget {
  const _LoadingCards();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(38),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(17),
      child: Column(
        children: [
          Text(message, style: const TextStyle(color: muted)),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

class CreateGallerySheet extends StatefulWidget {
  const CreateGallerySheet({super.key});
  @override
  State<CreateGallerySheet> createState() => _CreateGallerySheetState();
}

class _CreateGallerySheetState extends State<CreateGallerySheet> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(),
      _description = TextEditingController();
  String _type = 'everyday', _policy = 'everyone', _audience = 'invited';
  DateTime _date = DateTime.now();
  bool _recurring = false, _busy = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final created = await repo.createGallery({
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'event_type': _type,
        'event_date':
            '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
        'is_recurring': _recurring,
        'upload_policy': _policy,
        'audience': _audience,
      });
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      setState(
        () => _error = e is PostgrestException
            ? e.message
            : e is StateError
            ? e.message.toString()
            : 'Could not create this Mozaque. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.sizeOf(context).height * .89,
      decoration: const BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(27)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 17, 15, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'A PLACE TO REMEMBER',
                          style: TextStyle(
                            fontSize: 10,
                            color: muted,
                            letterSpacing: 1.3,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Create a Mozaque',
                          style: TextStyle(
                            fontFamily: 'serif',
                            fontSize: 28,
                            color: ink,
                          ),
                        ),
                        Text(
                          'Start a shared Mozaque around a meaningful moment.',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 9, 20, 22),
                  children: [
                    TextFormField(
                      controller: _title,
                      decoration: const InputDecoration(
                        labelText: 'What’s the occasion?',
                        hintText: 'Dickinson family Christmas',
                      ),
                      maxLength: 100,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Give this Mozaque a name'
                          : null,
                    ),
                    const SizedBox(height: 11),
                    TextFormField(
                      controller: _description,
                      decoration: const InputDecoration(
                        labelText: 'A little context (optional)',
                        hintText: 'What would you like everyone to remember?',
                      ),
                      maxLines: 2,
                      maxLength: 1000,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _type,
                      decoration: const InputDecoration(
                        labelText: 'Moment type',
                      ),
                      items: _typeLabels.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _type = v ?? _type),
                    ),
                    const SizedBox(height: 13),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.calendar_month_outlined,
                        color: blue,
                      ),
                      title: const Text('Meaningful date'),
                      subtitle: Text(
                        '${_months[_date.month - 1]} ${_date.day}, ${_date.year}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _chooseDate,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'This date comes around every year',
                        style: TextStyle(fontSize: 14),
                      ),
                      value: _recurring,
                      onChanged: (v) => setState(() => _recurring = v),
                      activeThumbColor: blue,
                    ),
                    const Divider(height: 24),
                    DropdownButtonFormField<String>(
                      value: _policy,
                      decoration: const InputDecoration(
                        labelText: 'Who can add photos?',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'everyone',
                          child: Text('Everyone invited'),
                        ),
                        DropdownMenuItem(
                          value: 'selected',
                          child: Text('Selected contributors'),
                        ),
                        DropdownMenuItem(
                          value: 'owner',
                          child: Text('Just me'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _policy = v ?? _policy),
                    ),
                    const SizedBox(height: 13),
                    DropdownButtonFormField<String>(
                      value: _audience,
                      decoration: const InputDecoration(
                        labelText: 'Who can see this Mozaque?',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'invited',
                          child: Text('People I invite'),
                        ),
                        DropdownMenuItem(
                          value: 'connections',
                          child: Text('All my connections'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _audience = v ?? _audience),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Photos stay private to people with access.',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    const SizedBox(height: 15),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _save,
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Create Mozaque'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({
    super.key,
    required this.gallery,
    required this.onInvite,
    required this.onChanged,
  });
  final Map<String, dynamic> gallery;
  final VoidCallback onInvite;
  final Future<void> Function() onChanged;
  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late Map<String, dynamic> _gallery;
  List<Map<String, dynamic>> _photos = [], _members = [];
  bool _loading = true, _uploading = false, _addingPeople = false;
  bool _canUpload = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _gallery = widget.gallery;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _gallery = await repo.gallery(_gallery['id']);
      _canUpload = await repo.canUpload(_gallery);
      _photos = await repo.photos(galleryId: _gallery['id']);
      _members = await repo.members(_gallery['id']);
      setState(() => _error = null);
    } catch (e) {
      setState(
        () => _error = e is PostgrestException
            ? e.message
            : 'Could not load this Mozaque.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    final selected = await ImagePicker().pickMultiImage(
      imageQuality: 88,
      maxWidth: 2400,
    );
    if (selected.isEmpty || !mounted) return;
    final captionController = TextEditingController();
    final caption = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a caption?'),
        content: TextField(
          controller: captionController,
          maxLength: 500,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'A little context for these photos',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, captionController.text.trim()),
            child: const Text('Add photos'),
          ),
        ],
      ),
    );
    if (!mounted || caption == null) return;
    setState(() => _uploading = true);
    try {
      for (final x in selected) {
        await repo.upload(
          _gallery['id'],
          await x.readAsBytes(),
          x.name,
          caption,
        );
      }
      await _load();
      await widget.onChanged();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is FormatException
                  ? e.message
                  : e is PostgrestException
                  ? e.message
                  : 'Could not add these photos.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _preserve() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Preserve this Mozaque?'),
        content: const Text(
          'Photos will stay as they are. No one will be able to add, remove, or change anything.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Preserve'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await repo.freeze(_gallery['id']);
      await _load();
      await widget.onChanged();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is PostgrestException
                  ? e.message
                  : 'Could not preserve this Mozaque.',
            ),
          ),
        );
    }
  }

  Future<void> _permissions(String key, String value) async {
    try {
      await repo.updateGallery(_gallery['id'], {key: value});
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is PostgrestException
                  ? e.message
                  : 'Could not update permissions.',
            ),
          ),
        );
    }
  }

  Future<void> _role(String id, String role) async {
    try {
      await repo.setRole(_gallery['id'], id, role);
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is PostgrestException
                  ? e.message
                  : 'Could not update this person.',
            ),
          ),
        );
    }
  }

  Future<void> _addPeople() async {
    try {
      final alreadyAdded = _members.map((m) => m['user_id'] as String).toSet();
      final candidates = (await repo.connections())
          .where((person) => !alreadyAdded.contains(person['id']))
          .toList();
      if (!mounted) return;
      if (candidates.isEmpty) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Your circle is ready to grow'),
            content: const Text(
              'Connect with someone from the People tab first. Then you can choose them for this Mozaque.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Done'),
              ),
            ],
          ),
        );
        return;
      }

      final selected = <String>{};
      final peopleToAdd = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => Container(
            height: MediaQuery.sizeOf(context).height * .72,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            decoration: const BoxDecoration(
              color: paper,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'YOUR CIRCLE',
                    style: TextStyle(
                      color: muted,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Who should be here?',
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 26,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Choose the people from your circle who can see this Mozaque.',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView(
                      children: candidates.map((person) {
                        final id = person['id'] as String;
                        final name =
                            person['display_name']?.toString() ?? 'Member';
                        return CheckboxListTile(
                          value: selected.contains(id),
                          onChanged: (checked) => setSheetState(() {
                            if (checked == true) {
                              selected.add(id);
                            } else {
                              selected.remove(id);
                            }
                          }),
                          contentPadding: EdgeInsets.zero,
                          secondary: _Avatar(name: name),
                          title: Text(name),
                          controlAffinity: ListTileControlAffinity.trailing,
                        );
                      }).toList(),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () =>
                                Navigator.pop(sheetContext, selected.toList()),
                      child: Text(
                        selected.isEmpty
                            ? 'Select someone'
                            : 'Add ${selected.length} ${selected.length == 1 ? 'person' : 'people'}',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (peopleToAdd == null || peopleToAdd.isEmpty || !mounted) return;

      setState(() => _addingPeople = true);
      for (final personId in peopleToAdd) {
        await repo.addConnectionToGallery(_gallery['id'], personId);
      }
      await _load();
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added ${peopleToAdd.length} ${peopleToAdd.length == 1 ? 'person' : 'people'} to this Mozaque.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is PostgrestException
                  ? e.message
                  : 'Could not add these people. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _addingPeople = false);
    }
  }

  Future<void> _piece(Map<String, dynamic> p, bool value) async {
    try {
      await repo.keepPiece(p['id'], value);
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is PostgrestException
                  ? e.message
                  : 'Could not save this Piece.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = _gallery['owner_id'] == _db.auth.currentUser?.id;
    final color = _colorFor(_gallery['title']);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mozaque'),
        actions: [
          if (owner)
            IconButton(
              tooltip: 'Invite',
              onPressed: widget.onInvite,
              icon: const Icon(Icons.person_add_alt_1),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'preserve') _preserve();
            },
            itemBuilder: (_) => [
              if (owner && _gallery['frozen_at'] == null)
                const PopupMenuItem(
                  value: 'preserve',
                  child: Text('Preserve this Mozaque'),
                ),
              const PopupMenuItem(
                enabled: false,
                child: Text('Photos stay private'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 34),
          children: [
            Container(
              height: 144,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withOpacity(.12),
                borderRadius: BorderRadius.circular(23),
              ),
              child: Icon(Icons.photo_library_outlined, color: color, size: 52),
            ),
            const SizedBox(height: 17),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _Tag(_typeLabels[_gallery['event_type']] ?? 'Moment'),
                if (_gallery['is_recurring']) const _Tag('Every year'),
                if (_gallery['frozen_at'] != null)
                  const _Tag('Preserved', icon: Icons.lock_outline),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              _gallery['title'],
              style: const TextStyle(
                fontFamily: 'serif',
                fontSize: 32,
                height: 1.15,
                color: ink,
              ),
            ),
            if ((_gallery['description'] as String).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Text(
                  _gallery['description'],
                  style: const TextStyle(color: muted),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: muted,
                ),
                const SizedBox(width: 7),
                Text(
                  _shortDate(_gallery['event_date']),
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(width: 14),
                const Icon(Icons.people_outline, size: 17, color: muted),
                const SizedBox(width: 4),
                Text(
                  '${_members.length + 1} people',
                  style: const TextStyle(color: muted),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (owner &&
                _gallery['audience'] == 'invited' &&
                _gallery['frozen_at'] == null) ...[
              OutlinedButton.icon(
                onPressed: _addingPeople ? null : _addPeople,
                icon: _addingPeople
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.group_add_outlined),
                label: Text(
                  _addingPeople
                      ? 'Adding people…'
                      : 'Add people from your circle',
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (owner) ...[
              DropdownButtonFormField<String>(
                value: _gallery['audience'],
                decoration: const InputDecoration(
                  labelText: 'Who can see it?',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'invited',
                    child: Text('People I invite'),
                  ),
                  DropdownMenuItem(
                    value: 'connections',
                    child: Text('All my connections'),
                  ),
                ],
                onChanged: _gallery['frozen_at'] == null
                    ? (v) {
                        if (v != null) _permissions('audience', v);
                      }
                    : null,
              ),
              const SizedBox(height: 9),
              DropdownButtonFormField<String>(
                value: _gallery['upload_policy'],
                decoration: const InputDecoration(
                  labelText: 'Who can add photos?',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'everyone',
                    child: Text('Everyone invited'),
                  ),
                  DropdownMenuItem(
                    value: 'selected',
                    child: Text('Selected contributors'),
                  ),
                  DropdownMenuItem(value: 'owner', child: Text('Just me')),
                ],
                onChanged: _gallery['frozen_at'] == null
                    ? (v) {
                        if (v != null) _permissions('upload_policy', v);
                      }
                    : null,
              ),
              if (_gallery['upload_policy'] == 'selected' &&
                  _members.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Choose who can add photos',
                          style: TextStyle(
                            color: muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      ..._members.map((m) {
                        final p = m['profiles'] as Map<String, dynamic>?;
                        final name = p?['display_name']?.toString() ?? 'Member';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: _Avatar(name: name),
                          title: Text(name),
                          trailing: DropdownButton<String>(
                            value: m['role'],
                            onChanged: _gallery['frozen_at'] == null
                                ? (v) {
                                    if (v != null) _role(m['user_id'], v);
                                  }
                                : null,
                            items: const [
                              DropdownMenuItem(
                                value: 'viewer',
                                child: Text('Can view'),
                              ),
                              DropdownMenuItem(
                                value: 'contributor',
                                child: Text('Can add'),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Memories',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${_photos.length} photos',
                  style: const TextStyle(color: muted),
                ),
                if (_canUpload)
                  IconButton(
                    onPressed: _uploading ? null : _upload,
                    tooltip: 'Add photos',
                    icon: _uploading
                        ? const SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.add_photo_alternate_outlined,
                            color: blue,
                          ),
                  ),
              ],
            ),
            if (_loading && _photos.isEmpty)
              const Padding(
                padding: EdgeInsets.all(25),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Center(
                child: Text(_error!, style: const TextStyle(color: muted)),
              )
            else if (_photos.isEmpty)
              _EmptyCard(
                icon: Icons.photo_camera_back_outlined,
                title: 'A space for this memory',
                copy: _canUpload
                    ? 'Add the first photo when you’re ready.'
                    : 'This Mozaque is waiting for its first photo.',
              )
            else
              ..._photos.map(
                (p) => _GalleryPhoto(photo: p, onPiece: (v) => _piece(p, v)),
              ),
          ],
        ),
      ),
    );
  }
}

class _GalleryPhoto extends StatefulWidget {
  const _GalleryPhoto({required this.photo, required this.onPiece});
  final Map<String, dynamic> photo;
  final Future<void> Function(bool) onPiece;
  @override
  State<_GalleryPhoto> createState() => _GalleryPhotoState();
}

class _GalleryPhotoState extends State<_GalleryPhoto> {
  bool _piece = false;
  @override
  void initState() {
    super.initState();
    _piece = widget.photo['my_piece'] == true;
  }

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    margin: const EdgeInsets.only(bottom: 11),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PhotoImage(path: widget.photo['storage_path'], height: 250),
        if ((widget.photo['caption'] as String).isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 9, 13, 0),
            child: Text(widget.photo['caption']),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 3),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () async {
                  final next = !_piece;
                  await widget.onPiece(next);
                  if (mounted) setState(() => _piece = next);
                },
                icon: Icon(
                  _piece ? Icons.bookmark : Icons.bookmark_border,
                  size: 18,
                ),
                label: Text(_piece ? 'Kept' : 'Keep a Piece'),
              ),
              const Spacer(),
              Text(
                '${widget.photo['profiles']?['display_name'] ?? 'Someone'}',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.icon});
  final String label;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFEEF0F7),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(icon, size: 13, color: muted),
          ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: muted,
          ),
        ),
      ],
    ),
  );
}
