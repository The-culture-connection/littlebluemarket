import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/fixtures/fixture_data.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
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
                            Image.asset(Fx.cart, width: 74),
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

// -------------------------------------------------------------------- email

/// Step one: the email address.
///
/// The store uses passwordless customer accounts, so there is no password
/// field anywhere in this flow. Signing in and creating a profile are the same
/// first step — the difference only shows up after the code is confirmed.
class EmailScreen extends StatefulWidget {
  const EmailScreen({super.key, this.creating = false});

  /// Whether the person arrived via "Create a Profile" rather than "Sign in".
  final bool creating;

  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> {
  final _email = TextEditingController();
  bool _valid = false;

  @override
  void initState() {
    super.initState();
    _email.addListener(() {
      final next = _email.text.contains('@') && _email.text.contains('.');
      if (next != _valid) setState(() => _valid = next);
    });
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_valid) return;
    context.push(
      '/verify?email=${Uri.encodeComponent(_email.text)}'
      '&create=${widget.creating ? 1 : 0}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingScaffold(
      title: widget.creating ? 'Create a profile' : 'Welcome back',
      subtitle: widget.creating
          ? "We'll email you a six-digit code. No password to remember."
          : 'Enter your email and we’ll send you a six-digit code.',
      fields: [
        LbmField(
          label: 'Email',
          controller: _email,
          hintText: 'you@example.com',
          onDark: true,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.go,
          autofocus: true,
          onSubmitted: (_) => _submit(),
        ),
      ],
      actions: [
        _SlateButton(
          label: 'Send my code',
          onPressed: _valid ? _submit : null,
        ),
        _QuietAction(
          widget.creating
              ? 'I already have a profile'
              : 'Create one instead',
          onPressed: () => context.pushReplacement(
            '/signin?create=${widget.creating ? 0 : 1}',
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

// --------------------------------------------------------------------- code

/// Step two: the six-digit code.
class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key, required this.email, this.creating = false});

  final String email;
  final bool creating;

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  Timer? _resendTimer;
  int _resendIn = 30;

  @override
  void initState() {
    super.initState();
    _startResendCountdown();
    _code.addListener(() {
      setState(() {});
      if (_code.text.length == 6) _confirm();
    });
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
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_code.text.length < 6) return;
    // A returning buyer goes straight in; a first-time account still needs a
    // handle, a photo and a bio before it has a storefront.
    if (widget.creating) {
      context.push('/setup');
    } else {
      ref.read(sessionProvider.notifier).signIn();
      context.go('/market');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingScaffold(
      title: 'Check your email',
      subtitle: 'We sent a six-digit code to ${widget.email}.',
      fields: [
        _CodeBoxes(
          controller: _code,
          focusNode: _focus,
          onCompleted: _confirm,
        ),
        const SizedBox(height: 18),
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
              : _QuietAction('Send a new code', onPressed: _startResendCountdown),
        ),
      ],
      actions: [
        _SlateButton(
          label: 'Confirm',
          onPressed: _code.text.length == 6 ? _confirm : null,
        ),
        _QuietAction(
          'Use a different email',
          onPressed: () => context.pop(),
        ),
      ],
    );
  }
}

/// Six boxes that share one hidden field, so paste and SMS autofill both work.
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({
    required this.controller,
    required this.focusNode,
    required this.onCompleted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onCompleted;

  @override
  Widget build(BuildContext context) {
    final digits = controller.text.padRight(6, ' ').split('');
    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 6; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Container(
                  width: 44,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: LbmRadius.fieldR,
                    border: Border.all(
                      color: controller.text.length == i
                          ? LbmConst.onWelcome
                          : Colors.white.withValues(alpha: 0.34),
                      width: 1.6,
                    ),
                  ),
                  child: Text(
                    digits[i].trim(),
                    style: const TextStyle(
                      fontFamily: kDisplayFont,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: LbmConst.onWelcome,
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                ),
              ),
          ],
        ),
        // The real field, invisible but focusable and autofillable.
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => onCompleted(),
              decoration: const InputDecoration(counterText: ''),
            ),
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- setup

/// Step three, first time only: the handle, a photo, and a bio.
///
/// The handle is asked first because it doubles as the storefront address.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _handle = TextEditingController(text: '@');
  final _bio = TextEditingController();
  bool _sells = true;

  @override
  void dispose() {
    _handle.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _finish() {
    ref.read(sessionProvider.notifier).signIn();
    context.go('/market');
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
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.add_a_photo_outlined,
                  color: LbmConst.onWelcome,
                  size: 26,
                ),
              ),
              const SizedBox(height: 8),
              _QuietAction('Add a photo', onPressed: () {}),
            ],
          ),
        ),
        const SizedBox(height: 8),
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
        const SizedBox(height: 13),
        _SellCheckbox(
          value: _sells,
          onChanged: (v) => setState(() => _sells = v),
        ),
      ],
      actions: [_SlateButton(label: 'Create a profile', onPressed: _finish)],
    );
  }
}

class _SellCheckbox extends StatelessWidget {
  const _SellCheckbox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: LbmRadius.fieldR,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: value
                    ? LbmConst.onWelcome
                    : Colors.white.withValues(alpha: 0.16),
                borderRadius: const BorderRadius.all(Radius.circular(7)),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.55),
                  width: 1.5,
                ),
              ),
              child: value
                  ? const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: LbmConst.welcomeBlue,
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "I'm here to sell as well as buy",
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: LbmConst.onWelcome.withValues(alpha: 0.88),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
