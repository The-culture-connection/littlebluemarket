import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// Sell with us: the one page a buyer needs to become a seller.
///
/// Three doors, in the order people arrive at them. Already a vendor with
/// Little Blue Market (in Shipturtle): confirm the email, tap once, and the
/// app checks the roster and grants selling as the vendor string their
/// products carry. New: apply on the website; Little Blue Market approves
/// in Shipturtle; come back and tap the same button. A claim code, for the
/// cases the roster cannot decide.
class SellWithUsScreen extends ConsumerStatefulWidget {
  const SellWithUsScreen({super.key});

  @override
  ConsumerState<SellWithUsScreen> createState() => _SellWithUsScreenState();
}

class _SellWithUsScreenState extends ConsumerState<SellWithUsScreen> {
  bool _checking = false;
  SellerSyncResult? _result;
  String? _error;

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
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error).body);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _openRegistration(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(url);
    if (uri == null || url.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('The sign-up link is not set up yet.')),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open $url')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final session = ref.watch(sessionProvider).value;
    final verified = session is MemberSession && session.emailVerified;
    final isSeller = ref.watch(isSellerProvider);
    final config = ref.watch(appConfigProvider);

    return LbmScreen(
      appBar: const LbmAppBar(title: 'Sell with us'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          if (isSeller)
            LbmCard(
              color: c.sageMist,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You already sell here',
                    style: LbmText.display.copyWith(fontSize: 18, color: c.ink),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your products and sales are on your profile.',
                    style: LbmText.tiny.copyWith(color: c.ink2),
                  ),
                  const SizedBox(height: 10),
                  PillButton(
                    'Go to my profile',
                    small: true,
                    expand: false,
                    onPressed: () => context.go('/you'),
                  ),
                ],
              ),
            )
          else ...[
            // Step 0: the address has to be proven before anything is
            // granted against it.
            const UnverifiedBanner(),
            _Card(
              title: 'Already a Little Blue Market vendor?',
              body:
                  'If you sell with us through Shipturtle under this email, '
                  'tap below. The app checks our vendor list and switches '
                  'your profile to a storefront.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PillButton(
                    _checking ? 'Checking…' : 'Check my seller status',
                    onPressed: !verified || _checking ? null : _check,
                  ),
                  if (!verified) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Confirm your email first (above).',
                      style: LbmText.xtiny.copyWith(color: c.ink3),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: LbmText.tiny.copyWith(
                        fontWeight: FontWeight.w700,
                        color: c.clay,
                      ),
                    ),
                  ],
                  if (_result != null) ...[
                    const SizedBox(height: 10),
                    _ResultLine(result: _result!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Card(
              title: 'New here? Apply to sell',
              body:
                  'Tell us about your shop on our website. Once Little Blue '
                  'Market approves you, come back here and tap Check my '
                  'seller status.',
              child: LbmAsync<AppConfig>(
                config,
                skeleton: const SizedBox(height: 40),
                errorBuilder: (_, _) => PillButton(
                  'Apply on our website',
                  style: PillStyle.quiet,
                  onPressed: () => _openRegistration(''),
                ),
                data: (cfg) => PillButton(
                  'Apply on our website',
                  style: PillStyle.quiet,
                  onPressed: () => _openRegistration(cfg.registrationUrl),
                ),
              ),
            ),
            const SizedBox(height: 12),
            LbmCard(
              child: ListRow(
                title: const Text('I have a claim code'),
                subtitle: const Text('Sent by Little Blue Market'),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: c.ink3,
                ),
                onTap: () => context.push('/you/claim-shop'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.body, required this.child});

  final String title;
  final String body;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LbmCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: LbmText.display.copyWith(fontSize: 18, color: c.ink),
          ),
          const SizedBox(height: 6),
          Text(body, style: LbmText.tiny.copyWith(color: c.ink2, height: 1.5)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.result});

  final SellerSyncResult result;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (String text, Color color) = switch (result.status) {
      SellerSyncStatus.granted => (
        'You now sell as "${result.vendorName}". Your Products tab is on '
            'your profile.',
        c.sage,
      ),
      SellerSyncStatus.alreadySeller => (
        'You already sell as "${result.vendorName}".',
        c.sage,
      ),
      SellerSyncStatus.notFound => (
        'This email is not on our vendor list yet. If you applied, Little '
            'Blue Market may not have approved you in Shipturtle yet; if '
            'you sell under a different email, use that one or a claim code.',
        c.clay,
      ),
      SellerSyncStatus.undecided => (
        result.note ??
            'We found you but could not decide which shop; a '
                'claim code will.',
        c.clay,
      ),
    };
    return Text(
      text,
      style: LbmText.tiny.copyWith(
        fontWeight: FontWeight.w700,
        color: color,
        height: 1.5,
      ),
    );
  }
}
