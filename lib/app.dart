import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
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
const _productDescription =
    'Share photos, notes and guestbook messages in private galleries with people you invite.';

enum _InviteAction { copy, share, email, profileLink }

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
      if (session == null) {
        final sharedSlug = kIsWeb ? mozaqueProfileSlugFromUri(Uri.base) : null;
        if (sharedSlug != null && sharedSlug.isNotEmpty) {
          return _SharedProfileLanding(slug: sharedSlug);
        }
        return const SignInScreen();
      }
      return const HomeShell();
    },
  );
}

class _SharedProfileLanding extends StatefulWidget {
  const _SharedProfileLanding({required this.slug});
  final String slug;

  @override
  State<_SharedProfileLanding> createState() => _SharedProfileLandingState();
}

class _SharedProfileLandingState extends State<_SharedProfileLanding> {
  bool _showAuth = false;
  bool _initialSignup = true;
  late Future<Map<String, dynamic>?> _profile;
  late Future<List<Map<String, dynamic>>> _showcases;

  @override
  void initState() {
    super.initState();
    _profile = repo.lookupProfileSlug(widget.slug);
    _showcases = repo.publicProfileGalleries(widget.slug);
  }

  @override
  Widget build(BuildContext context) {
    if (_showAuth) return SignInScreen(initialSignup: _initialSignup);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: FutureBuilder<Map<String, dynamic>?>(
                future: _profile,
                builder: (context, snapshot) {
                  final profile = snapshot.data;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: BrandMark()),
                      const SizedBox(height: 34),
                      if (snapshot.connectionState != ConnectionState.done)
                        const Center(child: CircularProgressIndicator())
                      else if (snapshot.hasError || profile == null) ...[
                        const Icon(Icons.link_off, size: 48, color: muted),
                        const SizedBox(height: 16),
                        const Text(
                          'This profile link is no longer available.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 22, color: ink),
                        ),
                      ] else ...[
                        const Text(
                          'PERSONAL PROFILE',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: muted,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          profile['display_name']?.toString() ??
                              'Someone you know',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'serif',
                            fontSize: 35,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '@${widget.slug}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: muted),
                        ),
                        const SizedBox(height: 18),
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: _showcases,
                          builder: (context, showcaseSnapshot) {
                            final galleries = showcaseSnapshot.data;
                            if (galleries == null) {
                              return const SizedBox.shrink();
                            }
                            if (galleries.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: Text(
                                  'No public Mozaques yet.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: muted),
                                ),
                              );
                            }
                            return _PublicProfileGalleriesView(
                              galleries: galleries,
                              slug: widget.slug,
                            );
                          },
                        ),
                        const SizedBox(height: 23),
                        FilledButton.icon(
                          onPressed: () => setState(() {
                            _initialSignup = true;
                            _showAuth = true;
                          }),
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('Create an account to connect'),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => setState(() {
                            _initialSignup = false;
                            _showAuth = true;
                          }),
                          child: const Text('Already have an account? Sign in'),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.initialSignup = false});
  final bool initialSignup;
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
  void initState() {
    super.initState();
    _new = widget.initialSignup;
  }

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
        final sharedProfileSlug = kIsWeb
            ? mozaqueProfileSlugFromUri(Uri.base)
            : null;
        if (kIsWeb && Uri.base.queryParameters.containsKey('invite')) {
          emailRedirectTo = Uri.base.toString();
        } else if (sharedProfileSlug != null) {
          emailRedirectTo = mozaqueProfileSignupRedirect(sharedProfileSlug);
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
      final redirectTo = kIsWeb ? Uri.base.toString() : 'https://mozaque.com/';
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
                    const Text(
                      'Private photo galleries for your people.',
                      style: TextStyle(
                        fontFamily: 'serif',
                        fontSize: 36,
                        height: 1.14,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      _productDescription,
                      style: TextStyle(fontSize: 15, color: muted, height: 1.5),
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

class _AttentionNavIcon extends StatefulWidget {
  const _AttentionNavIcon({
    required this.icon,
    required this.pulseToken,
    required this.hasNew,
  });

  final IconData icon;
  final int pulseToken;
  final bool hasNew;

  @override
  State<_AttentionNavIcon> createState() => _AttentionNavIconState();
}

class _AttentionNavIconState extends State<_AttentionNavIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

  @override
  void didUpdateWidget(covariant _AttentionNavIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulseToken != oldWidget.pulseToken) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = IconTheme.of(context).color ?? ink;
    final scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1, end: 1.35), weight: 18),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: .92), weight: 18),
      TweenSequenceItem(tween: Tween(begin: .92, end: 1.16), weight: 22),
      TweenSequenceItem(tween: Tween(begin: 1.16, end: 1), weight: 42),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    final rotation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -.12), weight: 20),
      TweenSequenceItem(tween: Tween(begin: -.12, end: .10), weight: 25),
      TweenSequenceItem(tween: Tween(begin: .10, end: 0), weight: 55),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    final flash = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 28),
      TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 72),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    return SizedBox(
      width: 38,
      height: 32,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Transform.rotate(
              angle: rotation.value,
              child: Transform.scale(
                scale: scale.value,
                child: Icon(
                  widget.icon,
                  color: Color.lerp(
                    baseColor,
                    const Color(0xFFE3A82C),
                    flash.value,
                  ),
                ),
              ),
            ),
            if (_controller.value > .05 && _controller.value < .72)
              Positioned(
                top: -3,
                right: 0,
                child: Opacity(
                  opacity: (1 - _controller.value).clamp(0, 1),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 13,
                    color: Color(0xFFE3A82C),
                  ),
                ),
              ),
            if (widget.hasNew)
              Positioned(
                right: -9,
                top: -5,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3A82C),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: paper, width: 1.5),
                  ),
                  child: const Text(
                    'NEW',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 7,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  Map<String, dynamic>? _activeGallery;
  int _feedPulse = 0, _mozaquesPulse = 0, _piecesPulse = 0;
  bool _hasNewFeed = false, _hasNewMozaques = false, _hasNewPieces = false;
  List<Map<String, dynamic>> _galleries = [],
      _feed = [],
      _notifications = [],
      _pieces = [],
      _connections = [],
      _incomingRequests = [];
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;
  StreamSubscription<Uri>? _linkSub;
  bool _joining = false;
  bool _profileLinkOpened = false;
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
    final profileSlug = mozaqueProfileSlugFromUri(uri);
    if (profileSlug != null && profileSlug.isNotEmpty) {
      if (_profileLinkOpened) return;
      _profileLinkOpened = true;
      await _showSharedProfile(profileSlug);
      return;
    }
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
        setState(() => _tab = 3);
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
      if (p == null) {
        throw StateError(
          'Your profile is still being created. Please sign out and back in.',
        );
      }
      final g = await repo.galleries();
      final f = await repo.feed();
      final notifications = await repo.notifications();
      final pieces = await repo.photos(pieces: true);
      final connections = await repo.connections();
      final incomingRequests = await repo.incomingConnectionRequests();
      if (!mounted) return;
      final userId = _db.auth.currentUser?.id ?? '';
      final attention = await _checkForNewItems(userId, f, notifications, g);
      if (!mounted) return;
      setState(() {
        _profile = p;
        _galleries = g;
        _feed = f;
        _notifications = notifications;
        _pieces = pieces;
        _connections = connections;
        _incomingRequests = incomingRequests;
        if (attention.feed) {
          _feedPulse++;
          _hasNewFeed = _tab != 0;
        }
        if (attention.mozaques) {
          _mozaquesPulse++;
          _hasNewMozaques = _tab != 3;
        }
        if (attention.pieces) {
          _piecesPulse++;
          _hasNewPieces = true;
        }
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<({bool feed, bool mozaques, bool pieces})> _checkForNewItems(
    String userId,
    List<Map<String, dynamic>> feed,
    List<Map<String, dynamic>> notifications,
    List<Map<String, dynamic>> galleries,
  ) async {
    if (userId.isEmpty) {
      return (feed: false, mozaques: false, pieces: false);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final feedKey = 'mozaque_seen_feed_$userId';
      final galleryKey = 'mozaque_seen_shared_galleries_$userId';
      final piecesKey = 'mozaque_unseen_pieces_$userId';
      final latest = _latestActivityMillis([...feed, ...notifications]);
      final savedLatest = prefs.getInt(feedKey);
      final sharedIds = galleries
          .where((g) => g['owner_id']?.toString() != userId)
          .map((g) => g['id'].toString())
          .toSet();
      final savedIds = prefs.getStringList(galleryKey);
      final newFeed = savedLatest != null && latest > savedLatest;
      final newMozaques =
          savedIds != null && sharedIds.any((id) => !savedIds.contains(id));

      // The first visit establishes a baseline. Opening the relevant tab marks
      // everything currently visible as seen, including on a later refresh.
      if (savedLatest == null || _tab == 0) {
        await prefs.setInt(feedKey, latest);
      }
      if (savedIds == null || _tab == 1) {
        await prefs.setStringList(galleryKey, sharedIds.toList());
      }
      final newPieces = _tab != 2 && (prefs.getBool(piecesKey) ?? false);
      if (_tab == 2) await prefs.setBool(piecesKey, false);
      return (
        feed: newFeed && (_tab == 0 || !_hasNewFeed),
        mozaques: newMozaques && (_tab == 1 || !_hasNewMozaques),
        pieces: newPieces && !_hasNewPieces,
      );
    } catch (_) {
      // Attention cues are best-effort; they must never prevent a feed refresh.
      return (feed: false, mozaques: false, pieces: false);
    }
  }

  int _latestActivityMillis(List<Map<String, dynamic>> items) {
    var latest = 0;
    for (final item in items) {
      final value = DateTime.tryParse(item['created_at']?.toString() ?? '');
      if (value != null && value.millisecondsSinceEpoch > latest) {
        latest = value.millisecondsSinceEpoch;
      }
    }
    return latest;
  }

  Future<void> _markTabSeen(int index) async {
    final userId = _db.auth.currentUser?.id ?? '';
    if (userId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (index == 0) {
        await prefs.setInt(
          'mozaque_seen_feed_$userId',
          _latestActivityMillis([..._feed, ..._notifications]),
        );
      } else if (index == 1) {
        final ids = _galleries
            .where((g) => g['owner_id']?.toString() != userId)
            .map((g) => g['id'].toString())
            .toSet();
        await prefs.setStringList(
          'mozaque_seen_shared_galleries_$userId',
          ids.toList(),
        );
      } else if (index == 2) {
        await prefs.setBool('mozaque_unseen_pieces_$userId', false);
      }
    } catch (_) {}
  }

  Future<void> _recordKeptPiece() async {
    final userId = _db.auth.currentUser?.id ?? '';
    if (userId.isEmpty) return;
    if (_tab == 2) {
      await _markTabSeen(2);
      return;
    }
    if (mounted) {
      setState(() {
        _hasNewPieces = true;
        _piecesPulse++;
      });
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('mozaque_unseen_pieces_$userId', true);
    } catch (_) {}
  }

  void _selectTab(int index) {
    setState(() {
      _tab = index;
      _activeGallery = null;
      if (index == 0) _hasNewFeed = false;
      if (index == 1) _hasNewMozaques = false;
      if (index == 2) _hasNewPieces = false;
    });
    unawaited(_markTabSeen(index));
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

  Future<void> _showSharedProfile(String slug) async {
    try {
      final profile = await repo.lookupProfileSlug(slug);
      if (!mounted) return;
      if (profile == null) {
        _notice('This profile link is no longer available.');
        return;
      }
      final showcases = await repo.publicProfileGalleries(slug);
      final targetId = profile['profile_id']?.toString() ?? '';
      final status = targetId == _db.auth.currentUser?.id
          ? 'self'
          : await repo.connectionStatus(targetId);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (sheetContext) => _SharedProfileSheet(
          profile: profile,
          publicGalleries: showcases,
          slug: slug,
          initialStatus: status,
          onConnect: () async {
            final result = await repo.requestConnectionBySlug(slug);
            await _load();
            if (mounted) {
              _notice(
                result == 'connected'
                    ? 'You’re connected. You can now share privately on Mozaque.'
                    : 'Connection request sent. They can accept it when they’re ready.',
              );
            }
            return result;
          },
        ),
      );
    } catch (e) {
      if (mounted) _notice(_message(e));
    }
  }

  Future<void> _shareMyProfile() async {
    var slug = _profile?['profile_slug']?.toString();
    if (slug == null || slug.isEmpty) {
      _notice('Choose your personal link in your profile settings first.');
      await _editProfile();
      slug = _profile?['profile_slug']?.toString();
    }
    if (slug == null || slug.isEmpty || !mounted) return;
    final link = mozaqueProfileLink(slug);
    try {
      await SharePlus.instance.share(
        ShareParams(
          subject: 'Connect with me on Mozaque',
          text:
              'Connect with me on Mozaque. My photos stay private unless I share a Mozaque with you.\n\n$link',
        ),
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) _notice('Your Mozaque link was copied.');
    }
  }

  Future<void> _respondToConnectionRequest(
    String requestId,
    bool accept,
  ) async {
    try {
      await repo.respondToConnectionRequest(requestId, accept: accept);
      await _load();
      if (mounted) {
        _notice(
          accept
              ? 'You’re connected. You can now share privately on Mozaque.'
              : 'Connection request declined.',
        );
      }
    } catch (e) {
      if (mounted) _notice(_message(e));
    }
  }

  Future<void> _create() async {
    final created = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreateGallerySheet(),
    );
    if (created != null && mounted) {
      final publicSettingFailed =
          created.remove('_public_visibility_update_failed') == true;
      await _load();
      if (publicSettingFailed) {
        _notice(
          'Your Mozaque was created, but its public setting could not be saved. Open People & permissions to try again.',
        );
      }
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
        setState(() => _tab = 3);
        _notice('You’re connected. You can now share privately on Mozaque.');
      }
    } catch (e) {
      _notice(_message(e));
    }
  }

  Future<void> _invite({String? galleryId, bool gentleNudge = false}) async {
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
          : gentleNudge
          ? 'A gentle reminder about $galleryTitle'
          : 'An invitation from $senderName to $galleryTitle';
      // Use the live web app as the universal invite destination until the
      // native apps have verified iOS Universal Links / Android App Links.
      final joinLink = mozaqueInviteLink(code);
      final message = galleryId == null
          ? 'Hi — it’s $senderName. I’m using Mozaque to keep shared photos in a private place for people we know, and I’d love you to join my circle.\n\nJoin me here: $joinLink\n\nIf the link doesn’t open, enter this private code in People: $code\n\nThe invitation expires in seven days.'
          : gentleNudge
          ? 'Hi — just a gentle reminder from $senderName. I’ve made a private Mozaque for “$galleryTitle” and would still love you to join when you have a moment. No rush at all.\n\nJoin here: $joinLink\n\nIf the link doesn’t open, enter this private code in People: $code\n\nThis invitation expires in seven days.'
          : 'Hi — it’s $senderName. I’ve made a private Mozaque for “$galleryTitle” and would love you to be part of it. It’s a place for the photos and little moments we want to keep together.\n\nJoin “$galleryTitle”: $joinLink\n\nIf the link doesn’t open, enter this private code in People: $code\n\nThe invitation expires in seven days.';
      if (!mounted) return;
      final action = await showDialog<_InviteAction>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            galleryId == null
                ? 'Invite to your circle'
                : gentleNudge
                ? 'Send a gentle reminder'
                : 'Invite to $galleryTitle',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gentleNudge
                      ? 'Nothing is sent automatically. Choose whether to share this fresh private invite, and who to send it to. It expires in seven days.'
                      : 'Share this private invitation with someone you know. It expires in seven days.',
                ),
                const SizedBox(height: 12),
                SelectableText(message, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F6FC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E8F2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CONNECT FIRST',
                        style: TextStyle(
                          color: muted,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _profile?['profile_slug']?.toString().isNotEmpty == true
                            ? mozaqueProfileLink(
                                _profile!['profile_slug'].toString(),
                              )
                            : 'Create your personal link in your profile settings.',
                        style: const TextStyle(color: ink, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'They can request to connect with you. This link does not give them access to this Mozaque.',
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => Navigator.pop(
                            dialogContext,
                            _InviteAction.profileLink,
                          ),
                          icon: const Icon(Icons.person_add_alt_1),
                          label: Text(
                            _profile?['profile_slug']?.toString().isNotEmpty ==
                                    true
                                ? 'Share connection link'
                                : 'Set up connection link',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.pop(dialogContext, _InviteAction.email),
              icon: const Icon(Icons.email_outlined),
              label: const Text('Email invite'),
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
      if (action == _InviteAction.profileLink) {
        await _shareMyProfile();
        return;
      } else if (action == _InviteAction.copy) {
        await Clipboard.setData(ClipboardData(text: message));
        _notice('Invitation copied. Paste it into a message or email.');
      } else if (action == _InviteAction.email) {
        final emailController = TextEditingController();
        final formKey = GlobalKey<FormState>();
        final email = await showDialog<String>(
          context: context,
          builder: (emailContext) => AlertDialog(
            title: const Text('Email invitation'),
            content: Form(
              key: formKey,
              child: TextFormField(
                controller: emailController,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  hintText: 'name@example.com',
                ),
                validator: (value) {
                  final address = value?.trim() ?? '';
                  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address)
                      ? null
                      : 'Enter a valid email address';
                },
                onFieldSubmitted: (_) {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.pop(emailContext, emailController.text.trim());
                  }
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(emailContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.pop(emailContext, emailController.text.trim());
                  }
                },
                child: const Text('Continue to email'),
              ),
            ],
          ),
        );
        emailController.dispose();
        if (email == null || !mounted) return;
        final mailto = Uri(
          scheme: 'mailto',
          path: email,
          queryParameters: {'subject': subject, 'body': message},
        );
        try {
          final opened = await launchUrl(
            mailto,
            mode: LaunchMode.externalApplication,
          );
          if (!opened) throw StateError('No email app is available.');
        } catch (_) {
          try {
            await SharePlus.instance.share(
              ShareParams(subject: subject, text: 'To: $email\n\n$message'),
            );
          } catch (_) {
            await Clipboard.setData(
              ClipboardData(text: 'To: $email\n\n$subject\n\n$message'),
            );
            _notice('Invite copied. Paste it into an email to $email.');
          }
        }
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
    setState(() => _activeGallery = gallery);
  }

  void _closeGallery() {
    if (_activeGallery == null) return;
    setState(() => _activeGallery = null);
    unawaited(_load());
  }

  Future<void> _editProfile() async {
    final controller = TextEditingController(
      text: _profile?['display_name'] ?? '',
    );
    final slugController = TextEditingController(
      text: _profile?['profile_slug']?.toString() ?? '',
    );
    var profileSlug = _profile?['profile_slug']?.toString();
    var avatarPath = _profile?['avatar_path'] as String?;
    var busy = false;
    var memoryRemindersEnabled = _profile?['memory_reminders_enabled'] != false;
    String? error;
    String? deleteError;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Your profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 5),
                _Avatar(
                  name: _profile?['display_name']?.toString() ?? '?',
                  path: avatarPath,
                  size: 76,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          final image = await ImagePicker().pickImage(
                            source: ImageSource.gallery,
                            maxWidth: 1200,
                            maxHeight: 1200,
                            imageQuality: 86,
                          );
                          if (image == null || !dialogContext.mounted) return;
                          final mime = image.mimeType?.toLowerCase();
                          final originalExt = image.name
                              .split('.')
                              .last
                              .toLowerCase();
                          final format = switch (mime) {
                            'image/jpeg' => ('jpg', 'image/jpeg'),
                            'image/png' => ('png', 'image/png'),
                            'image/webp' => ('webp', 'image/webp'),
                            _
                                when originalExt == 'jpg' ||
                                    originalExt == 'jpeg' =>
                              ('jpg', 'image/jpeg'),
                            _ when originalExt == 'png' => ('png', 'image/png'),
                            _ when originalExt == 'webp' => (
                              'webp',
                              'image/webp',
                            ),
                            _ => null,
                          };
                          if (format == null) {
                            setDialogState(() {
                              error = 'Choose a JPEG, PNG or WebP image.';
                            });
                            return;
                          }
                          setDialogState(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            final bytes = await image.readAsBytes();
                            if (bytes.length > 5 * 1024 * 1024) {
                              setDialogState(() {
                                error = 'Choose an image smaller than 5 MB.';
                              });
                              return;
                            }
                            final path = await repo.saveAvatar(
                              bytes: bytes,
                              extension: format.$1,
                              contentType: format.$2,
                            );
                            if (!mounted || !dialogContext.mounted) return;
                            avatarPath = path;
                            setState(() {
                              _profile = {...?_profile, 'avatar_path': path};
                            });
                            await _load();
                            setDialogState(() {});
                          } catch (e) {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                error = _message(e);
                              });
                            }
                          } finally {
                            if (mounted && dialogContext.mounted) {
                              setDialogState(() => busy = false);
                            }
                          }
                        },
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(
                    avatarPath == null ? 'Add a photo' : 'Change photo',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'Your name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: slugController,
                  maxLength: 30,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Your personal Mozaque link',
                    prefixText: 'mozaque.com/',
                    helperText:
                        'Choose a link people can use to request a connection.',
                  ),
                ),
                if (profileSlug != null && profileSlug!.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              final link = mozaqueProfileLink(profileSlug!);
                              try {
                                await SharePlus.instance.share(
                                  ShareParams(
                                    subject: 'Connect with me on Mozaque',
                                    text:
                                        'Connect with me on Mozaque. My photos stay private unless I share a Mozaque with you.\n\n$link',
                                  ),
                                );
                              } catch (_) {
                                await Clipboard.setData(
                                  ClipboardData(text: link),
                                );
                                if (dialogContext.mounted) {
                                  ScaffoldMessenger.of(
                                    dialogContext,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Your Mozaque link was copied.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Share my link'),
                    ),
                  ),
                const SizedBox(height: 8),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Public Mozaques'),
                  subtitle: Text(
                    'Choose public or private inside each Mozaque’s People & permissions settings.',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Echoes and anniversary reminders'),
                  subtitle: const Text(
                    'Resurface meaningful dates in your feed. You can turn this off any time.',
                  ),
                  value: memoryRemindersEnabled,
                  onChanged: busy
                      ? null
                      : (enabled) async {
                          setDialogState(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            await repo.setMemoryReminders(enabled);
                            if (!mounted || !dialogContext.mounted) return;
                            memoryRemindersEnabled = enabled;
                            setState(() {
                              _profile = {
                                ...?_profile,
                                'memory_reminders_enabled': enabled,
                              };
                            });
                            await _load();
                            setDialogState(() {});
                          } catch (e) {
                            if (dialogContext.mounted) {
                              setDialogState(() => error = _message(e));
                            }
                          } finally {
                            if (mounted && dialogContext.mounted) {
                              setDialogState(() => busy = false);
                            }
                          }
                        },
                ),
                const SizedBox(height: 8),
                const Divider(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            final confirmation = TextEditingController();
                            final confirmed = await showDialog<bool>(
                              context: dialogContext,
                              builder: (confirmContext) => StatefulBuilder(
                                builder: (confirmContext, setConfirmState) =>
                                    AlertDialog(
                                      title: const Text('Delete your account?'),
                                      content: SingleChildScrollView(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'This permanently removes your profile, account, every Mozaque you own, and the photos you uploaded. Photos in a Mozaque you own will also be removed for everyone. This cannot be undone.',
                                            ),
                                            const SizedBox(height: 16),
                                            TextField(
                                              controller: confirmation,
                                              autofocus: true,
                                              decoration: const InputDecoration(
                                                labelText:
                                                    'Type DELETE to confirm',
                                              ),
                                            ),
                                            if (deleteError != null ||
                                                error != null) ...[
                                              const SizedBox(height: 10),
                                              Text(
                                                deleteError ?? error!,
                                                style: const TextStyle(
                                                  color: Color(0xFFB42318),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: busy
                                              ? null
                                              : () => Navigator.pop(
                                                  confirmContext,
                                                  false,
                                                ),
                                          child: const Text('Keep my account'),
                                        ),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFFB42318,
                                            ),
                                          ),
                                          onPressed: busy
                                              ? null
                                              : () async {
                                                  if (confirmation.text
                                                          .trim() !=
                                                      'DELETE') {
                                                    setConfirmState(() {
                                                      deleteError =
                                                          'Type DELETE exactly to continue.';
                                                    });
                                                    return;
                                                  }
                                                  setConfirmState(() {
                                                    busy = true;
                                                    deleteError = null;
                                                  });
                                                  try {
                                                    await repo.deleteAccount();
                                                    if (confirmContext
                                                        .mounted) {
                                                      Navigator.pop(
                                                        confirmContext,
                                                        true,
                                                      );
                                                    }
                                                  } catch (e) {
                                                    if (confirmContext
                                                        .mounted) {
                                                      setConfirmState(() {
                                                        deleteError = _message(
                                                          e,
                                                        );
                                                        busy = false;
                                                      });
                                                    }
                                                  }
                                                },
                                          child: busy
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                )
                                              : const Text('Delete account'),
                                        ),
                                      ],
                                    ),
                              ),
                            );
                            confirmation.dispose();
                            if (confirmed == true && dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          },
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('Delete account and data'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB42318),
                    ),
                  ),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(color: Color(0xFFB42318)),
                  ),
              ],
            ),
          ),
          actions: [
            if (avatarPath != null)
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        final oldPath = avatarPath!;
                        setDialogState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await repo.removeAvatar(oldPath);
                          if (!mounted || !dialogContext.mounted) return;
                          avatarPath = null;
                          setState(() {
                            _profile = {...?_profile, 'avatar_path': null};
                          });
                          await _load();
                          setDialogState(() {});
                        } catch (e) {
                          if (dialogContext.mounted) {
                            setDialogState(() => error = _message(e));
                          }
                        } finally {
                          if (mounted && dialogContext.mounted) {
                            setDialogState(() => busy = false);
                          }
                        }
                      },
                child: const Text('Remove photo'),
              ),
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final value = controller.text.trim();
                      if (value.isEmpty) {
                        setDialogState(() => error = 'Add your name first.');
                        return;
                      }
                      setDialogState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await repo.saveName(value);
                        final requestedSlug = slugController.text.trim();
                        if (requestedSlug != (profileSlug ?? '')) {
                          profileSlug = await repo.saveProfileSlug(
                            requestedSlug,
                          );
                        }
                        if (!mounted || !dialogContext.mounted) return;
                        setState(() {
                          _profile = {
                            ...?_profile,
                            'display_name': value,
                            'profile_slug': profileSlug,
                          };
                        });
                        await _load();
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                      } catch (e) {
                        if (dialogContext.mounted) {
                          setDialogState(() => error = _message(e));
                        }
                      } finally {
                        if (mounted && dialogContext.mounted) {
                          setDialogState(() => busy = false);
                        }
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    slugController.dispose();
  }

  Future<void> _showConnectionProfile(Map<String, dynamic> person) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => Container(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
          decoration: const BoxDecoration(
            color: paper,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Avatar(
                  name: person['display_name']?.toString() ?? '?',
                  path: person['avatar_path'] as String?,
                  size: 104,
                ),
                const SizedBox(height: 15),
                Text(
                  person['display_name']?.toString() ?? 'Mozaque member',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'serif',
                    fontSize: 28,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Connected privately',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pages = [
      _FeedPage(
        galleries: _galleries,
        feed: _feed,
        notifications: _notifications,
        profile: _profile,
        loading: _loading,
        error: _error,
        onRefresh: _load,
        onCreate: _create,
        onOpen: _openGallery,
        onOpenConnections: () => _selectTab(3),
        onPieceKept: _recordKeptPiece,
      ),
      _MemoryPage(
        galleries: _galleries,
        currentUserId: _db.auth.currentUser?.id ?? '',
        onCreate: _create,
        onJoin: _joinWithCode,
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
        incomingRequests: _incomingRequests,
        profileSlug: _profile?['profile_slug']?.toString(),
        onInvite: () => _invite(),
        onJoin: _joinWithCode,
        onShareProfile: _shareMyProfile,
        onRespond: _respondToConnectionRequest,
        onRefresh: _load,
        onOpenProfile: _showConnectionProfile,
      ),
    ];
    return PopScope(
      canPop: _activeGallery == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _activeGallery != null) _closeGallery();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              if (_activeGallery == null)
                _TopBar(
                  onProfile: _editProfile,
                  onSignOut: () => _db.auth.signOut(),
                  profileName: _profile?['display_name']?.toString() ?? '?',
                  avatarPath: _profile?['avatar_path'] as String?,
                ),
              Expanded(
                child: _activeGallery == null
                    ? pages[_tab]
                    : GalleryScreen(
                        key: ValueKey(_activeGallery!['id']),
                        gallery: _activeGallery!,
                        onInvite: () =>
                            _invite(galleryId: _activeGallery!['id']),
                        onGentleNudge: () => _invite(
                          galleryId: _activeGallery!['id'],
                          gentleNudge: true,
                        ),
                        onChanged: _load,
                        onBack: _closeGallery,
                        onPieceKept: _recordKeptPiece,
                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _selectTab,
          destinations: [
            NavigationDestination(
              icon: _AttentionNavIcon(
                icon: Icons.dynamic_feed_outlined,
                pulseToken: _feedPulse,
                hasNew: _hasNewFeed,
              ),
              selectedIcon: _AttentionNavIcon(
                icon: Icons.dynamic_feed,
                pulseToken: _feedPulse,
                hasNew: _hasNewFeed,
              ),
              label: 'Feed',
            ),
            NavigationDestination(
              icon: _AttentionNavIcon(
                icon: Icons.photo_library_outlined,
                pulseToken: _mozaquesPulse,
                hasNew: _hasNewMozaques,
              ),
              selectedIcon: _AttentionNavIcon(
                icon: Icons.photo_library,
                pulseToken: _mozaquesPulse,
                hasNew: _hasNewMozaques,
              ),
              label: 'Mozaques',
            ),
            NavigationDestination(
              icon: _AttentionNavIcon(
                icon: Icons.bookmark_border,
                pulseToken: _piecesPulse,
                hasNew: _hasNewPieces,
              ),
              selectedIcon: _AttentionNavIcon(
                icon: Icons.bookmark,
                pulseToken: _piecesPulse,
                hasNew: _hasNewPieces,
              ),
              label: 'Pieces',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: _incomingRequests.isNotEmpty,
                label: Text('${_incomingRequests.length}'),
                child: const Icon(Icons.people_outline),
              ),
              selectedIcon: Badge(
                isLabelVisible: _incomingRequests.isNotEmpty,
                label: Text('${_incomingRequests.length}'),
                child: const Icon(Icons.people),
              ),
              label: 'People',
            ),
          ],
        ),
        floatingActionButton: _activeGallery == null && (_tab == 0 || _tab == 1)
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
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onProfile,
    required this.onSignOut,
    required this.profileName,
    required this.avatarPath,
  });
  final VoidCallback onProfile, onSignOut;
  final String profileName;
  final String? avatarPath;
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
          icon: _Avatar(name: profileName, path: avatarPath),
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
    required this.notifications,
    required this.profile,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onCreate,
    required this.onOpen,
    required this.onOpenConnections,
    required this.onPieceKept,
  });
  final List<Map<String, dynamic>> galleries, feed, notifications;
  final Map<String, dynamic>? profile;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final VoidCallback onCreate;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final VoidCallback onOpenConnections;
  final Future<void> Function() onPieceKept;
  @override
  Widget build(BuildContext context) {
    final name =
        (profile?['display_name'] as String?)?.split(' ').first ?? 'friend';
    final remindersEnabled = profile?['memory_reminders_enabled'] != false;
    final echoes = remindersEnabled ? _echoes(galleries, feed) : const [];
    final showEventPreview =
        Uri.base.queryParameters['previewFeedEvents'] == '1';
    final upcoming = remindersEnabled
        ? _upcomingOccasions(galleries)
        : const [];
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
                      'PRIVATE PHOTO GALLERIES',
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
                      _productDescription,
                      style: TextStyle(color: muted, fontSize: 14, height: 1.5),
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
                    ...notifications.map((notification) {
                      final actor =
                          notification['actor_name']?.toString() ?? 'Someone';
                      final gallery =
                          notification['galleries'] as Map<String, dynamic>?;
                      final galleryId = notification['gallery_id'];
                      final galleryName = _presentMozaqueTitle(
                        gallery?['title']?.toString() ?? 'a Mozaque',
                      );
                      final date = _relativeDate(notification['created_at']);
                      final detailText =
                          notification['detail']?.toString() ?? '';
                      late final String kind, title, detail;
                      late final IconData icon;
                      late final Color accent;
                      switch (notification['kind']) {
                        case 'glow':
                          kind = 'NEW GLOW';
                          title = '$actor glowed your photo';
                          detail = 'In $galleryName · $date';
                          icon = Icons.local_fire_department_outlined;
                          accent = const Color(0xFFE5953D);
                        case 'photo_note':
                          kind = 'PHOTO COMMENT';
                          title = '$actor commented on a photo';
                          detail = '“$detailText” · In “$galleryName” · $date';
                          icon = Icons.chat_bubble_outline;
                          accent = const Color(0xFF8B62D8);
                        case 'guestbook_message':
                          kind = 'GUESTBOOK';
                          title = '$actor left a guestbook message';
                          detail = '“$detailText” · In “$galleryName” · $date';
                          icon = Icons.menu_book_outlined;
                          accent = const Color(0xFF3A9B8B);
                        case 'guestbook_reply':
                          kind = 'GUESTBOOK REPLY';
                          title = '$actor replied in the guestbook';
                          detail = '“$detailText” · In “$galleryName” · $date';
                          icon = Icons.reply_outlined;
                          accent = const Color(0xFF3A9B8B);
                        case 'member_added':
                          kind = 'NEW MOZAQUE';
                          title = 'You were added to a Mozaque';
                          detail = '$actor added you to “$galleryName” · $date';
                          icon = Icons.photo_library_outlined;
                          accent = blue;
                        case 'member_joined':
                          kind = 'NEW MEMBER';
                          title = '$actor joined your Mozaque';
                          detail = '“$galleryName” · $date';
                          icon = Icons.people_outline;
                          accent = const Color(0xFF3A9B8B);
                        case 'member_role_changed':
                          kind = 'PERMISSION CHANGED';
                          title = 'Your photo permission changed';
                          detail =
                              '$actor: $detailText in “$galleryName” · $date';
                          icon = Icons.tune;
                          accent = const Color(0xFF8B62D8);
                        case 'gallery_preserved':
                          kind = 'PRESERVED';
                          title = '$actor preserved a Mozaque';
                          detail =
                              '“$galleryName” is now a lasting memory · $date';
                          icon = Icons.lock_outline;
                          accent = const Color(0xFF8B62D8);
                        case 'gallery_settings_changed':
                          kind = 'MOZAQUE UPDATED';
                          title = 'A Mozaque was updated';
                          detail =
                              '$actor: $detailText in “$galleryName” · $date';
                          icon = Icons.edit_outlined;
                          accent = blue;
                        case 'connection_added':
                          kind = 'NEW CONNECTION';
                          title = '$actor accepted your invitation';
                          detail = 'You’re now connected on Mozaque · $date';
                          icon = Icons.person_add_alt_1_outlined;
                          accent = const Color(0xFF3A9B8B);
                        case 'connection_request':
                          kind = 'CONNECTION REQUEST';
                          title = '$actor would like to connect';
                          detail = 'Review their request in People · $date';
                          icon = Icons.person_add_alt_1_outlined;
                          accent = const Color(0xFF3A9B8B);
                        default:
                          kind = 'UPDATE';
                          title = 'There’s something new';
                          detail = detailText;
                          icon = Icons.notifications_none;
                          accent = blue;
                      }
                      return _TimelineCard(
                        kind: kind,
                        title: title,
                        detail: detail,
                        icon: icon,
                        accent: accent,
                        onTap: () {
                          if (notification['kind'] == 'connection_request') {
                            onOpenConnections();
                            return;
                          }
                          final target = galleries
                              .where((g) => g['id'] == galleryId)
                              .firstOrNull;
                          if (target != null) onOpen(target);
                        },
                      );
                    }),
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
                          onPieceKept: onPieceKept,
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
    this.onPieceKept,
  });
  final Map<String, dynamic> photo;
  final VoidCallback onGallery;
  final Future<void> Function() onRefresh;
  final Future<void> Function()? onPieceKept;
  @override
  State<_PhotoCard> createState() => _PhotoCardState();
}

class _PhotoCardState extends State<_PhotoCard> {
  String? _busyAction;
  Map<String, dynamic>? _updatedPhoto;

  @override
  void didUpdateWidget(covariant _PhotoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo['my_glow'] != widget.photo['my_glow'] ||
        oldWidget.photo['my_piece'] != widget.photo['my_piece'] ||
        oldWidget.photo['glow_count'] != widget.photo['glow_count']) {
      _updatedPhoto = null;
    }
  }

  Future<void> _toggle(String table, bool active) async {
    if (_busyAction != null) return;
    final action = table == 'piece' ? 'piece' : 'glow';
    setState(() => _busyAction = action);
    try {
      if (table == 'piece') {
        await repo.keepPiece(widget.photo['id'], active);
      } else {
        await repo.glow(widget.photo['id'], active);
      }
      if (!mounted) return;
      if (table == 'piece' && active) {
        await widget.onPieceKept?.call();
      }
      final current = _updatedPhoto ?? widget.photo;
      setState(() {
        _updatedPhoto = {
          ...current,
          if (table == 'piece') 'my_piece': active,
          if (table == 'glow') 'my_glow': active,
          if (table == 'glow')
            'glow_count':
                (((current['glow_count'] as num?)?.toInt() ?? 0) +
                        (active ? 1 : -1))
                    .clamp(0, 1000000),
        };
        _busyAction = null;
      });
      unawaited(widget.onRefresh());
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
      if (mounted && _busyAction != null) {
        setState(() => _busyAction = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _updatedPhoto ?? widget.photo;
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
                _Avatar(
                  name: uploader.toString(),
                  path:
                      (p['profiles'] as Map<String, dynamic>?)?['avatar_path']
                          as String?,
                ),
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
            padding: const EdgeInsets.fromLTRB(8, 3, 8, 7),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 390;
                final glowCount = (p['glow_count'] as num?)?.toInt() ?? 0;
                return Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 0,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        foregroundColor: p['my_glow'] == true
                            ? const Color(0xFFE5953D)
                            : muted,
                      ),
                      onPressed: _busyAction == null
                          ? () => _toggle('glow', p['my_glow'] != true)
                          : null,
                      icon: _busyAction == 'glow'
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.local_fire_department_outlined,
                              color: p['my_glow'] == true
                                  ? const Color(0xFFE5953D)
                                  : muted,
                              size: 19,
                            ),
                      label: Text(glowCount == 0 ? 'Glow' : '$glowCount'),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                      ),
                      onPressed: _busyAction == null
                          ? () => _toggle('piece', p['my_piece'] != true)
                          : null,
                      icon: _busyAction == 'piece'
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              p['my_piece'] == true
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                              color: p['my_piece'] == true ? blue : muted,
                              size: 19,
                            ),
                      label: Text(
                        p['my_piece'] == true ? 'Piece kept' : 'Take Piece',
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                      ),
                      onPressed: widget.onGallery,
                      child: Text(narrow ? 'Mozaque' : 'View Mozaque'),
                    ),
                  ],
                );
              },
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

class _Avatar extends StatefulWidget {
  const _Avatar({required this.name, this.path, this.size = 34});
  final String name;
  final String? path;
  final double size;

  @override
  State<_Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<_Avatar> {
  Future<String>? _imageUrl;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  @override
  void didUpdateWidget(covariant _Avatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _loadUrl();
  }

  void _loadUrl() {
    final path = widget.path;
    _imageUrl = path == null || path.isEmpty ? null : repo.avatarUrl(path);
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.name.isEmpty ? '?' : widget.name[0].toUpperCase();
    final fallback = Container(
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFFE9EDFF),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: const TextStyle(color: blue, fontWeight: FontWeight.w800),
      ),
    );
    if (_imageUrl == null) return fallback;
    return ClipOval(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: FutureBuilder<String>(
          future: _imageUrl,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return fallback;
            return Image.network(
              snapshot.data!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
            );
          },
        ),
      ),
    );
  }
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
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 100),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 34,
                      color: ink,
                    ),
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
            ),
          ),
        ),
      ],
    ),
  );
}

class _ConnectionsPage extends StatelessWidget {
  const _ConnectionsPage({
    required this.connections,
    required this.incomingRequests,
    required this.profileSlug,
    required this.onInvite,
    required this.onJoin,
    required this.onShareProfile,
    required this.onRespond,
    required this.onRefresh,
    required this.onOpenProfile,
  });
  final List<Map<String, dynamic>> connections;
  final List<Map<String, dynamic>> incomingRequests;
  final String? profileSlug;
  final VoidCallback onInvite, onJoin;
  final VoidCallback onShareProfile;
  final Future<void> Function(String requestId, bool accept) onRespond;
  final Future<void> Function() onRefresh;
  final ValueChanged<Map<String, dynamic>> onOpenProfile;
  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 100),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 31,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'No public search or follower counts. Your photos stay private.',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 20),
                  if (profileSlug == null || profileSlug!.isEmpty)
                    OutlinedButton.icon(
                      onPressed: onShareProfile,
                      icon: const Icon(Icons.link),
                      label: const Text('Set up your personal link'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: onShareProfile,
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Share your Mozaque link'),
                    ),
                  const SizedBox(height: 14),
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
                  if (incomingRequests.isNotEmpty) ...[
                    Text(
                      'CONNECTION REQUESTS  ·  ${incomingRequests.length}',
                      style: const TextStyle(
                        color: muted,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 7),
                    ...incomingRequests.map((request) {
                      final person =
                          request['profiles'] as Map<String, dynamic>?;
                      final name =
                          person?['display_name']?.toString() ?? 'Someone';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 9),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                          child: Column(
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: _Avatar(
                                  name: name,
                                  path: person?['avatar_path'] as String?,
                                ),
                                title: Text(name),
                                subtitle: const Text(
                                  'Would like to connect with you',
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () => onRespond(
                                        request['id'].toString(),
                                        false,
                                      ),
                                      child: const Text('Decline'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () => onRespond(
                                        request['id'].toString(),
                                        true,
                                      ),
                                      child: const Text('Accept'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 14),
                  ],
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
                        onTap: () => onOpenProfile(c),
                        leading: _Avatar(
                          name: c['display_name'] ?? '?',
                          path: c['avatar_path'] as String?,
                        ),
                        title: Text(c['display_name'] ?? 'Mozaque member'),
                        subtitle: const Text('Connected privately'),
                        trailing: const Icon(Icons.chevron_right, color: muted),
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

class _SharedProfileSheet extends StatefulWidget {
  const _SharedProfileSheet({
    required this.profile,
    required this.publicGalleries,
    required this.slug,
    required this.initialStatus,
    required this.onConnect,
  });
  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> publicGalleries;
  final String slug;
  final String initialStatus;
  final Future<String> Function() onConnect;

  @override
  State<_SharedProfileSheet> createState() => _SharedProfileSheetState();
}

class _SharedProfileSheetState extends State<_SharedProfileSheet> {
  late String _status = widget.initialStatus;
  bool _busy = false;
  String? _error;

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await widget.onConnect();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not send the request. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.profile['display_name']?.toString() ?? 'Mozaque member';
    final canSeeAvatar =
        _status == 'connected' ||
        _status == 'incoming' ||
        _status == 'outgoing';
    final buttonLabel = switch (_status) {
      'self' => 'This is your profile',
      'connected' => 'Connected privately',
      'outgoing' => 'Request sent',
      'incoming' => 'Accept connection request',
      _ => 'Request to connect',
    };
    final canAct = _status == 'none' || _status == 'incoming';
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
      decoration: const BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Avatar(
                name: name,
                path: canSeeAvatar
                    ? widget.profile['avatar_path'] as String?
                    : null,
                size: 84,
              ),
              const SizedBox(height: 14),
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'serif',
                  fontSize: 29,
                  color: ink,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                widget.publicGalleries.isEmpty
                    ? 'A private connection. Their photos stay private unless they share a Mozaque with you.'
                    : 'Mozaques ${name.split(' ').first} has chosen to share.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, height: 1.45),
              ),
              if (widget.publicGalleries.isNotEmpty) ...[
                const SizedBox(height: 16),
                _PublicProfileGalleriesView(
                  galleries: widget.publicGalleries,
                  slug: widget.slug,
                  compact: true,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Color(0xFFB42318))),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: canAct && !_busy ? _connect : null,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(buttonLabel),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublicProfileGalleriesView extends StatelessWidget {
  const _PublicProfileGalleriesView({
    required this.galleries,
    required this.slug,
    this.compact = false,
  });
  final List<Map<String, dynamic>> galleries;
  final String slug;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < galleries.length; index++) ...[
        _PublicProfileGalleryBanner(
          gallery: galleries[index],
          compact: compact,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => _PublicProfileGalleryDetailPage(
                slug: slug,
                summary: galleries[index],
              ),
            ),
          ),
        ),
        if (index + 1 < galleries.length) const SizedBox(height: 14),
      ],
    ],
  );
}

class _PublicProfileGalleryBanner extends StatelessWidget {
  const _PublicProfileGalleryBanner({
    required this.gallery,
    required this.onTap,
    this.compact = false,
  });
  final Map<String, dynamic> gallery;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final photoCount =
        int.tryParse(gallery['photo_count']?.toString() ?? '') ?? 0;
    final date = DateTime.tryParse(gallery['event_date']?.toString() ?? '');
    final eventType = _typeLabels[gallery['event_type']] ?? 'Mozaque';
    final coverPath = gallery['cover_storage_path']?.toString();
    final height = compact ? 132.0 : 190.0;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (coverPath == null || coverPath.isEmpty)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_colorFor(gallery['title']), ink],
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.photo_library_outlined,
                      size: 50,
                      color: Color(0xA6FFFFFF),
                    ),
                  ),
                )
              else
                _PublicPhotoCover(path: coverPath),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x1A10172B), Color(0xD910172B)],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 14,
                bottom: 12,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            gallery['title']?.toString() ?? 'Shared memories',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'serif',
                              fontSize: compact ? 19 : 24,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$eventType${date == null ? '' : ' · ${_months[date.month - 1]} ${date.day}, ${date.year}'} · $photoCount ${photoCount == 1 ? 'photo' : 'photos'}',
                            style: const TextStyle(
                              color: Color(0xFFE7EAF4),
                              fontSize: 12,
                            ),
                          ),
                          if ((gallery['description']?.toString() ?? '')
                              .trim()
                              .isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              gallery['description'].toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFE7EAF4),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (onTap != null)
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 21,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublicPhotoCover extends StatelessWidget {
  const _PublicPhotoCover({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: repo.publicPhotoUrl(path),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const ColoredBox(
          color: Color(0xFFF3F4F8),
          child: Icon(Icons.broken_image_outlined, color: muted),
        );
      }
      if (!snapshot.hasData) {
        return const ColoredBox(
          color: Color(0xFFF3F4F8),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      }
      return Image.network(
        snapshot.data!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const ColoredBox(
          color: Color(0xFFF3F4F8),
          child: Icon(Icons.broken_image_outlined, color: muted),
        ),
      );
    },
  );
}

class _PublicProfileGalleryDetailPage extends StatefulWidget {
  const _PublicProfileGalleryDetailPage({
    required this.slug,
    required this.summary,
  });
  final String slug;
  final Map<String, dynamic> summary;

  @override
  State<_PublicProfileGalleryDetailPage> createState() =>
      _PublicProfileGalleryDetailPageState();
}

class _PublicProfileGalleryDetailPageState
    extends State<_PublicProfileGalleryDetailPage> {
  late Future<Map<String, dynamic>?> _details;

  @override
  void initState() {
    super.initState();
    _details = repo.publicProfileGalleryDetail(
      widget.slug,
      widget.summary['gallery_id'].toString(),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Public Mozaque'),
      leading: IconButton(
        tooltip: 'Back to profile',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    body: FutureBuilder<Map<String, dynamic>?>(
      future: _details,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final gallery = snapshot.data;
        if (snapshot.hasError || gallery == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'This Mozaque is no longer public.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted),
              ),
            ),
          );
        }
        final rawPhotos = gallery['photos'];
        final photos = rawPhotos is List
            ? rawPhotos
                  .whereType<Map>()
                  .map((photo) => Map<String, dynamic>.from(photo))
                  .toList()
            : <Map<String, dynamic>>[];
        final date = DateTime.tryParse(gallery['event_date']?.toString() ?? '');
        final eventType = _typeLabels[gallery['event_type']] ?? 'Mozaque';
        final description = gallery['description']?.toString().trim() ?? '';

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
              children: [
                _PublicProfileGalleryBanner(
                  gallery: {...widget.summary, ...gallery},
                  onTap: null,
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(description, style: const TextStyle(color: muted)),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Memories',
                        style: TextStyle(
                          fontFamily: 'serif',
                          fontSize: 24,
                          color: ink,
                        ),
                      ),
                    ),
                    Text(
                      '${gallery['photo_count'] ?? photos.length} photos',
                      style: const TextStyle(color: muted),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (photos.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Photos will appear here when they’re added.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted),
                    ),
                  )
                else ...[
                  ...photos.map((photo) => _PublicProfilePhoto(photo: photo)),
                  if (photos.length <
                      (int.tryParse(gallery['photo_count']?.toString() ?? '') ??
                          photos.length))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Showing the latest ${photos.length} photos.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _PublicProfilePhoto extends StatelessWidget {
  const _PublicProfilePhoto({required this.photo});
  final Map<String, dynamic> photo;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1.55,
            child: FutureBuilder<String>(
              future: repo.publicPhotoUrl(photo['storage_path'] as String),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const ColoredBox(
                    color: Color(0xFFF3F4F8),
                    child: Icon(Icons.broken_image_outlined, color: muted),
                  );
                }
                if (!snapshot.hasData) {
                  return const ColoredBox(
                    color: Color(0xFFF3F4F8),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                return Image.network(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Color(0xFFF3F4F8),
                    child: Icon(Icons.broken_image_outlined, color: muted),
                  ),
                );
              },
            ),
          ),
          if ((photo['caption']?.toString() ?? '').trim().isNotEmpty)
            ColoredBox(
              color: const Color(0xFFF7F7FB),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                child: Text(
                  photo['caption'].toString(),
                  style: const TextStyle(color: ink, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _MemoryPage extends StatefulWidget {
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
  State<_MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<_MemoryPage> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final mine = widget.galleries
        .where((g) => g['owner_id'] == widget.currentUserId)
        .toList();
    // The galleries query is already filtered by Supabase RLS. Include every
    // visible gallery owned by someone else, even when access comes from the
    // owner's connections rather than a direct gallery_members row.
    final shared = widget.galleries
        .where((g) => g['owner_id'] != widget.currentUserId)
        .toList();
    final showingMine = _selected == 0;
    final visible = showingMine ? mine : shared;

    Widget tab({
      required int index,
      required String label,
      required int count,
    }) {
      final active = _selected == index;
      return Expanded(
        child: Semantics(
          button: true,
          selected: active,
          label: '$label, $count',
          child: InkWell(
            onTap: () => setState(() => _selected = index),
            borderRadius: BorderRadius.circular(13),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 11),
              decoration: BoxDecoration(
                color: active ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(13),
                boxShadow: active
                    ? const [
                        BoxShadow(
                          color: Color(0x120F1B3D),
                          blurRadius: 7,
                          offset: Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? ink : muted,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: TextStyle(
                      color: active ? blue : muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 100),
          children: [
            const Text(
              'PRIVATE PHOTO GALLERIES',
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
            const SizedBox(height: 5),
            const Text(
              'Each Mozaque is a private gallery for photos you share with your people.',
              style: TextStyle(color: muted, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFECEEF5),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Row(
                children: [
                  tab(index: 0, label: 'Created by you', count: mine.length),
                  tab(index: 1, label: 'Shared with you', count: shared.length),
                ],
              ),
            ),
            const SizedBox(height: 17),
            _CollectionHeading(
              title: showingMine ? 'Created by you' : 'Shared with you',
              count: visible.length,
            ),
            if (!showingMine) ...[
              const SizedBox(height: 5),
              const Text(
                'Private Mozaques shared with you by invitation or through your circle.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 11),
            if (visible.isEmpty && showingMine)
              _EmptyCard(
                icon: Icons.photo_library_outlined,
                title: 'Make a place for a memory',
                copy:
                    'A gathering, a birthday, a holiday, or an ordinary Tuesday.',
                action: 'Create a Mozaque',
                onAction: widget.onCreate,
              )
            else if (visible.isEmpty)
              _EmptyCard(
                icon: Icons.mail_outline,
                title: 'Shared Mozaques will find a home here',
                copy:
                    'Open a private invite link or enter its code to join a Mozaque.',
                action: 'Enter invite code',
                onAction: widget.onJoin,
              )
            else
              ...visible.map(
                (g) => _GalleryCard(gallery: g, onTap: () => widget.onOpen(g)),
              ),
          ],
        ),
      ),
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
      Text(
        '$count ${count == 1 ? 'gallery' : 'galleries'}',
        style: const TextStyle(color: muted, fontSize: 12),
      ),
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
    final coverPath = gallery['cover_storage_path'] as String?;
    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: SizedBox(
                height: 166,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (coverPath != null)
                      _PhotoImage(path: coverPath, height: 166)
                    else
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [color.withOpacity(.88), ink],
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              right: 8,
                              top: -25,
                              child: Icon(
                                Icons.auto_awesome_mosaic,
                                size: 150,
                                color: Colors.white.withOpacity(.12),
                              ),
                            ),
                            const Center(
                              child: Icon(
                                Icons.photo_library_outlined,
                                size: 43,
                                color: Color(0xA6FFFFFF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x260F172A),
                            Color(0x00000000),
                            Color(0xC810172B),
                          ],
                          stops: [0, .35, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 13,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(.27),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(.28),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.photo_library_outlined,
                              color: Colors.white,
                              size: 14,
                            ),
                            SizedBox(width: 5),
                            Text(
                              'PHOTO GALLERY',
                              style: TextStyle(
                                color: Colors.white,
                                letterSpacing: .8,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 14,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            gallery['title']?.toString() ?? 'Untitled Mozaque',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                              shadows: [
                                Shadow(color: Color(0x70000000), blurRadius: 9),
                              ],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${_typeLabels[gallery['event_type']] ?? 'Moment'} · ${_shortDate(gallery['event_date'])}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(.92),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              shadows: const [
                                Shadow(color: Color(0x70000000), blurRadius: 8),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Positioned(
                      right: 11,
                      bottom: 13,
                      child: Icon(
                        Icons.chevron_right,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 11, 15, 13),
              child: Row(
                children: [
                  Icon(
                    gallery['audience'] == 'connections'
                        ? Icons.people_outline
                        : Icons.lock_outline,
                    size: 15,
                    color: muted,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      gallery['audience'] == 'connections'
                          ? 'Private · Shared with your connections'
                          : 'Private · People you invite',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                  if (gallery['frozen_at'] != null) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.lock_clock_outlined,
                      size: 15,
                      color: muted,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Preserved',
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ],
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
  bool _recurring = false, _busy = false, _makePublic = false;
  bool _loadingConnections = true;
  List<Map<String, dynamic>> _connections = [];
  final Set<String> _selectedConnectionIds = {};
  Map<String, dynamic>? _createdGallery;
  String? _error;
  @override
  void initState() {
    super.initState();
    _loadConnections();
  }

  Future<void> _loadConnections() async {
    try {
      final connections = await repo.connections();
      if (mounted) setState(() => _connections = connections);
    } catch (_) {
      // Gallery creation should still work if the optional friend list cannot load.
    } finally {
      if (mounted) setState(() => _loadingConnections = false);
    }
  }

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
    if (_createdGallery != null) {
      Navigator.pop(context, _createdGallery);
      return;
    }
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
      _createdGallery = created;
      if (_makePublic) {
        try {
          await repo.setGalleryPublic(created['id'] as String, true);
          created['is_public'] = true;
        } catch (_) {
          created['_public_visibility_update_failed'] = true;
          if (mounted) Navigator.pop(context, created);
          return;
        }
      }
      if (_audience == 'invited' && _selectedConnectionIds.isNotEmpty) {
        try {
          for (final userId in _selectedConnectionIds) {
            await repo.addConnectionToGallery(created['id'], userId);
          }
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _error =
                'Your Mozaque is saved, but we couldn’t add everyone. Open it and choose “Add people from your circle” to finish.';
          });
          return;
        }
      }
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
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _makePublic,
                      onChanged: (value) => setState(() => _makePublic = value),
                      activeThumbColor: blue,
                      title: const Text(
                        'Make this Mozaque public',
                        style: TextStyle(fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Off by default. Anyone with your personal profile link can view its details and photos when this is on. Visitors can’t comment, Glow or keep Pieces. Change it later in People & permissions.',
                        style: TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ),
                    if (_audience == 'invited') ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Invite friends already in your circle',
                              style: TextStyle(
                                color: ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (_selectedConnectionIds.isNotEmpty)
                            Text(
                              '${_selectedConnectionIds.length} selected',
                              style: const TextStyle(color: blue, fontSize: 12),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Choose existing friends now, or invite someone with a link after creating your Mozaque.',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                      const SizedBox(height: 6),
                      if (_loadingConnections)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      else if (_connections.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'No connected friends yet. You can still create a link invite after this Mozaque is made.',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 190),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _connections.length,
                            itemBuilder: (context, index) {
                              final person = _connections[index];
                              final id = person['id'] as String;
                              final name = (person['display_name'] as String?)
                                  ?.trim();
                              return CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Text(
                                  name == null || name.isEmpty
                                      ? 'Mozaque member'
                                      : name,
                                ),
                                value: _selectedConnectionIds.contains(id),
                                activeColor: blue,
                                onChanged: (selected) => setState(() {
                                  if (selected == true) {
                                    _selectedConnectionIds.add(id);
                                  } else {
                                    _selectedConnectionIds.remove(id);
                                  }
                                }),
                              );
                            },
                          ),
                        ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      _makePublic
                          ? 'Public visitors can view photos only. Comments and interactions stay within the Mozaque for its members.'
                          : 'Photos stay private to people with access.',
                      style: const TextStyle(fontSize: 12, color: muted),
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
                            : Text(
                                _createdGallery == null
                                    ? 'Create Mozaque'
                                    : 'Open Mozaque',
                              ),
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
    required this.onGentleNudge,
    required this.onChanged,
    required this.onBack,
    required this.onPieceKept,
  });
  final Map<String, dynamic> gallery;
  final VoidCallback onInvite;
  final VoidCallback onGentleNudge;
  final Future<void> Function() onChanged;
  final VoidCallback onBack;
  final Future<void> Function() onPieceKept;
  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late Map<String, dynamic> _gallery;
  List<Map<String, dynamic>> _photos = [], _members = [];
  bool _loading = true, _uploading = false, _addingPeople = false;
  bool _deleting = false;
  bool _canUpload = false;
  bool _isPublic = false;
  String? _error;
  double? _uploadProgress;
  int _uploadingIndex = 0, _uploadingTotal = 0;
  String _uploadingName = '';
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
      if (_gallery['owner_id'] == _db.auth.currentUser?.id) {
        _isPublic = _gallery['is_public'] == true;
      }
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

  Future<void> _setPublic(bool makePublic) async {
    if (makePublic) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Show this Mozaque publicly?'),
          content: const Text(
            'Anyone with your personal profile link will be able to view this '
            'Mozaque’s details and photos. It will appear alongside any other '
            'Mozaques you’ve made public. Visitors can’t comment, Glow, or keep '
            'Pieces. You can turn this off at any time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Show publicly'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    try {
      await repo.setGalleryPublic(_gallery['id'] as String, makePublic);
      _gallery['is_public'] = makePublic;
      if (!mounted) return;
      setState(() => _isPublic = makePublic);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            makePublic
                ? 'This Mozaque is public on your profile.'
                : 'This Mozaque is private again.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update public profile: $error')),
      );
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
    setState(() {
      _uploading = true;
      _uploadingTotal = selected.length;
      _uploadingIndex = 0;
      _uploadProgress = 0;
    });
    try {
      for (var index = 0; index < selected.length; index++) {
        final x = selected[index];
        if (mounted) {
          setState(() {
            _uploadingIndex = index;
            _uploadingName = x.name;
            _uploadProgress = index / selected.length;
          });
        }
        await repo.upload(
          _gallery['id'],
          await x.readAsBytes(),
          x.name,
          caption,
          onProgress: (sent, total) {
            if (!mounted) return;
            setState(() {
              _uploadProgress =
                  (index + (total == 0 ? 0 : sent / total)) / selected.length;
            });
          },
        );
      }
      if (mounted) setState(() => _uploadProgress = 1);
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
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadProgress = null;
          _uploadingIndex = 0;
          _uploadingTotal = 0;
          _uploadingName = '';
        });
      }
    }
  }

  Future<void> _showPhotoNotes(Map<String, dynamic> photo) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: _ConversationPanel(
            photoId: photo['id'] as String,
            galleryTitle: _gallery['title']?.toString() ?? 'this Mozaque',
            galleryOwner: _gallery['owner_id'] == _db.auth.currentUser?.id,
            readOnly: _gallery['frozen_at'] != null,
          ),
        ),
      ),
    );
  }

  Future<void> _showGuestbook() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: .96,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          child: Material(
            color: const Color(0xFFF7F8FC),
            child: _GuestbookPage(
              galleryId: _gallery['id'] as String,
              galleryTitle: _gallery['title']?.toString() ?? 'Your Mozaque',
              galleryOwner: _gallery['owner_id'] == _db.auth.currentUser?.id,
              readOnly: _gallery['frozen_at'] != null,
            ),
          ),
        ),
      ),
    );
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

  Future<void> _deleteGallery() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this Mozaque?'),
        content: const Text(
          'This permanently deletes the gallery, its photos, comments, guestbook, and invitations for everyone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Mozaque'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB34842),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await repo.deleteGallery(_gallery['id'] as String);
      if (mounted) widget.onBack();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is PostgrestException
                  ? e.message
                  : e is StorageException
                  ? e.message
                  : e is StateError
                  ? e.message.toString()
                  : 'Could not delete this Mozaque. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
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

  Future<void> _editAddYoursPrompt() async {
    final controller = TextEditingController(
      text: _gallery['add_yours_prompt']?.toString() ?? '',
    );
    var saving = false;
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Your “Add yours” prompt'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Give everyone a simple idea for what to add. Leave it blank to use the default prompt.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLength: 140,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'What moment should everyone add?',
                ),
              ),
              if (error != null)
                Text(error!, style: const TextStyle(color: Color(0xFFB42318))),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      try {
                        final prompt = controller.text.trim();
                        await repo.updateGallery(_gallery['id'], {
                          'add_yours_prompt': prompt.isEmpty ? null : prompt,
                        });
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (e) {
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            error = e is PostgrestException
                                ? e.message
                                : 'Could not save this prompt.';
                            saving = false;
                          });
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save prompt'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (saved == true) await _load();
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
                          secondary: _Avatar(
                            name: name,
                            path: person['avatar_path'] as String?,
                          ),
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
      if (value) await widget.onPieceKept();
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

  Future<void> _glow(Map<String, dynamic> p, bool value) async {
    await repo.glow(p['id'], value);
    if (!mounted) return;
    setState(() {
      _photos = _photos.map((photo) {
        if (photo['id'] != p['id']) return photo;
        final count = (photo['glow_count'] as num?)?.toInt() ?? 0;
        return {
          ...photo,
          'my_glow': value,
          'glow_count': (count + (value ? 1 : -1)).clamp(0, 1000000),
        };
      }).toList();
    });
    unawaited(widget.onChanged());
  }

  Future<void> _setCover(String photoId) async {
    try {
      await repo.setGalleryCoverPhoto(_gallery['id'], photoId);
      await _load();
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mozaque cover photo updated.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is PostgrestException
                  ? e.message
                  : 'Could not update this Mozaque’s cover photo.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _deletePhoto(Map<String, dynamic> photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this photo?'),
        content: const Text(
          'It will be removed from this Mozaque for everyone and cannot be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep photo'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete photo'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await repo.deletePhoto(photo);
      await _load();
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo deleted from this Mozaque.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is PostgrestException
                  ? e.message
                  : e is StorageException
                  ? e.message
                  : e is StateError
                  ? e.message.toString()
                  : 'Could not delete this photo.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = _gallery['owner_id'] == _db.auth.currentUser?.id;
    final color = _colorFor(_gallery['title']);
    final coverPhoto =
        _photos
            .where((photo) => photo['id'] == _gallery['cover_photo_id'])
            .firstOrNull ??
        _photos.firstOrNull;
    final title = _gallery['title']?.toString() ?? 'Your Mozaque';
    final description = _gallery['description']?.toString() ?? '';
    final audienceLabel = _gallery['audience'] == 'connections'
        ? 'All my connections'
        : 'People I invite';
    final uploadLabel = switch (_gallery['upload_policy']) {
      'everyone' => 'Everyone can add photos',
      'selected' => 'Selected contributors',
      _ => 'Only you can add photos',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mozaque'),
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton.filledTonal(
            tooltip: 'Guestbook',
            onPressed: _showGuestbook,
            icon: const Icon(Icons.forum_outlined),
          ),
          if (owner)
            IconButton(
              tooltip: 'Invite',
              onPressed: widget.onInvite,
              icon: const Icon(Icons.person_add_alt_1),
            ),
          PopupMenuButton<String>(
            enabled: !_deleting,
            icon: _deleting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'preserve') _preserve();
              if (v == 'delete') _deleteGallery();
              if (v == 'prompt') _editAddYoursPrompt();
              if (v == 'nudge') widget.onGentleNudge();
            },
            itemBuilder: (_) => [
              if (owner && _gallery['frozen_at'] == null)
                PopupMenuItem(
                  value: 'prompt',
                  child: Text(
                    (_gallery['add_yours_prompt'] as String?) == null
                        ? 'Set “Add yours” prompt'
                        : 'Edit “Add yours” prompt',
                  ),
                ),
              if (owner && _gallery['frozen_at'] == null)
                const PopupMenuItem(
                  value: 'nudge',
                  child: Text('Send a gentle invite'),
                ),
              if (owner && _gallery['frozen_at'] == null)
                const PopupMenuItem(
                  value: 'preserve',
                  child: Text('Preserve this Mozaque'),
                ),
              if (owner)
                const PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Delete Mozaque',
                    style: TextStyle(color: Color(0xFFB34842)),
                  ),
                ),
              const PopupMenuItem(
                enabled: false,
                child: Text('Photos stay private'),
              ),
            ],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 940),
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 34),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: SizedBox(
                    height: 232,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (coverPhoto != null)
                          _PhotoImage(
                            path: coverPhoto['storage_path'] as String,
                            height: 232,
                          )
                        else
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  color.withOpacity(.92),
                                  Color.lerp(color, ink, .68)!,
                                ],
                              ),
                            ),
                            child: Stack(
                              children: [
                                Positioned(
                                  right: 18,
                                  top: -36,
                                  child: Icon(
                                    Icons.auto_awesome_mosaic,
                                    size: 190,
                                    color: Colors.white.withOpacity(.10),
                                  ),
                                ),
                                Center(
                                  child: Icon(
                                    _gallery['event_type'] == 'birthday'
                                        ? Icons.cake_outlined
                                        : _gallery['event_type'] == 'wedding'
                                        ? Icons.favorite_border
                                        : Icons.photo_library_outlined,
                                    size: 58,
                                    color: Colors.white.withOpacity(.38),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x00000000),
                                Color(0x1A10172B),
                                Color(0xC810172B),
                              ],
                              stops: [0, .35, 1],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 20,
                          right: 20,
                          bottom: 18,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Wrap(
                                spacing: 7,
                                runSpacing: 5,
                                children: [
                                  _GalleryHeroTag(
                                    _typeLabels[_gallery['event_type']] ??
                                        'Moment',
                                  ),
                                  if (_gallery['is_recurring'] == true)
                                    const _GalleryHeroTag('Every year'),
                                  if (_gallery['frozen_at'] != null)
                                    const _GalleryHeroTag(
                                      'Preserved',
                                      icon: Icons.lock_outline,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'serif',
                                  color: Colors.white,
                                  fontSize: 30,
                                  height: 1.05,
                                  shadows: [
                                    Shadow(
                                      color: Color(0x70000000),
                                      blurRadius: 12,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 7),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_today_outlined,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _shortDate(_gallery['event_date']),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 13),
                                  const Icon(
                                    Icons.people_outline,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${_members.length + 1} people',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              if (description.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(.88),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (owner) ...[
                  const SizedBox(height: 10),
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      leading: const Icon(Icons.manage_accounts_outlined),
                      title: const Text('People & permissions'),
                      subtitle: Text(
                        '${_members.length + 1} people · $audienceLabel · $uploadLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 18),
                          padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F8FC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE4E7F0)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.public_outlined, color: blue),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Public profile',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: ink,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _isPublic
                                          ? 'Public. Anyone with your personal link can view these details and photos. Visitors can’t comment, Glow, or keep Pieces. Other public Mozaques stay public too.'
                                          : 'Private. Turn on to let anyone with your personal link view these details and photos. Visitors can’t comment, Glow, or keep Pieces.',
                                      style: const TextStyle(
                                        color: muted,
                                        fontSize: 12,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Switch.adaptive(
                                value: _isPublic,
                                onChanged: _setPublic,
                                activeColor: blue,
                              ),
                            ],
                          ),
                        ),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 7),
                            child: Text(
                              'MEMBER ACCESS',
                              style: TextStyle(
                                color: muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .8,
                              ),
                            ),
                          ),
                        ),
                        if (_gallery['audience'] == 'invited' &&
                            _gallery['frozen_at'] == null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _addingPeople ? null : _addPeople,
                                icon: _addingPeople
                                    ? const SizedBox(
                                        width: 17,
                                        height: 17,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.group_add_outlined),
                                label: Text(
                                  _addingPeople
                                      ? 'Adding people…'
                                      : 'Add people from your circle',
                                ),
                              ),
                            ),
                          ),
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
                        const SizedBox(height: 14),
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
                            DropdownMenuItem(
                              value: 'owner',
                              child: Text('Just me'),
                            ),
                          ],
                          onChanged: _gallery['frozen_at'] == null
                              ? (v) {
                                  if (v != null)
                                    _permissions('upload_policy', v);
                                }
                              : null,
                        ),
                        if (_gallery['upload_policy'] == 'selected' &&
                            _members.isNotEmpty) ...[
                          const Divider(height: 25),
                          const Padding(
                            padding: EdgeInsets.only(top: 12, bottom: 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Choose who can add photos',
                                style: TextStyle(
                                  color: muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          ..._members.map((m) {
                            final p = m['profiles'] as Map<String, dynamic>?;
                            final name =
                                p?['display_name']?.toString() ?? 'Member';
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: _Avatar(
                                name: name,
                                path: p?['avatar_path'] as String?,
                              ),
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
                      ],
                    ),
                  ),
                ],
                if (_gallery['frozen_at'] == null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.fromLTRB(15, 13, 13, 13),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF1FF),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: const Color(0xFFDDE3FF)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(
                            Icons.add_photo_alternate_outlined,
                            color: blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ADD YOURS',
                                style: TextStyle(
                                  color: blue,
                                  fontSize: 10,
                                  letterSpacing: 1.1,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                (_gallery['add_yours_prompt'] as String?) ??
                                    'Add a photo to this memory',
                                style: const TextStyle(
                                  color: ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (!_canUpload)
                                const Padding(
                                  padding: EdgeInsets.only(top: 3),
                                  child: Text(
                                    'Ask the owner to let you add photos.',
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (_canUpload)
                          IconButton.filledTonal(
                            tooltip: 'Add yours',
                            onPressed: _uploading ? null : _upload,
                            icon: const Icon(Icons.add, color: blue),
                          ),
                      ],
                    ),
                  ),
                  if (owner && _photos.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: widget.onGentleNudge,
                          icon: const Icon(Icons.forward_to_inbox_outlined),
                          label: const Text('Send a gentle invite'),
                        ),
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.add_photo_alternate_outlined,
                                color: blue,
                              ),
                      ),
                  ],
                ),
                if (_uploading)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E6EF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.cloud_upload_outlined,
                                size: 19,
                                color: blue,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Uploading ${_uploadingIndex + 1} of $_uploadingTotal · $_uploadingName',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                '${((_uploadProgress ?? 0) * 100).round()}%',
                                style: const TextStyle(color: muted),
                              ),
                            ],
                          ),
                          const SizedBox(height: 9),
                          LinearProgressIndicator(
                            value: _uploadProgress,
                            minHeight: 5,
                            borderRadius: BorderRadius.circular(9),
                            color: blue,
                            backgroundColor: blue.withOpacity(.12),
                          ),
                        ],
                      ),
                    ),
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
                  ..._photos.map((p) {
                    final canDelete =
                        _gallery['frozen_at'] == null &&
                        (owner || p['uploader_id'] == _db.auth.currentUser?.id);
                    return _GalleryPhoto(
                      photo: p,
                      onGlow: (value) => _glow(p, value),
                      onPiece: (v) => _piece(p, v),
                      onNotes: () => _showPhotoNotes(p),
                      isCover: p['id'] == _gallery['cover_photo_id'],
                      canSetCover: owner && _gallery['frozen_at'] == null,
                      onSetCover: () => _setCover(p['id'] as String),
                      canDelete: canDelete,
                      onDelete: () => _deletePhoto(p),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationPanel extends StatefulWidget {
  const _ConversationPanel({
    required this.galleryTitle,
    required this.galleryOwner,
    required this.readOnly,
    required this.photoId,
  });

  final String photoId, galleryTitle;
  final bool galleryOwner, readOnly;

  @override
  State<_ConversationPanel> createState() => _ConversationPanelState();
}

class _ConversationPanelState extends State<_ConversationPanel> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true, _posting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final entries = await repo.photoNotes(widget.photoId);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyConversationError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _post() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _posting) return;
    setState(() => _posting = true);
    try {
      await repo.addPhotoNote(widget.photoId, body);
      _controller.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyConversationError(e))));
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this message?'),
        content: const Text('It will disappear for everyone in this Mozaque.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await repo.deletePhotoNote(entry['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyConversationError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = _db.auth.currentUser?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Comments on this photo',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'A little context on “${widget.galleryTitle}”. Only people in this Mozaque can read it.',
          style: const TextStyle(color: muted, fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading && _entries.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _entries.isEmpty
              ? Center(
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: muted),
                  ),
                )
              : _entries.isEmpty
              ? Center(
                  child: Text(
                    'Add the first comment to this memory.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: muted),
                  ),
                )
              : ListView.separated(
                  itemCount: _entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    final profile = entry['profiles'] as Map<String, dynamic>?;
                    final author =
                        profile?['display_name']?.toString() ?? 'Someone';
                    final canDelete =
                        !widget.readOnly &&
                        (entry['author_id'] == userId || widget.galleryOwner);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Avatar(
                            name: author,
                            path: profile?['avatar_path'] as String?,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$author · ${_relativeDate(entry['created_at'])}',
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  entry['body'] as String,
                                  style: const TextStyle(
                                    color: ink,
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (canDelete)
                            IconButton(
                              tooltip: 'Remove message',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _delete(entry),
                              icon: const Icon(Icons.delete_outline, size: 19),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 7),
        if (widget.readOnly)
          const Text(
            'This Mozaque has been preserved. Messages are read-only.',
            style: TextStyle(color: muted, fontSize: 12),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLength: 1000,
                  minLines: 1,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Add a note about this moment…',
                    counterText: '',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onSubmitted: (_) => _post(),
                ),
              ),
              const SizedBox(width: 7),
              IconButton.filled(
                tooltip: 'Post message',
                onPressed: _posting ? null : _post,
                icon: _posting
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
              ),
            ],
          ),
      ],
    );
  }
}

String _friendlyConversationError(Object error) => error is PostgrestException
    ? error.message
    : 'Could not load or save this message. Please try again.';

class _GuestbookPage extends StatefulWidget {
  const _GuestbookPage({
    required this.galleryId,
    required this.galleryTitle,
    required this.galleryOwner,
    required this.readOnly,
  });

  final String galleryId, galleryTitle;
  final bool galleryOwner, readOnly;

  @override
  State<_GuestbookPage> createState() => _GuestbookPageState();
}

class _GuestbookPageState extends State<_GuestbookPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _entries = [];
  String? _replyToId, _replyToName, _error;
  bool _loading = true, _posting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final entries = await repo.guestbookEntries(widget.galleryId);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyConversationError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _replies(String entryId) =>
      _entries.where((entry) => entry['parent_id'] == entryId).toList();

  Future<void> _post() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _posting) return;
    setState(() => _posting = true);
    try {
      await repo.addGuestbookEntry(
        widget.galleryId,
        body,
        parentId: _replyToId,
      );
      _controller.clear();
      setState(() {
        _replyToId = null;
        _replyToName = null;
      });
      await _load();
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyConversationError(e))));
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _glow(Map<String, dynamic> entry) async {
    final active = entry['my_glow'] == true;
    try {
      await repo.guestbookGlow(entry['id'] as String, !active);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyConversationError(e))));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this comment?'),
        content: const Text(
          'The comment and its replies will be removed from the guestbook.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await repo.deleteGuestbookEntry(entry['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyConversationError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roots = _entries
        .where((entry) => entry['parent_id'] == null)
        .toList();
    final userId = _db.auth.currentUser?.id;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(17, 5, 12, 13),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Close guestbook',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Guestbook',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      widget.galleryTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh guestbook',
                onPressed: _load,
                icon: const Icon(Icons.refresh, color: blue),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 15),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, size: 15, color: muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'A shared place for wishes, stories and little memories. Only people in this Mozaque can read it.',
                  style: const TextStyle(
                    color: muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading && _entries.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: muted),
                    ),
                  ),
                )
              : roots.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE9ECFF),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Icon(
                            Icons.auto_stories_outlined,
                            color: blue,
                            size: 31,
                          ),
                        ),
                        const SizedBox(height: 15),
                        Text(
                          'Leave the first note',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: ink,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Share a wish, a story, or what this day meant to you.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: muted, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 15, 16, 18),
                  itemCount: roots.length,
                  itemBuilder: (context, index) {
                    final root = roots[index];
                    final replies = _replies(root['id'] as String);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 13),
                      child: Column(
                        children: [
                          _GuestbookMessage(
                            entry: root,
                            isReply: false,
                            canReply: !widget.readOnly,
                            canDelete:
                                !widget.readOnly &&
                                (root['author_id'] == userId ||
                                    widget.galleryOwner),
                            onGlow: () => _glow(root),
                            onReply: () {
                              final profile =
                                  root['profiles'] as Map<String, dynamic>?;
                              setState(() {
                                _replyToId = root['id'] as String;
                                _replyToName =
                                    profile?['display_name']?.toString() ??
                                    'this person';
                              });
                            },
                            onDelete: () => _delete(root),
                          ),
                          if (replies.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 24, top: 8),
                              child: Container(
                                decoration: const BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                      color: Color(0xFFDCE1F3),
                                      width: 2,
                                    ),
                                  ),
                                ),
                                padding: const EdgeInsets.only(left: 11),
                                child: Column(
                                  children: [
                                    for (final reply in replies)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: _GuestbookMessage(
                                          entry: reply,
                                          isReply: true,
                                          canReply: false,
                                          canDelete:
                                              !widget.readOnly &&
                                              (reply['author_id'] == userId ||
                                                  widget.galleryOwner),
                                          onGlow: () => _glow(reply),
                                          onReply: () {},
                                          onDelete: () => _delete(reply),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        if (widget.readOnly)
          const Padding(
            padding: EdgeInsets.all(15),
            child: Text(
              'This Mozaque has been preserved. The guestbook is read-only.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          )
        else
          Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              10,
              14,
              10 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_replyToId != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      children: [
                        const Icon(Icons.reply, size: 16, color: blue),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Replying to ${_replyToName ?? 'comment'}',
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cancel reply',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() {
                            _replyToId = null;
                            _replyToName = null;
                          }),
                          icon: const Icon(Icons.close, size: 17),
                        ),
                      ],
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        maxLength: 1000,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: _replyToId == null
                              ? 'Write a note for everyone…'
                              : 'Write your reply…',
                          counterText: '',
                          filled: true,
                          fillColor: Colors.white,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: Color(0xFFE1E5EF),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: Color(0xFFE1E5EF),
                            ),
                          ),
                        ),
                        onSubmitted: (_) => _post(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Post guestbook message',
                      onPressed: _posting ? null : _post,
                      icon: _posting
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _GuestbookMessage extends StatelessWidget {
  const _GuestbookMessage({
    required this.entry,
    required this.isReply,
    required this.canReply,
    required this.canDelete,
    required this.onGlow,
    required this.onReply,
    required this.onDelete,
  });

  final Map<String, dynamic> entry;
  final bool isReply, canReply, canDelete;
  final VoidCallback onGlow, onReply, onDelete;

  @override
  Widget build(BuildContext context) {
    final profile = entry['profiles'] as Map<String, dynamic>?;
    final author = profile?['display_name']?.toString() ?? 'Someone';
    final active = entry['my_glow'] == true;
    final glowCount = (entry['glow_count'] as num?)?.toInt() ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 9, 3),
      decoration: BoxDecoration(
        color: isReply ? Colors.white.withValues(alpha: .72) : Colors.white,
        border: Border.all(color: const Color(0xFFE5E8F1)),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(name: author, path: profile?['avatar_path'] as String?),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      author,
                      style: const TextStyle(
                        color: ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      _relativeDate(entry['created_at']),
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (canDelete)
                IconButton(
                  tooltip: 'Remove comment',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: const Icon(Icons.more_horiz, color: muted),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(42, 8, 6, 2),
            child: Text(
              entry['body'] as String,
              style: const TextStyle(color: ink, fontSize: 14, height: 1.45),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 34),
            child: Wrap(
              spacing: 2,
              children: [
                TextButton.icon(
                  onPressed: onGlow,
                  style: TextButton.styleFrom(
                    foregroundColor: active ? const Color(0xFFE5953D) : muted,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: Icon(
                    active
                        ? Icons.local_fire_department
                        : Icons.local_fire_department_outlined,
                    size: 17,
                  ),
                  label: Text(glowCount == 0 ? 'Glow' : '$glowCount'),
                ),
                if (canReply)
                  TextButton.icon(
                    onPressed: onReply,
                    style: TextButton.styleFrom(
                      foregroundColor: muted,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.reply, size: 17),
                    label: const Text('Reply'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryPhoto extends StatefulWidget {
  const _GalleryPhoto({
    required this.photo,
    required this.onGlow,
    required this.onPiece,
    required this.onNotes,
    required this.isCover,
    required this.canSetCover,
    required this.onSetCover,
    required this.canDelete,
    required this.onDelete,
  });
  final Map<String, dynamic> photo;
  final Future<void> Function(bool) onGlow;
  final Future<void> Function(bool) onPiece;
  final VoidCallback onNotes;
  final bool isCover, canSetCover;
  final VoidCallback onSetCover;
  final bool canDelete;
  final VoidCallback onDelete;
  @override
  State<_GalleryPhoto> createState() => _GalleryPhotoState();
}

class _GalleryPhotoState extends State<_GalleryPhoto> {
  bool _piece = false, _glow = false, _glowing = false;
  @override
  void initState() {
    super.initState();
    _piece = widget.photo['my_piece'] == true;
    _glow = widget.photo['my_glow'] == true;
  }

  @override
  void didUpdateWidget(covariant _GalleryPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo['my_piece'] != widget.photo['my_piece']) {
      _piece = widget.photo['my_piece'] == true;
    }
    if (oldWidget.photo['my_glow'] != widget.photo['my_glow']) {
      _glow = widget.photo['my_glow'] == true;
    }
  }

  Future<void> _toggleGlow() async {
    if (_glowing) return;
    final next = !_glow;
    setState(() => _glowing = true);
    try {
      await widget.onGlow(next);
      if (mounted) setState(() => _glow = next);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is PostgrestException ? e.message : 'Could not update Glow.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _glowing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final glowCount = (widget.photo['glow_count'] as num?)?.toInt() ?? 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => _PhotoImage(
              path: widget.photo['storage_path'],
              height: (constraints.maxWidth * .68).clamp(260, 600).toDouble(),
            ),
          ),
          if ((widget.photo['caption'] as String).isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 9, 13, 0),
              child: Text(widget.photo['caption']),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 3),
            child: Wrap(
              alignment: WrapAlignment.start,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 2,
              runSpacing: 0,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: _glow ? const Color(0xFFE5953D) : muted,
                  ),
                  onPressed: _glowing ? null : _toggleGlow,
                  icon: _glowing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _glow
                              ? Icons.local_fire_department
                              : Icons.local_fire_department_outlined,
                          color: _glow ? const Color(0xFFE5953D) : muted,
                          size: 18,
                        ),
                  label: Text(glowCount == 0 ? 'Glow' : '$glowCount'),
                ),
                TextButton.icon(
                  onPressed: widget.onNotes,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Comments'),
                ),
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
                if (widget.canSetCover)
                  TextButton.icon(
                    onPressed: widget.isCover ? null : widget.onSetCover,
                    icon: Icon(
                      widget.isCover
                          ? Icons.check_circle_outline
                          : Icons.photo_outlined,
                      size: 18,
                    ),
                    label: Text(
                      widget.isCover ? 'Cover photo' : 'Use as cover',
                    ),
                  ),
                if (widget.canDelete)
                  TextButton.icon(
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete photo'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '${widget.photo['profiles']?['display_name'] ?? 'Someone'}',
                    style: const TextStyle(color: muted, fontSize: 12),
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

class _GalleryHeroTag extends StatelessWidget {
  const _GalleryHeroTag(this.label, {this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(.18),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withOpacity(.28)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
