import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/repositories.dart';
import '../state/providers.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'async.dart';
import 'primitives.dart';

/// Shown to a member whose email is not confirmed yet.
///
/// An unconfirmed member can browse, buy and post; what they cannot do is
/// link a store customer or claim a vendor, and both of those refuse with
/// "confirm your email first". Saying it here, with the two buttons that fix
/// it, is what stops "the app will not let me do anything".
class UnverifiedBanner extends ConsumerStatefulWidget {
  const UnverifiedBanner({super.key});

  @override
  ConsumerState<UnverifiedBanner> createState() => _UnverifiedBannerState();
}

class _UnverifiedBannerState extends ConsumerState<UnverifiedBanner> {
  String? _notice;
  bool _busy = false;

  Future<void> _resend() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).sendEmailVerification();
      if (mounted) setState(() => _notice = 'Sent again. Check Spam too.');
    } on RepositoryException catch (error) {
      if (mounted) setState(() => _notice = describeError(error).body);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final user = await ref.read(sessionProvider.notifier).reloadUser();
      if (!mounted) return;
      setState(() {
        _notice = user?.emailVerified == true
            ? 'Confirmed. Thank you.'
            : 'Not confirmed yet. Open the link in the email, then tap again.';
      });
    } on RepositoryException catch (error) {
      if (mounted) setState(() => _notice = describeError(error).body);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final session = ref.watch(sessionProvider).value;
    if (session is! MemberSession || session.emailVerified) {
      return const SizedBox.shrink();
    }
    final email =
        ref.read(authServiceProvider).currentUser?.email ?? 'your email';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: LbmCard(
        color: c.skyWash,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Confirm your email',
              style: LbmText.display.copyWith(fontSize: 16, color: c.ink),
            ),
            const SizedBox(height: 4),
            Text(
              _notice ??
                  'We sent a link to $email. Open it to link your store '
                      'orders and, if you sell, your shop.',
              style: LbmText.tiny.copyWith(color: c.ink2, height: 1.45),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                PillButton(
                  "I've confirmed it",
                  small: true,
                  expand: false,
                  onPressed: _busy ? null : _check,
                ),
                PillButton(
                  'Resend',
                  small: true,
                  expand: false,
                  style: PillStyle.quiet,
                  onPressed: _busy ? null : _resend,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
