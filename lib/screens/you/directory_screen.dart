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
import '../../widgets/directory_listing_card.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import '../../widgets/unverified_banner.dart';

/// Little Blue Cart directory: the one page that joins this account to
/// littlebluecart.com.
///
/// Linking is by the confirmed email, decided on the backend: a WordPress
/// member, a WooCommerce customer, or both. What comes back is shown here,
/// website orders first; listings join in CP-D3. Arriving from an onboarding
/// door (`?auto=1`) runs the link by itself once the email is confirmed.
class DirectoryScreen extends ConsumerStatefulWidget {
  const DirectoryScreen({super.key, this.auto = false, this.add = false});

  /// True when an onboarding door sent the person here: link without a tap.
  final bool auto;

  /// True for the "I want to list my business" door: open the website's
  /// Add Your Business form once, then stay here to explain what happens next.
  final bool add;

  @override
  ConsumerState<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends ConsumerState<DirectoryScreen> {
  bool _busy = false;
  bool _autoRan = false;
  bool _addOpened = false;
  DirectoryLinkResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.auto) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAuto());
    }
  }

  /// The door's promise: once the email is confirmed, the link runs on its
  /// own. Once, so a session stream that re-emits cannot loop it.
  void _maybeAuto() {
    if (!mounted || !widget.auto || _autoRan) return;
    final session = ref.read(sessionProvider).value;
    if (session is! MemberSession || !session.emailVerified) return;
    final link = ref.read(directoryLinkProvider).value;
    _autoRan = true;
    if (link?.linked ?? false) return;
    _link();
  }

  Future<void> _link() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await ref.read(directoryRepositoryProvider).link();
      if (!mounted) return;
      setState(() => _result = result);
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error).body);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Use my directory listing": the profile takes the listing's name,
  /// handle, bio, hashtags and City, State. On demand only after the first
  /// link, so later edits are never replaced silently.
  Future<void> _applyProfile() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final applied = await ref
          .read(directoryRepositoryProvider)
          .applyListingProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Your profile now reads as ${applied.name} (${applied.handle}).',
          ),
        ),
      );
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error).body);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(url);
    if (uri == null || url.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That link is not set up yet.')),
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
    final link = ref.watch(directoryLinkProvider);
    final orders = ref.watch(directoryOrdersProvider);
    final listings = ref.watch(myDirectoryListingsProvider);
    final config = ref.watch(appConfigProvider);
    final linked = link.value?.linked ?? false;

    // The confirm-email banner's "I've confirmed it" flips the session; the
    // door's automatic link waits for exactly that.
    ref.listen(sessionProvider, (_, _) => _maybeAuto());

    // The "list my business" door: the form opens once the link is known.
    final addUrl = config.value?.directoryAddListingUrl;
    if (widget.add && !_addOpened && addUrl != null) {
      _addOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _open(addUrl);
      });
    }

    return LbmScreen(
      appBar: const LbmAppBar(title: 'Little Blue Cart directory'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          const UnverifiedBanner(),
          LbmAsync<DirectoryLink?>(
            link,
            skeleton: const SizedBox(height: 120),
            data: (current) => _StatusCard(
              link: current,
              verified: verified,
              busy: _busy,
              error: _error,
              result: _result,
              onLink: _link,
              onApplyProfile: (current?.listingCount ?? 0) > 0
                  ? _applyProfile
                  : null,
            ),
          ),
          if (linked) ...[
            const SizedBox(height: 16),
            const SectionHead('My listings'),
            const SizedBox(height: 8),
            LbmAsync<List<DirectoryListing>>(
              listings,
              skeleton: const SizedBox(height: 80),
              data: (list) => list.isEmpty
                  ? LbmCard(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No listing under this account yet. Add your business '
                        'below; it shows here once Little Blue Cart approves '
                        'it (tap Refresh).',
                        style: LbmText.tiny.copyWith(
                          color: c.ink2,
                          height: 1.5,
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final listing in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: DirectoryListingCard(
                              listing: listing,
                              showStatus: true,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
          if (linked) ...[
            const SizedBox(height: 16),
            const SectionHead('My products (sold on my website)'),
            const SizedBox(height: 8),
            LbmAsync<List<Product>>(
              ref.watch(myDirectoryProductsProvider),
              skeleton: const SizedBox(height: 60),
              data: (list) => LbmCard(
                child: RowStack(
                  children: [
                    for (final product in list)
                      ListRow(
                        leading: product.hasPhoto
                            ? ClipRRect(
                                borderRadius: LbmRadius.imageR,
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Image.network(
                                    product.imageUrls.first,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        ColoredBox(color: c.skyWash),
                                  ),
                                ),
                              )
                            : Icon(Icons.storefront_outlined, color: c.ink3),
                        title: Text(product.title),
                        subtitle: Text(product.price),
                        trailing: Icon(
                          Icons.edit_outlined,
                          size: 20,
                          color: c.ink3,
                        ),
                        onTap: () => context.push(
                          '/you/directory-product/'
                          '${product.id.substring(Product.externalPrefix.length)}',
                        ),
                      ),
                    ListRow(
                      leading: Icon(Icons.add_rounded, color: c.accentText),
                      title: const Text('Add a product'),
                      subtitle: const Text(
                        'Photos, a name, a price; Buy opens your website',
                      ),
                      onTap: () => context.push('/you/directory-product'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _AddListingCard(
            config: config,
            onOpen: _open,
          ),
          const SizedBox(height: 16),
          const SectionHead('Orders from littlebluecart.com'),
          const SizedBox(height: 8),
          LbmAsync<List<DirectoryOrder>>(
            orders,
            skeleton: const SizedBox(height: 80),
            data: (list) => list.isEmpty
                ? LbmCard(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      linked
                          ? 'No website orders on this email yet.'
                          : 'Link your account to see orders you placed on '
                                'littlebluecart.com.',
                      style: LbmText.tiny.copyWith(color: c.ink2, height: 1.5),
                    ),
                  )
                : LbmCard(
                    child: RowStack(
                      children: [
                        for (final order in list)
                          ListRow(
                            title: Text(
                              'Order #${order.number} · ${order.totalLabel}',
                            ),
                            subtitle: Text(
                              '${order.dateLabel} · ${order.statusLabel}'
                              '${order.items.isEmpty ? '' : '\n${order.summary}'}',
                            ),
                            trailing: Icon(
                              Icons.open_in_new_rounded,
                              size: 20,
                              color: c.ink3,
                            ),
                            onTap: () => _open(order.viewUrl),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Adding a listing stays on the website: the plans, the payment and Little
/// Blue Cart's review live there. The app opens the form and says what
/// happens next.
class _AddListingCard extends StatelessWidget {
  const _AddListingCard({required this.config, required this.onOpen});

  final AsyncValue<AppConfig> config;
  final Future<void> Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LbmCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'List your business in the directory',
            style: LbmText.display.copyWith(fontSize: 18, color: c.ink),
          ),
          const SizedBox(height: 6),
          Text(
            'The form is on littlebluecart.com: pick a plan and tell us about '
            'your business. Little Blue Cart reviews it; once it is approved, '
            'come back here and tap Refresh.',
            style: LbmText.tiny.copyWith(color: c.ink2, height: 1.5),
          ),
          const SizedBox(height: 12),
          LbmAsync<AppConfig>(
            config,
            skeleton: const SizedBox(height: 40),
            errorBuilder: (_, _) => PillButton(
              'Add a listing',
              style: PillStyle.quiet,
              onPressed: () => onOpen(''),
            ),
            data: (cfg) => PillButton(
              'Add a listing',
              style: PillStyle.quiet,
              onPressed: () => onOpen(cfg.directoryAddListingUrl),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.link,
    required this.verified,
    required this.busy,
    required this.error,
    required this.result,
    required this.onLink,
    this.onApplyProfile,
  });

  final DirectoryLink? link;
  final bool verified;
  final bool busy;
  final String? error;
  final DirectoryLinkResult? result;
  final VoidCallback onLink;

  /// Present once a listing is linked: fills the profile from it.
  final VoidCallback? onApplyProfile;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final current = link;
    final linked = current?.linked ?? false;

    return LbmCard(
      color: linked ? c.sageMist : null,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            linked
                ? current!.label
                : 'Bought or listed on littlebluecart.com?',
            style: LbmText.display.copyWith(fontSize: 18, color: c.ink),
          ),
          const SizedBox(height: 6),
          Text(
            linked
                ? '${_plural(current!.orderCount, 'website order')} · '
                      '${_plural(current.listingCount, 'listing')}'
                : 'If your littlebluecart.com account uses this email, tap '
                      'below. The app finds your website orders and your '
                      'business listing.',
            style: LbmText.tiny.copyWith(color: c.ink2, height: 1.5),
          ),
          const SizedBox(height: 12),
          PillButton(
            busy
                ? 'Checking…'
                : linked
                ? 'Refresh'
                : 'Link my directory account',
            style: linked ? PillStyle.quiet : PillStyle.solid,
            onPressed: !verified || busy ? null : onLink,
          ),
          if (onApplyProfile != null) ...[
            const SizedBox(height: 8),
            PillButton(
              'Use my directory listing',
              style: PillStyle.quiet,
              onPressed: busy ? null : onApplyProfile,
            ),
            const SizedBox(height: 6),
            Text(
              'Sets your name, handle, bio, hashtags and city from the '
              'listing. It ran once when you linked; tap to run it again.',
              style: LbmText.xtiny.copyWith(color: c.ink3, height: 1.4),
            ),
          ],
          if (!verified) ...[
            const SizedBox(height: 8),
            Text(
              'Confirm your email first (above).',
              style: LbmText.xtiny.copyWith(color: c.ink3),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              error!,
              style: LbmText.tiny.copyWith(
                fontWeight: FontWeight.w700,
                color: c.clay,
              ),
            ),
          ],
          if (result != null) ...[
            const SizedBox(height: 10),
            _ResultLine(result: result!),
          ],
        ],
      ),
    );
  }

  static String _plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.result});

  final DirectoryLinkResult result;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (String text, Color color) = switch (result.status) {
      DirectoryLinkStatus.linked => (
        'Linked. ${result.orders} ${result.orders == 1 ? 'order' : 'orders'} '
            'and ${result.listings} ${result.listings == 1 ? 'listing' : 'listings'} '
            'found.${result.note == null ? '' : ' ${result.note}'}',
        c.sage,
      ),
      DirectoryLinkStatus.alreadyLinked => (
        result.note ?? 'Already linked.',
        c.sage,
      ),
      DirectoryLinkStatus.notFound => (
        'No account at littlebluecart.com uses this email. If your listing '
            'or orders are under another address, sign in with that one.'
            '${result.note == null ? '' : ' ${result.note}'}',
        c.clay,
      ),
      DirectoryLinkStatus.off => (
        result.note ?? 'The directory is not connected to the app yet.',
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
