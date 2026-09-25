import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_assets.dart';
import '../../legal_links.dart';
import '../../data/repositories/repositories.dart';
import '../../models/onboarding.dart';
import '../../widgets/async.dart';
import '../../state/providers.dart';
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
    this.justDeleted = false,
    this.intent = OnboardingIntent.newHere,
  });

  /// Whether the person arrived via "Create a Profile" rather than "Sign in".
  final bool creating;

  /// They have just deleted their account and been sent here. Says so, once,
  /// because the screen they confirmed it on no longer exists.
  final bool justDeleted;

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
  /// Ticked to agree to the terms. Only asked when creating an account, and
  /// the Create button stays dead until it is.
  bool _agreed = false;
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
    // Belt and braces: the button is disabled without the tick, and this
    // refuses anyway, so no future edit to the button can slip past it.
    if (widget.creating && !_agreed) return;
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
        if (widget.justDeleted) const _DeletedNote(),
        if (widget.creating)
          _AgreeToTerms(
            agreed: _agreed,
            onChanged: (next) => setState(() => _agreed = next),
          ),
        _SlateButton(
          label: _busy
              ? 'One moment…'
              : (widget.creating ? 'Create my profile' : 'Sign in'),
          onPressed: _valid && !_busy && (!widget.creating || _agreed)
              ? _submit
              : null,
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

/// Step three, first time only: the name, a photo, a handle and a bio.
///
/// Nothing here says "storefront" any more. Customers read it as a promise
/// that they were about to be given a shop, and asked why they were being
/// made to open one to buy a candle (Grace's testers, 2026-09-23). A handle
/// is a name people can reply to; a shop is something a seller claims later,
/// on Sell with us.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key, this.intent = OnboardingIntent.newHere});

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

  /// What this person says they care about, picked at setup.
  ///
  /// Seeds the feed and the tag pages from the first minute: an account that
  /// follows nothing has nothing to come back to.
  final _tags = <String>{};

  /// Shown when the backend has no popular tags to offer yet, so the step is
  /// never an empty box.
  static const _fallbackTags = [
    '#WomanOwned',
    '#BIPOCOwned',
    '#LGBTQOwned',
    '#VeteranOwned',
    '#DisabledOwned',
    '#PlasticFree',
    '#MadeInDetroit',
    '#Handmade',
  ];

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

  /// Leaves without a profile: as a guest on the Market, or back to the
  /// welcome screen. See [SessionNotifier.leaveOnboarding].
  Future<void> _leave({required bool asGuest}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).leaveOnboarding(asGuest: asGuest);
      if (!mounted) return;
      context.go(asGuest ? '/market' : '/');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    if (_busy) return;
    final name = _validName;
    if (name == null) {
      setState(
        () => _error =
            'Add your name first. It is what people see on your posts.',
      );
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
              tags: _tags.toList(),
            ),
          );
      // Following them as well as wearing them, so the feed and the tag
      // pages have something in them from the first minute. Best effort: a
      // failure here must not hold up an account that already exists.
      for (final tag in _tags) {
        try {
          await ref
              .read(socialRepositoryProvider)
              .setFollowingTag(tag, on: true);
        } on Object {
          // Left unfollowed; the tag page still offers the button.
        }
      }
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
      subtitle:
          'Everyone here has one, buyers included. It is how you comment, '
          'review what you buy, and message a maker — and how they know who '
          'they are talking to.',
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
          hintText: '@yourname',
          helper: 'What people see when you comment. You can change it later.',
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
        const SizedBox(height: 16),
        _TagPicker(
          selected: _tags,
          options: ref.watch(popularTagsProvider).value
                  ?.map((t) => t.tag)
                  .toList() ??
              _fallbackTags,
          onToggle: (tag) => setState(() {
            if (!_tags.remove(tag)) _tags.add(tag);
          }),
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
        const _LegalNote(),
        // The door out. Without these two this screen was a room with no
        // exit: Back went to the confirm-your-email step, which sent them
        // straight here again (Grace's testers, 2026-09-23).
        const SizedBox(height: 4),
        _QuietAction(
          'Look around as a guest',
          onPressed: _busy ? () {} : () => _leave(asGuest: true),
        ),
        _QuietAction(
          'Back to the start',
          onPressed: _busy ? () {} : () => _leave(asGuest: false),
        ),
        const SizedBox(height: 4),
        Text(
          'Your account is saved either way. Sign in again whenever you want '
          'to finish this.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.5,
            color: LbmConst.onWelcome.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

/// "By creating a profile you agree to…", with the two policies tappable.
/// Sits under the create buttons on both sign-up steps.
class _LegalNote extends StatefulWidget {
  const _LegalNote();

  @override
  State<_LegalNote> createState() => _LegalNoteState();
}

class _LegalNoteState extends State<_LegalNote> {
  late final _terms = TapGestureRecognizer()
    ..onTap = () => _open(LegalLinks.storeTerms);
  late final _privacy = TapGestureRecognizer()
    ..onTap = () => _open(LegalLinks.privacyPolicy);

  Future<void> _open(String url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!await openLegalLink(url)) {
      messenger?.showSnackBar(SnackBar(content: Text('Could not open $url')));
    }
  }

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: kBodyFont,
      fontSize: 11.5,
      height: 1.4,
      fontWeight: FontWeight.w600,
      color: LbmConst.onWelcome.withValues(alpha: 0.75),
    );
    final link = base.copyWith(
      color: LbmConst.onWelcome,
      decoration: TextDecoration.underline,
      decorationColor: LbmConst.onWelcome,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Text.rich(
        TextSpan(
          style: base,
          children: [
            const TextSpan(text: 'By creating a profile you agree to our '),
            TextSpan(text: 'Terms of Service', style: link, recognizer: _terms),
            const TextSpan(text: ' and '),
            TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
            const TextSpan(text: '.'),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// "I agree to the Terms of Service and Privacy Policy", as a tick that has
/// to be given before an account can be created.
///
/// Grace created an account and never saw the terms (2026-09-14). They were
/// there, as `_LegalNote`: 11.5px, three quarters opacity, the last thing on
/// the screen, below the button and below "I already have a profile". Being
/// present is not the same as being presented, and both app stores ask that
/// somebody actually agrees. So it is legible, it is above the button, and
/// the button does not work until it is ticked.
///
/// Both policies remain tappable, and both are also rows in Edit profile for
/// anybody who wants to read them later.
class _AgreeToTerms extends StatefulWidget {
  const _AgreeToTerms({required this.agreed, required this.onChanged});

  final bool agreed;
  final ValueChanged<bool> onChanged;

  @override
  State<_AgreeToTerms> createState() => _AgreeToTermsState();
}

class _AgreeToTermsState extends State<_AgreeToTerms> {
  // The app's own terms, opened in the app. The store's policy page is
  // about buying and shipping and says nothing about what may be posted.
  late final _terms = TapGestureRecognizer()
    ..onTap = () => _openTerms();
  late final _privacy = TapGestureRecognizer()
    ..onTap = () => openLegalLink(LegalLinks.privacyPolicy);

  void _openTerms() {
    if (!mounted) return;
    context.push(LegalLinks.termsRoute);
  }

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: kBodyFont,
      fontSize: 13,
      height: 1.45,
      fontWeight: FontWeight.w600,
      color: LbmConst.onWelcome,
    );
    final link = base.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: LbmConst.onWelcome,
      fontWeight: FontWeight.w800,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
      // The whole row is the control, so a screen reader announces the
      // agreement rather than an unlabelled tick.
      child: Semantics(
        checked: widget.agreed,
        label: 'I agree to the Terms of Use and the Privacy Policy',
        child: InkWell(
          onTap: () => widget.onChanged(!widget.agreed),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drawn rather than a Checkbox: this sits on the artwork,
                // where Material's own colours do not belong.
                Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: widget.agreed
                        ? LbmConst.onWelcome
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: LbmConst.onWelcome, width: 2),
                  ),
                  child: widget.agreed
                      ? Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: LbmConst.welcomeBlue,
                        )
                      : null,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: ExcludeSemantics(
                    child: Text.rich(
                      TextSpan(
                        style: base,
                        children: [
                          const TextSpan(text: 'I agree to the '),
                          TextSpan(
                            text: 'Terms of Use',
                            style: link,
                            recognizer: _terms,
                          ),
                          const TextSpan(text: ' and the '),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: link,
                            recognizer: _privacy,
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Your account has been deleted", on the screen somebody lands on after
/// deleting it.
///
/// The confirmation used to be on the deletion page itself, which is the one
/// page that cannot survive the sign-out that follows. Saying it here means
/// it is read.
class _DeletedNote extends StatelessWidget {
  const _DeletedNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
      child: Text(
        'Your account has been deleted, and you have been signed out. '
        'Orders stay as financial records; everything else about you is '
        'gone. You are welcome back any time.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: kBodyFont,
          fontSize: 13,
          height: 1.5,
          fontWeight: FontWeight.w700,
          color: LbmConst.onWelcome,
        ),
      ),
    );
  }
}

/// "Pick a few things you care about", at the end of profile setup.
///
/// The chips are hashtags, and picking one both puts it on the profile and
/// follows it. It is the difference between an account that opens onto a
/// stranger's market and one that opens onto something recognisable.
///
/// Optional on purpose: a required step here is a wall in front of an
/// account that already exists.
class _TagPicker extends StatelessWidget {
  const _TagPicker({
    required this.selected,
    required this.options,
    required this.onToggle,
  });

  final Set<String> selected;
  final List<String> options;
  final ValueChanged<String> onToggle;

  /// How many the copy suggests. Nothing enforces it.
  static const _suggested = 3;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Pick $_suggested things you care about',
          style: const TextStyle(
            fontFamily: kBodyFont,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.36,
            color: LbmConst.onWelcome,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Your market starts here. You can change them later.',
          style: TextStyle(
            fontFamily: kBodyFont,
            fontSize: 12,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: LbmConst.onWelcome.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final tag in options)
              _TagChip(
                label: tag,
                on: selected.contains(tag),
                onTap: () => onToggle(tag),
              ),
          ],
        ),
      ],
    );
  }
}

/// A chip on the welcome blue, which is not a themed surface: the palette's
/// chip colours are drawn for paper and disappear here.
class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on
                ? LbmConst.onWelcome
                : LbmConst.onWelcome.withValues(alpha: 0.14),
            borderRadius: LbmRadius.pillR,
            border: Border.all(
              color: LbmConst.onWelcome.withValues(alpha: on ? 1 : 0.45),
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: kBodyFont,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: on ? LbmConst.welcomeBlue : LbmConst.onWelcome,
            ),
          ),
        ),
      ),
    );
  }
}
