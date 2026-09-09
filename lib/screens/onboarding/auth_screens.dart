import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_assets.dart';
import '../../data/providers.dart';
import '../../data/repositories/repositories.dart';
import '../../models/onboarding.dart';
import '../../widgets/async.dart';
import '../../state/session.dart';
import '../../state/tips.dart';
import '../../state/tour.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/photo_source.dart';
import '../../widgets/primitives.dart';

/// The onboarding chrome: the hero blue, the cart mark, a title and a
/// subtitle, with the action pinned to the bottom.
class _OnboardingScaffold extends StatelessWidget {
  const _OnboardingScaffold({
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final List<Widget> fields;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: LbmConst.welcomeBlue,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: LbmConst.welcomeBlue,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CircleIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    bare: true,
                    iconSize: 22,
                    color: LbmConst.onWelcome,
                    tooltip: 'Back',
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/'),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(26, 10, 26, 34),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Column(
                          children: [
                            Image.asset(LbmAssets.cartMark, width: 74),
                            const SizedBox(height: 10),
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              style: LbmText.display.copyWith(
                                fontSize: 29,
                                height: 1.1,
                                color: LbmConst.onWelcome,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              subtitle,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.55,
                                color: LbmConst.onWelcome.withValues(
                                  alpha: 0.86,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        ...fields,
                        const SizedBox(height: 24),
                        ...actions,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quieter text action on the onboarding blue.
class _QuietAction extends StatelessWidget {
  const _QuietAction(this.label, {required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.all(10),
        foregroundColor: LbmConst.onWelcome,
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: kBodyFont,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: LbmConst.onWelcome.withValues(alpha: 0.86),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- orient

/// "Are you…": the seven doors behind Create a Profile.
///
/// Each door is a plain `?intent=` on the sign-up route. It travels through
/// email, confirm and setup and decides only where the person lands first.
/// The welcome artwork stays screen one: its Sign in is "returning to the
/// app", its Create a Profile opens this.
class OrientScreen extends StatelessWidget {
  const OrientScreen({super.key});

  void _go(BuildContext context, OnboardingIntent intent) =>
      context.push('/signin?create=1${intent.querySuffix}');

  @override
  Widget build(BuildContext context) {
    return _OnboardingScaffold(
      title: 'Are you…',
      subtitle:
          'Pick the one that fits best. It only decides where you land first.',
      fields: [
        _DoorGroup(
          label: 'Shopping',
          doors: [
            _Door(
              "I'm new here",
              onTap: () => _go(context, OnboardingIntent.newHere),
            ),
            _Door(
              "I've bought on littlebluecart.com",
              onTap: () => _go(context, OnboardingIntent.directoryCustomer),
            ),
            _Door(
              "I've bought on Little Blue Market",
              onTap: () => _go(context, OnboardingIntent.marketplaceCustomer),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _DoorGroup(
          label: 'Selling',
          doors: [
            _Door(
              'My business is listed in the directory',
              onTap: () => _go(context, OnboardingIntent.directorySeller),
            ),
            _Door(
              'I sell on Little Blue Market',
              onTap: () => _go(context, OnboardingIntent.marketplaceSeller),
            ),
            _Door(
              'I want to list my business in the directory',
              onTap: () => _go(context, OnboardingIntent.newDirectorySeller),
            ),
            _Door(
              'I want to sell on Little Blue Market',
              onTap: () => _go(context, OnboardingIntent.newMarketplaceSeller),
            ),
          ],
        ),
      ],
      actions: [
        _QuietAction(
          'I already have a profile',
          onPressed: () => context.push('/signin'),
        ),
      ],
    );
  }
}

class _DoorGroup extends StatelessWidget {
  const _DoorGroup({required this.label, required this.doors});

  final String label;
  final List<Widget> doors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: kBodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: LbmConst.onWelcome.withValues(alpha: 0.72),
            ),
          ),
        ),
        for (final door in doors)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: door),
      ],
    );
  }
}

/// One door: a translucent row on the onboarding blue, the same surface the
/// fields use, so the list reads as choices rather than buttons.
class _Door extends StatelessWidget {
  const _Door(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: LbmRadius.fieldR,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: LbmRadius.fieldR,
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontFamily: kBodyFont,
                      fontSize: 14.5,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: LbmConst.onWelcome,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: LbmConst.onWelcome.withValues(alpha: 0.8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ email + password

/// Sign in, or create an account.
///
/// One screen, both fields. The prototype drew a six-digit code here, but
/// Firebase issues links rather than codes, and the link had to travel through
/// Dynamic Links, which shut down in August 2025. Password auth is the one
/// option that needs no mail infrastructure of our own.
class EmailScreen extends ConsumerStatefulWidget {
  const EmailScreen({
    super.key,
    this.creating = false,
    this.intent = OnboardingIntent.newHere,
  });

  /// Whether the person arrived via "Create a Profile" rather than "Sign in".
  final bool creating;

  /// The door they chose on "Are you…", carried through to setup.
  final OnboardingIntent intent;

  @override
  ConsumerState<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends ConsumerState<EmailScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _valid = false;
  bool _busy = false;
  String? _error;
  String? _notice;

  /// Firebase's own minimum. Enforcing it here means the button is disabled
  /// rather than the server refusing after a round trip.
  static const _minPassword = 6;

  @override
  void initState() {
    super.initState();
    _email.addListener(_revalidate);
    _password.addListener(_revalidate);
  }

  void _revalidate() {
    final next =
        _email.text.contains('@') &&
        _email.text.contains('.') &&
        _password.text.length >= _minPassword;
    if (next != _valid) setState(() => _valid = next);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      final session = ref.read(sessionProvider.notifier);
      if (widget.creating) {
        await session.signUp(email: _email.text, password: _password.text);
        if (!mounted) return;
        // The account exists and is signed in; the address is not yet proven.
        // That only blocks linking a shop record, so it is a notice rather
        // than a gate.
        context.push(
          '/verify?email=${Uri.encodeComponent(_email.text)}&create=1'
          '${widget.intent.querySuffix}',
        );
      } else {
        final user = await session.signInWithPassword(
          email: _email.text,
          password: _password.text,
        );
        if (!mounted) return;
        // An existing account that never confirmed its address gets the
        // confirm screen back, with a way past it, rather than the market
        // and a wall later.
        if (!user.emailVerified) {
          context.go('/verify?email=${Uri.encodeComponent(_email.text)}');
        } else {
          context.go('/market');
        }
      }
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error).body);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_email.text.contains('@')) {
      setState(() => _error = 'Enter your email first');
      return;
    }
    try {
      await ref.read(sessionProvider.notifier).sendPasswordReset(_email.text);
      if (!mounted) return;
      // Worded so it says nothing about whether the address has an account.
      setState(() {
        _error = null;
        _notice = 'If that address has an account, a reset link is on its way.';
      });
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error).body);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingScaffold(
      title: widget.creating ? 'Create a profile' : 'Welcome back',
      subtitle: widget.creating
          ? 'Pick a password with at least 6 characters.'
          : 'Sign in with your email and password.',
      fields: [
        LbmField(
          label: 'Email',
          controller: _email,
          hintText: 'you@example.com',
          onDark: true,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofocus: true,
          autofillHints: const [AutofillHints.email],
        ),
        const SizedBox(height: 12),
        LbmField(
          label: 'Password',
          controller: _password,
          hintText: 'At least 6 characters',
          onDark: true,
          obscureText: true,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _submit(),
          autofillHints: widget.creating
              ? const [AutofillHints.newPassword]
              : const [AutofillHints.password],
        ),
        if (_error != null || _notice != null) ...[
          const SizedBox(height: 12),
          Text(
            _error ?? _notice!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: LbmConst.onWelcome.withValues(
                alpha: _error != null ? 1 : 0.8,
              ),
            ),
          ),
        ],
      ],
      actions: [
        _SlateButton(
          label: _busy
              ? 'One moment…'
              : (widget.creating ? 'Create my profile' : 'Sign in'),
          onPressed: _valid && !_busy ? _submit : null,
        ),
        if (!widget.creating)
          _QuietAction('I forgot my password', onPressed: _resetPassword),
        _QuietAction(
          widget.creating ? 'I already have a profile' : 'Create one instead',
          onPressed: () => context.pushReplacement(
            '/signin?create=${widget.creating ? 0 : 1}'
            '${widget.intent.querySuffix}',
          ),
        ),
      ],
    );
  }
}

/// The onboarding button. It keeps the animation's own slate fill rather than
/// the app accent, because these screens have to sit against the artwork.
class _SlateButton extends StatelessWidget {
  const _SlateButton({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: LbmConst.slate,
          borderRadius: LbmRadius.pillR,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: LbmRadius.pillR,
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: kBodyFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: LbmConst.onWelcome,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- verify

/// Shown once, straight after signing up.
///
/// Deliberately **not** a gate. The account already works; an unverified
/// address only blocks linking an existing shop customer or vendor record,
/// which happens later and refuses on its own. Blocking here would strand
/// anyone whose mail is slow for the sake of a check they have not reached.
class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({
    super.key,
    required this.email,
    this.creating = false,
    this.intent = OnboardingIntent.newHere,
  });

  final String email;
  final bool creating;
  final OnboardingIntent intent;

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  Timer? _resendTimer;
  Timer? _pollTimer;
  int _resendIn = 30;
  String? _error;
  String? _notice;
  bool _verified = false;
  bool _checking = false;

  /// How often the screen quietly asks whether the link has been clicked, so
  /// someone who confirms on the same phone sees it flip on its own.
  static const _pollEvery = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _startResendCountdown();
    _pollTimer = Timer.periodic(_pollEvery, (_) => _check(quiet: true));
  }

  /// Re-reads the account. Nothing pushes "verified" to the phone; the
  /// token it holds says what it said when it was minted, so the app has
  /// to ask. [quiet] is the timer: it reports success and stays silent
  /// about anything else.
  Future<void> _check({bool quiet = false}) async {
    if (_checking || _verified) return;
    _checking = true;
    try {
      final user = await ref.read(sessionProvider.notifier).reloadUser();
      if (!mounted) return;
      if (user?.emailVerified == true) {
        _pollTimer?.cancel();
        _resendTimer?.cancel();
        setState(() {
          _verified = true;
          _error = null;
          _notice = null;
        });
      } else if (!quiet) {
        setState(() {
          _notice = null;
          _error =
              'Not confirmed yet. Open the link in the email '
              '(check Spam), then tap again.';
        });
      }
    } on RepositoryException catch (error) {
      if (!mounted || quiet) return;
      setState(() => _error = describeError(error).body);
    } finally {
      _checking = false;
    }
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _resend() async {
    try {
      await ref.read(sessionProvider.notifier).sendEmailVerification();
      if (!mounted) return;
      setState(() {
        _error = null;
        _notice = 'Sent again. Give it a minute.';
      });
      _startResendCountdown();
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error).body);
    }
  }

  void _continue() {
    if (widget.creating) {
      context.push('/setup${widget.intent.queryParam}');
    } else {
      context.go('/market');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Once confirmed, the screen becomes the same "You're confirmed" card
    // the email's link opens in the browser: the check, the same words.
    if (_verified) {
      return _OnboardingScaffold(
        title: "You're confirmed",
        subtitle:
            'Thank you. Your shop orders, and your shop if you sell, can '
            'now be linked to this profile.',
        fields: const [_ConfirmedBadge()],
        actions: [_SlateButton(label: 'Continue', onPressed: _continue)],
      );
    }

    return _OnboardingScaffold(
      title: 'Confirm your email',
      subtitle:
          'We sent a link to ${widget.email}. Open it when you get a moment. '
          "You'll need it before your shop orders can be linked to this profile.",
      fields: [
        if (_error != null || _notice != null) ...[
          Text(
            _error ?? _notice!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: LbmConst.onWelcome.withValues(
                alpha: _error != null ? 1 : 0.85,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Center(
          child: _resendIn > 0
              ? Text(
                  'Resend in ${_resendIn}s',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: LbmConst.onWelcome.withValues(alpha: 0.7),
                  ),
                )
              : _QuietAction('Send it again', onPressed: _resend),
        ),
      ],
      actions: [
        // Two buttons on purpose. Confirming is what unlocks linking a shop
        // account later; continuing is always allowed, because slow mail
        // must not strand anyone at the door.
        _SlateButton(
          label: _checking ? 'Checking…' : "I've confirmed it",
          onPressed: _checking ? null : () => _check(),
        ),
        _QuietAction('Continue for now', onPressed: _continue),
      ],
    );
  }
}

/// The check the confirmation page in the browser shows, drawn the same way
/// here: a pale disc on the welcome blue with the hero blue check in it.
class _ConfirmedBadge extends StatelessWidget {
  const _ConfirmedBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(
          color: LbmConst.onWelcome,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.check_rounded,
          size: 38,
          color: LbmConst.welcomeBlue,
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- setup

/// Step three, first time only: the handle, a photo, and a bio.
///
/// The handle is asked first because it doubles as the storefront address.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({
    super.key,
    this.intent = OnboardingIntent.newHere,
  });

  /// Where to land once the profile exists: the door chosen on "Are you…".
  final OnboardingIntent intent;

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _name = TextEditingController();
  final _handle = TextEditingController(text: '@');
  final _bio = TextEditingController();
  bool _busy = false;
  String? _error;
  Uint8List? _photo;
  String _photoType = 'image/jpeg';

  @override
  void initState() {
    super.initState();
    // The Create button follows the name: a profile is never made without
    // one, so nobody appears as "Someone" (Grace, 2026-09-09).
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _bio.dispose();
    super.dispose();
  }

  /// The name as it will be stored, or null when it is not one yet.
  String? get _validName {
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return name.length >= 2 ? name : null;
  }

  /// The photo is only picked here; it is uploaded with the profile, so a
  /// person who backs out never leaves an orphan in storage.
  Future<void> _pickPhoto() async {
    final source = await choosePhotoSource(context);
    if (source == null || !mounted) return;
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo = bytes;
        _photoType = pickedContentType(file);
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not get that photo: $error');
    }
  }

  Future<void> _finish() async {
    if (_busy) return;
    final name = _validName;
    if (name == null) {
      setState(() => _error = 'Add your name first. It is what people see on your posts.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The name, handle and bio are written, not discarded. The prototype
      // collected the handle and bio and threw them away.
      await ref
          .read(sessionProvider.notifier)
          .createProfile(
            ProfileEdit(
              name: name,
              handle: _handle.text.trim().isEmpty ? null : _handle.text.trim(),
              bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
            ),
          );
      final photo = _photo;
      if (photo != null) {
        // The upload writes the URL onto the profile itself.
        await ref
            .read(profileRepositoryProvider)
            .uploadAvatar(photo, contentType: _photoType);
      }
      if (!mounted) return;
      // A first profile gets the tour, once. The shell shows it as soon as
      // the landing screen is up; a phone that has seen it never sees it
      // again, whichever account signs in.
      if (!ref.read(tipsProvider).contains(Tips.firstTour)) {
        ref.read(tourPendingProvider.notifier).request();
      }
      // The door decides the first screen: a directory owner lands on the
      // Directory page already linking, a Market seller on Sell with us
      // already checking, everyone else on the feed.
      context.go(widget.intent.landingRoute);
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error).body);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingScaffold(
      title: 'Set up your profile',
      subtitle: 'Your handle is also your storefront address.',
      fields: [
        Center(
          child: Column(
            children: [
              GestureDetector(
                onTap: _busy ? null : _pickPhoto,
                child: Container(
                  width: 78,
                  height: 78,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: _photo != null
                      ? Image.memory(_photo!, fit: BoxFit.cover)
                      : const Icon(
                          Icons.add_a_photo_outlined,
                          color: LbmConst.onWelcome,
                          size: 26,
                        ),
                ),
              ),
              const SizedBox(height: 8),
              _QuietAction(
                _photo == null ? 'Add a photo' : 'Change photo',
                onPressed: _busy ? () {} : _pickPhoto,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        LbmField(
          label: 'Your name',
          controller: _name,
          hintText: 'The name people see on your posts',
          onDark: true,
          autofocus: true,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 13),
        LbmField(
          label: 'Handle',
          controller: _handle,
          hintText: '@yourshop',
          onDark: true,
        ),
        const SizedBox(height: 13),
        LbmField(
          label: 'Bio',
          controller: _bio,
          hintText: 'What you make, and where you make it.',
          maxLines: 3,
          onDark: true,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: LbmConst.onWelcome,
            ),
          ),
        ],
      ],
      actions: [
        _SlateButton(
          label: _busy ? 'One moment…' : 'Create a profile',
          onPressed: _busy || _validName == null ? null : _finish,
        ),
      ],
    );
  }
}

