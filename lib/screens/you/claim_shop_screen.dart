import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/repositories.dart';
import '../../models/models.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import '../../widgets/unverified_banner.dart';

/// Claiming a shop.
///
/// **The email is the way in; the code is the exception.** A Shipturtle
/// vendor already has an email on their vendor account, and confirming that
/// address in the app is proof enough: `syncSellerStatus` asks the backend
/// to match it against the Shipturtle roster and grant the vendor string
/// their products carry. Nobody has to issue anything, and a vendor approved
/// at midnight can be selling at one minute past.
///
/// This screen used to offer only a claim code, with a TODO about how codes
/// would be handed out, which had it backwards: it sent every vendor to ask
/// Grace for something they did not need (Grace, 2026-09-24). The code
/// stays, underneath, because the roster match deliberately refuses three
/// cases it cannot decide safely — one email on two vendor companies, a
/// vendor with no products yet, and a vendor string another account already
/// holds — and somebody has to be able to sort those out by hand.
///
/// Nothing here decides anything either way. Both paths go to a callable
/// that checks the verified email, reserves the vendor name and records the
/// grant in one transaction. This screen's whole job is to explain the
/// result.
class ClaimShopScreen extends ConsumerStatefulWidget {
  const ClaimShopScreen({super.key});

  @override
  ConsumerState<ClaimShopScreen> createState() => _ClaimShopScreenState();
}

class _ClaimShopScreenState extends ConsumerState<ClaimShopScreen> {
  final _code = TextEditingController();
  bool _working = false;
  bool _checking = false;
  String? _error;
  SellerSyncResult? _result;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// The autonomous path: the address on the Shipturtle vendor account,
  /// confirmed in the app, is the claim.
  Future<void> _check() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await ref
          .read(profileRepositoryProvider)
          .syncSellerStatus();
      // A grant lives on the token; refresh it so the Products tab appears
      // without a sign-out.
      await ref.read(sessionProvider.notifier).reloadUser();
      if (!mounted) return;
      setState(() => _result = result);
      if (result.status == SellerSyncStatus.granted ||
          result.status == SellerSyncStatus.alreadySeller) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.vendorName == null
                  ? 'Your shop is connected.'
                  : 'You are now selling as ${result.vendorName}.',
            ),
          ),
        );
        context.go('/you');
      }
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error).body);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _claim() async {
    if (_code.text.trim().isEmpty || _working) return;
    setState(() {
      _working = true;
      _error = null;
    });

    try {
      final grant = await ref
          .read(profileRepositoryProvider)
          .requestSellerStatus(_code.text);
      if (!mounted) return;

      // Name the shop. A code issued against the wrong vendor record is the
      // one mistake the person can catch and we cannot.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You are now selling as ${grant.vendorName}.')),
      );
      // Land on the profile, where the Products tab has just appeared.
      context.go('/you');
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error).body);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final session = ref.watch(sessionProvider).value;
    final verified = session is MemberSession && session.emailVerified;

    return LbmScreen(
      appBar: const LbmAppBar(title: 'Start selling'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Step 0: the address has to be proven before anything is granted
          // against it. The whole scheme rests on it.
          const UnverifiedBanner(),
          LbmCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connect my shop',
                    style: LbmText.display.copyWith(fontSize: 19, color: c.ink),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'If you sell with Little Blue Market through Shipturtle, '
                    'use the same email here as on your vendor account. '
                    'Confirm it and tap below: we check the vendor list and '
                    'connect your shop, with its products and sales, to this '
                    'profile. No code needed.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: c.ink2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  PillButton(
                    _checking ? 'Checking…' : 'Connect my shop',
                    onPressed: !verified || _checking ? null : _check,
                  ),
                  if (!verified) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Confirm your email first (above).',
                      style: LbmText.xtiny.copyWith(color: c.ink3),
                    ),
                  ],
                  if (_result != null) ...[
                    const SizedBox(height: 12),
                    _SyncNote(result: _result!),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          LbmCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Given a claim code?',
                    style: LbmText.tiny.copyWith(
                      fontWeight: FontWeight.w800,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Only needed when the check above cannot decide on its '
                    'own, and Little Blue Market has sent you one.',
                    style: LbmText.xtiny.copyWith(color: c.ink2, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  LbmField(
                    label: 'Claim code',
                    controller: _code,
                    hintText: 'The code we sent you',
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _claim(),
                  ),
                  const SizedBox(height: 12),
                  PillButton(
                    _working ? 'Checking…' : 'Use my code',
                    style: PillStyle.quiet,
                    onPressed: _code.text.trim().isEmpty || _working
                        ? null
                        : _claim,
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _error!,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                  color: c.clay,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Not a vendor yet? Apply on our website first. Once Little Blue '
              'Market approves you, come back and tap Connect my shop.',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: c.ink3),
            ),
          ),
        ],
      ),
    );
  }
}

/// Why the check did not connect a shop, in words the person can act on.
///
/// Only the unhappy cases reach here: a grant leaves the screen.
class _SyncNote extends StatelessWidget {
  const _SyncNote({required this.result});

  final SellerSyncResult result;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final text = switch (result.status) {
      SellerSyncStatus.granted ||
      SellerSyncStatus.alreadySeller => 'Your shop is connected.',
      SellerSyncStatus.notFound =>
        'We could not find a vendor account with this email. Check it is the '
            'same address as on your Shipturtle vendor account, or use a '
            'claim code below.',
      SellerSyncStatus.undecided =>
        result.note == null
            ? 'We found you, but could not connect the shop automatically. '
                  'Use a claim code below, or get in touch.'
            : 'We found you, but could not connect the shop automatically: '
                  '${result.note}. Use a claim code below, or get in touch.',
    };
    return Text(
      text,
      style: LbmText.xtiny.copyWith(color: c.ink2, height: 1.55),
    );
  }
}
