import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/dev_error_sink.dart';
import '../../data/repositories/repositories.dart';
import '../../models/models.dart';
import '../../state/providers.dart';
import '../../models/feed_item.dart';
import '../../state/feed_items.dart';
import '../../state/notification_delivery_suite.dart';
import '../../state/notifications_ui.dart';
import '../../state/promos.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/lbm_toast.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';

/// The hidden dev screen: who the phone thinks it is, and whether the
/// deployed backend can reach Shopify, the webhooks and Shipturtle.
///
/// Reached from the bottom of Edit Profile in debug builds. Everything on it
/// is copyable, because its whole purpose is to be pasted to Claude.
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  late Future<AuthFacts> _facts;
  Future<HealthReport>? _health;

  @override
  void initState() {
    super.initState();
    _facts = ref.read(diagnosticsRepositoryProvider).authFacts();
  }

  void _runHealth() {
    setState(() {
      _health = ref.read(diagnosticsRepositoryProvider).healthCheck();
    });
  }

  void _refreshFacts() {
    setState(() {
      _facts = ref.read(diagnosticsRepositoryProvider).authFacts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LbmScreen(
      appBar: LbmAppBar(title: kLbmDev ? 'Diagnostics (dev)' : 'Staff tools'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 26),
        children: [
          const SectionHead('This phone'),
          FutureBuilder<AuthFacts>(
            future: _facts,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return LbmErrorCard(
                  error: snapshot.error!,
                  onRetry: _refreshFacts,
                );
              }
              final facts = snapshot.data;
              if (facts == null) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              return _FactsCard(facts: facts, onRefresh: _refreshFacts);
            },
          ),
          const SizedBox(height: 18),
          const SectionHead('Store link'),
          const _LinkCard(),
          const SizedBox(height: 18),
          const SectionHead('Admin · the catalog'),
          _AdminCard(onClaimed: _refreshFacts),
          const SizedBox(height: 18),
          const SectionHead('Adverts and announcements'),
          const _PromosCard(),
          const SizedBox(height: 18),
          const SectionHead('Notification preview'),
          const _PreviewCard(),
          const SizedBox(height: 18),
          const SectionHead('Notification delivery'),
          const _DeliveryCard(),
          const SizedBox(height: 18),
          const SectionHead('The backend'),
          LbmCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Asks the deployed functions whether they can reach the '
                  'store, the webhooks and Shipturtle. Takes a few seconds.',
                  style: LbmText.tiny.copyWith(color: c.ink2),
                ),
                const SizedBox(height: 12),
                PillButton(
                  _health == null ? 'Run backend health check' : 'Run again',
                  onPressed: _runHealth,
                ),
              ],
            ),
          ),
          if (_health != null) ...[
            const SizedBox(height: 10),
            FutureBuilder<HealthReport>(
              future: _health,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return LbmErrorCard(
                    error: snapshot.error!,
                    onRetry: _runHealth,
                  );
                }
                final report = snapshot.data;
                if (report == null) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                return _ReportCard(report: report);
              },
            ),
          ],
          if (kLbmDev) ...[
            const SizedBox(height: 18),
            const SectionHead('Artwork'),
            LbmCard(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The launch animation now plays over the app at start-up, '
                    'so the welcome screen no longer replays it. This button '
                    'is the only way left to watch the welcome GIF itself, '
                    'from its first frame.',
                    style: LbmText.tiny.copyWith(color: c.ink2),
                  ),
                  const SizedBox(height: 12),
                  PillButton(
                    'Play the welcome animation',
                    onPressed: () => context.push('/welcome-intro'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Runs the store link by hand and says what it found.
///
/// The session does this on its own for a verified, unlinked account; this
/// button exists so a person can force it and *see* the answer instead of
/// wondering whether it ran.
class _LinkCard extends ConsumerStatefulWidget {
  const _LinkCard();

  @override
  ConsumerState<_LinkCard> createState() => _LinkCardState();
}

class _LinkCardState extends ConsumerState<_LinkCard> {
  Future<LinkResult>? _link;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LbmCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Asks the backend to match this account to the store by its '
            'confirmed email: the Shopify customer, past orders, and the '
            'Shipturtle vendor. Runs on its own after sign-up; this repeats it.',
            style: LbmText.tiny.copyWith(color: c.ink2),
          ),
          const SizedBox(height: 12),
          PillButton(
            _link == null ? 'Link my store account now' : 'Run again',
            onPressed: () => setState(() {
              _link = ref.read(profileRepositoryProvider).linkStoreAccounts();
            }),
          ),
          if (_link != null) ...[
            const SizedBox(height: 12),
            FutureBuilder<LinkResult>(
              future: _link,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return LbmErrorCard(error: snapshot.error!);
                }
                final r = snapshot.data;
                if (r == null) {
                  return Text(
                    'Asking…',
                    style: LbmText.tiny.copyWith(color: c.ink3),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Fact(
                      'Shopify customer',
                      r.linkedCustomer ? 'found' : 'none with this email',
                      good: r.linkedCustomer,
                    ),
                    _Fact(
                      'Past orders',
                      r.alreadyLinked
                          ? 'already copied on an earlier link'
                          : '${r.backfilledOrders} orders, ${r.backfilledItems} items',
                    ),
                    _Fact(
                      'Shipturtle vendor',
                      r.linkedVendor ? 'matched' : 'none with this email',
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// The three admin actions: claim the flag, mirror the collections, import
/// the catalog. Each says what it did in one line, and a failure shows the
/// backend's own message — "not on the admin list" tells the person exactly
/// which console document to edit.
class _AdminCard extends ConsumerStatefulWidget {
  const _AdminCard({required this.onClaimed});

  final VoidCallback onClaimed;

  @override
  ConsumerState<_AdminCard> createState() => _AdminCardState();
}

class _AdminCardState extends ConsumerState<_AdminCard> {
  bool _busy = false;
  String? _status;
  Object? _error;
  final _sellerUid = TextEditingController();
  final _vendorName = TextEditingController();

  @override
  void dispose() {
    _sellerUid.dispose();
    _vendorName.dispose();
    super.dispose();
  }

  Future<String> _setVendor() async {
    final uid = _sellerUid.text.trim();
    final vendor = _vendorName.text.trim();
    if (uid.isEmpty || vendor.isEmpty) {
      return 'Enter both the seller\'s uid and the vendor string.';
    }
    final previous = await _repo.setSellerVendor(uid: uid, vendorName: vendor);
    return 'Seller $uid now sells as "$vendor" (was "$previous"). Their '
        'products re-attribute within seconds; the seller pulls to refresh.';
  }

  Future<void> _run(String working, Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _status = working;
    });
    try {
      final result = await action();
      if (mounted) setState(() => _status = result);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  DiagnosticsRepository get _repo => ref.read(diagnosticsRepositoryProvider);

  Future<String> _claim() async {
    await _repo.claimAdmin();
    widget.onClaimed();
    return 'Admin claim granted to this account.';
  }

  Future<String> _reindexTags() async {
    final result = await _repo.backfillProfileTags();
    return 'Checked ${result.checked} profiles, repaired ${result.updated} '
        '(hashtags, names, post and purchase counts).';
  }

  Future<String> _backfillShops() async {
    final r = await _repo.backfillShopShells();
    return 'Gave ${r.shells} of ${r.vendors} shops a profile, and attached '
        '${r.products} listings that had none. Took ${r.posts} feed posts '
        'back off shops nobody has signed up for.';
  }

  Future<String> _sync() async {
    final count = await _repo.syncCollections();
    return 'Synced $count collections. Pull the Market feed to refresh.';
  }

  /// CP-P4: a buyer must be refused before anything reaches the store. The
  /// id does not exist, so a seller gets "no longer exists" instead — also
  /// informative.
  Future<String> _tryPublish() async {
    try {
      await ref
          .read(sellerRepositoryProvider)
          .publishListing('diagnostics-probe');
      return 'Unexpected: the backend accepted a publish for a missing draft.';
    } on RepositoryException catch (error) {
      return 'Backend answered: ${error.runtimeType} · ${error.message}';
    }
  }

  Future<String> _backfill({required bool reset}) async {
    var progress = await _repo.backfillCatalog(reset: reset);
    while (!progress.done) {
      if (mounted) {
        setState(() => _status = 'Importing… ${progress.total} so far');
      }
      progress = await _repo.backfillCatalog();
    }
    return 'Imported ${progress.total} products. Done.';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LbmCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Admins only. Claim admin works when this account\'s confirmed '
            'email is listed in Firestore: collection _internal → document admins '
            '(field "emails"). Sync mirrors the store\'s collections; '
            'Backfill imports every product, in pages, and can be run again '
            'safely.',
            style: LbmText.tiny.copyWith(color: c.ink2),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              PillButton(
                'Claim admin',
                small: true,
                expand: false,
                onPressed: _busy ? null : () => _run('Claiming…', _claim),
              ),
              PillButton(
                'Sync collections',
                small: true,
                expand: false,
                style: PillStyle.quiet,
                onPressed: _busy ? null : () => _run('Syncing…', _sync),
              ),
              PillButton(
                'Reindex profiles',
                small: true,
                expand: false,
                style: PillStyle.quiet,
                onPressed: _busy
                    ? null
                    : () => _run('Reindexing…', _reindexTags),
              ),
              PillButton(
                'Shop profiles',
                small: true,
                expand: false,
                style: PillStyle.quiet,
                onPressed: _busy
                    ? null
                    : () => _run('Building…', _backfillShops),
              ),
              PillButton(
                'Backfill catalog',
                small: true,
                expand: false,
                style: PillStyle.quiet,
                onPressed: _busy
                    ? null
                    : () => _run('Importing…', () => _backfill(reset: false)),
              ),
              PillButton(
                'Try publish',
                small: true,
                expand: false,
                style: PillStyle.ghost,
                onPressed: _busy
                    ? null
                    : () => _run('Asking the backend…', _tryPublish),
              ),
              PillButton(
                'Backfill from the start',
                small: true,
                expand: false,
                style: PillStyle.ghost,
                onPressed: _busy
                    ? null
                    : () => _run(
                        'Importing from the start…',
                        () => _backfill(reset: true),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Re-point a seller at the vendor string Shipturtle uses for '
            'their company (npm run shipturtle:vendors prints it). The uid '
            'is on the seller\'s own Diagnostics facts card.',
            style: LbmText.tiny.copyWith(color: c.ink2),
          ),
          const SizedBox(height: 8),
          LbmField(
            label: 'Seller uid',
            controller: _sellerUid,
            readOnly: _busy,
          ),
          const SizedBox(height: 8),
          LbmField(
            label: 'Vendor string',
            controller: _vendorName,
            hintText: 'exactly as Shipturtle shows it',
            readOnly: _busy,
          ),
          const SizedBox(height: 8),
          PillButton(
            'Set seller vendor',
            small: true,
            expand: false,
            style: PillStyle.quiet,
            onPressed: _busy ? null : () => _run('Re-pointing…', _setVendor),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            LbmErrorCard(error: _error!),
          ] else if (_status != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (_busy) ...[
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    _status!,
                    style: LbmText.tiny.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _busy ? c.ink2 : c.sage,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FactsCard extends StatelessWidget {
  const _FactsCard({required this.facts, required this.onRefresh});

  final AuthFacts facts;
  final VoidCallback onRefresh;

  String get _text => [
    'backend:       ${facts.backend}',
    'uid:           ${facts.uid ?? '(signed out)'}',
    'email:         ${facts.email ?? '-'}',
    'anonymous:     ${facts.isAnonymous}',
    'emailVerified: ${facts.emailVerified}',
    'seller claim:  ${facts.isSeller}',
    'admin claim:   ${facts.isAdmin}',
    'isLinked:      ${facts.isLinked}',
  ].join('\n');

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LbmCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Fact('Backend', facts.backend),
          _Fact('Account', facts.uid ?? 'signed out'),
          _Fact('Email', facts.email ?? '-'),
          _Fact('Guest', facts.isAnonymous ? 'yes' : 'no'),
          _Fact(
            'Email verified',
            facts.emailVerified ? 'yes' : 'no',
            good: facts.emailVerified,
          ),
          _Fact('Seller claim', facts.isSeller ? 'yes' : 'no'),
          _Fact('Admin claim', facts.isAdmin ? 'yes' : 'no'),
          _Fact('Linked to the store', facts.isLinked ? 'yes' : 'not yet'),
          const SizedBox(height: 10),
          Row(
            children: [
              PillButton(
                'Copy',
                small: true,
                expand: false,
                style: PillStyle.quiet,
                onPressed: () => Clipboard.setData(ClipboardData(text: _text)),
              ),
              const SizedBox(width: 6),
              PillButton(
                'Refresh',
                small: true,
                expand: false,
                style: PillStyle.ghost,
                onPressed: onRefresh,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Claims come from the token on this phone. If a grant happened '
            'and this still says no, the token has not refreshed.',
            style: LbmText.xtiny.copyWith(color: c.ink3),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.good});

  final String label;
  final String value;
  final bool? good;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(label, style: LbmText.tiny.copyWith(color: c.ink2)),
          ),
          Expanded(
            child: Text(
              value,
              style: LbmText.tiny.copyWith(
                fontWeight: FontWeight.w700,
                color: good == null ? c.ink : (good! ? c.sage : c.clay),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final HealthReport report;

  String get _text {
    final buffer = StringBuffer()
      ..writeln('--- LBM backend health (paste to Claude) ---')
      ..writeln('project: ${report.project}')
      ..writeln('at:      ${report.at.toIso8601String()}');
    for (final check in report.checks) {
      buffer.writeln(
        '${check.ok ? 'PASS' : 'FAIL'}  ${check.name}: ${check.summary}',
      );
      if (!check.ok && check.fix != null) {
        buffer.writeln('      fix -> ${check.fix}');
      }
    }
    buffer.writeln('--------------------------------------------');
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LbmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RowStack(
            children: [
              for (final check in report.checks)
                ListRow(
                  leading: Icon(
                    check.ok ? Icons.check_circle_rounded : Icons.error_rounded,
                    size: 20,
                    color: check.ok ? c.sage : c.clay,
                  ),
                  title: Text(check.name),
                  subtitle: Text(
                    check.ok || check.fix == null
                        ? check.summary
                        : '${check.summary}\nfix: ${check.fix}',
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                  ),
                  crossAxisAlignment: CrossAxisAlignment.start,
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: PillButton(
              'Copy report for Claude',
              small: true,
              expand: false,
              style: PillStyle.quiet,
              onPressed: () => Clipboard.setData(ClipboardData(text: _text)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Every advert and announcement, and a way to see any of them on demand.
///
/// Grace asked for this (2026-09-14): a popup shows once per phone per app
/// opening, so testing one meant force-closing the app, and testing it twice
/// meant reinstalling. **Show it now** ignores every rule, including the
/// audience filter, so an advert aimed at sellers can be checked by someone
/// who is not one. Nothing is counted while testing.
class _PromosCard extends ConsumerWidget {
  const _PromosCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final promos = ref.watch(allPromosProvider);
    final seen = ref.watch(promosSeenProvider);
    final isSeller = ref.watch(isSellerProvider);
    final linked = ref.watch(directoryLinkProvider).value?.linked ?? false;
    final turnTaken = ref.watch(promoTurnTakenProvider);

    return LbmCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Everything live, whoever it is aimed at. Show it now ignores the '
            'three-second wait, the one-per-opening rule, the never-twice '
            'rule and the audience, and is not counted as seen or tapped.',
            style: LbmText.tiny.copyWith(color: c.ink2),
          ),
          const SizedBox(height: 12),
          LbmAsync<List<Promo>>(
            promos,
            skeleton: const ListRowSkeleton(rows: 2),
            onRetry: () => ref.invalidate(allPromosProvider),
            isEmpty: (items) => items.isEmpty,
            empty: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Nothing live. Post one from the admin website, then Refresh.',
                style: LbmText.tiny.copyWith(color: c.ink3),
              ),
            ),
            data: (items) => RowStack(
              children: [
                for (final promo in items)
                  ListRow(
                    leading: Icon(
                      promo.kind == PromoKind.announcement
                          ? Icons.campaign_outlined
                          : Icons.sell_outlined,
                      color: c.ink2,
                    ),
                    title: Text(promo.title),
                    subtitle: Text(
                      [
                        promo.kind.label,
                        promo.audience.label,
                        if (promo.imageUrls.length > 1)
                          '${promo.imageUrls.length} photos'
                        else if (promo.hasPhoto)
                          '1 photo'
                        else
                          'no photo',
                        if (!promo.showsTo(
                          isSeller: isSeller,
                          directoryLinked: linked,
                        ))
                          'not aimed at you',
                        if (seen.contains(promo.id)) 'already seen here',
                      ].join(' · '),
                    ),
                    trailing: PillButton(
                      'Show it',
                      small: true,
                      expand: false,
                      style: PillStyle.ghost,
                      onPressed: () =>
                          ref.read(promoOverrideProvider.notifier).show(promo),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PillButton(
                'Refresh',
                small: true,
                expand: false,
                style: PillStyle.quiet,
                onPressed: () => ref.invalidate(allPromosProvider),
              ),
              PillButton(
                'Forget what I have seen',
                small: true,
                expand: false,
                style: PillStyle.quiet,
                onPressed: () async {
                  await ref.read(promosSeenProvider.notifier).forget();
                  ref.read(promoTurnTakenProvider.notifier).release();
                  ref.invalidate(promoForThisLaunchProvider);
                },
              ),
              if (turnTaken)
                PillButton(
                  'Let another one show',
                  small: true,
                  expand: false,
                  style: PillStyle.quiet,
                  onPressed: () {
                    ref.read(promoTurnTakenProvider.notifier).release();
                    ref.invalidate(promoForThisLaunchProvider);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The notification delivery suite: this phone is the device under test.
///
/// Each check has the backend do one real thing to this account, as a bot,
/// and passes only on what this phone actually receives. Admins only, dev
/// backend only; the results are plain lines for pasting to Claude.
class _DeliveryCard extends ConsumerStatefulWidget {
  const _DeliveryCard();

  @override
  ConsumerState<_DeliveryCard> createState() => _DeliveryCardState();
}

class _DeliveryCardState extends ConsumerState<_DeliveryCard> {
  final _results = <CheckResult>[];
  bool _running = false;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _results.clear();
    });
    final suite = ref.read(notificationDeliverySuiteProvider);
    await suite.run(
      onResult: (r) {
        if (mounted) setState(() => _results.add(r));
      },
    );
    if (mounted) setState(() => _running = false);
  }

  String get _text => [
    'Notification delivery · ${DateTime.now().toIso8601String()}',
    for (final r in _results) r.line,
  ].join('\n');

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final passed = _results.where((r) => r.status == CheckStatus.pass).length;
    final failed = _results.where((r) => r.status != CheckStatus.pass).length;

    return LbmCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Proves pushes reach this phone: a comment, the 20 minute limit, '
            'a mention, a direct message, quiet hours, an announcement (sent '
            'only to this phone) and the forum digest. A check passes only on '
            'what actually arrives here. Keep the app open on this screen; '
            'it takes about four minutes. Admins only, dev backend only. Your '
            'quiet hours are put back afterwards and the test posts removed.',
            style: LbmText.tiny.copyWith(color: c.ink2, height: 1.5),
          ),
          const SizedBox(height: 12),
          if (kIsWeb)
            Text(
              'Run this on a phone: a browser cannot receive these pushes.',
              style: LbmText.tiny.copyWith(
                fontWeight: FontWeight.w800,
                color: c.clay,
              ),
            )
          else
            PillButton(
              _running
                  ? 'Running… ${_results.length} done'
                  : _results.isEmpty
                  ? 'Run the delivery tests'
                  : 'Run again',
              onPressed: _running ? null : _run,
            ),
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final r in _results) _ResultRow(result: r),
            if (!_running) ...[
              const SizedBox(height: 8),
              Text(
                '$passed passed, $failed not',
                style: LbmText.tiny.copyWith(
                  fontWeight: FontWeight.w800,
                  color: failed == 0 ? c.sage : c.clay,
                ),
              ),
              const SizedBox(height: 8),
              PillButton(
                'Copy results',
                small: true,
                expand: false,
                style: PillStyle.quiet,
                onPressed: () => Clipboard.setData(ClipboardData(text: _text)),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result});

  final CheckResult result;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (IconData icon, Color colour) = switch (result.status) {
      CheckStatus.pass => (Icons.check_circle_rounded, c.sage),
      CheckStatus.fail => (Icons.cancel_rounded, c.clay),
      CheckStatus.skip => (Icons.remove_circle_outline_rounded, c.ink3),
      CheckStatus.inconclusive => (Icons.help_rounded, c.clay),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colour),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.name,
                  style: LbmText.tiny.copyWith(
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                  ),
                ),
                if (result.detail.isNotEmpty)
                  Text(
                    result.detail,
                    style: LbmText.xtiny.copyWith(color: c.ink2),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One button per kind of notification, raising what it looks like on this
/// phone right now, the way the mockup's trigger panel did.
///
/// Nothing is sent and nothing is written: each button hands the same
/// choreography the real event would reach, in preview mode, so it shows
/// whatever the clock says (quiet hours do not hide a preview) and wherever
/// the phone is. For whether a real push arrives, see Notification delivery
/// below.
class _PreviewCard extends ConsumerWidget {
  const _PreviewCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final ui = ref.read(notificationsUiProvider.notifier);

    void say(String line) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(line)));

    /// Somebody real to put on the DM banner: whoever the latest
    /// conversation is with, or failing that this account.
    String someone() {
      final me = ref.read(currentUidProvider) ?? '';
      final inbox = ref.read(inboxProvider).value ?? const [];
      for (final conversation in inbox) {
        for (final id in conversation.participantIds) {
          if (id != me) return id;
        }
      }
      return me;
    }

    List<FeedItem> feed() => ref.read(feedItemsProvider).value ?? const [];

    final previews = <(IconData, String, String, VoidCallback)>[
      (
        Icons.campaign_outlined,
        'Announcement',
        'The popup springs up, and the bell on You rings next time you see it.',
        () {
          ref
              .read(promoOverrideProvider.notifier)
              .show(
                const Promo(
                  id: 'preview-announcement',
                  kind: PromoKind.announcement,
                  title: 'Town hall tonight at 7',
                  caption: 'Come tell us what to build next. Live in the app.',
                  audience: AnnouncementAudience.all,
                  ctaLabel: 'Remind me',
                ),
              );
          ui.handle(UiEvent.announcement, preview: true);
        },
      ),
      (
        Icons.sell_outlined,
        'Advert',
        'The popup, labelled Sponsored. Never a push or a bell.',
        () => ref
            .read(promoOverrideProvider.notifier)
            .show(
              const Promo(
                id: 'preview-advert',
                kind: PromoKind.ad,
                title: '20% off everything this week',
                caption: 'Daybreak Digitals, print shop in Detroit.',
                audience: AnnouncementAudience.all,
                ctaLabel: 'Shop the drop',
              ),
            ),
      ),
      (
        Icons.mail_outline_rounded,
        'Direct message',
        'The banner drops in with Reply for 4 seconds.',
        () => ui.handle(
          UiEvent.dm,
          title: 'Kali Brooks',
          subtitle: "Pawpaw's in through mid-October, want me to hold two?",
          route: '/you/messages',
          personId: someone(),
          preview: true,
        ),
      ),
      (
        Icons.alternate_email_rounded,
        'Mention',
        'A toast, and the bell rings.',
        () => ui.handle(
          UiEvent.mention,
          kicker: 'Mention · Open chat',
          title: 'Ama Mensah mentioned you',
          subtitle: "@you Kali's in Ypsi too",
          route: '/community',
          preview: true,
        ),
      ),
      (
        Icons.chat_bubble_outline_rounded,
        'Reply to your post',
        'A toast, and the bell rings.',
        () => ui.handle(
          UiEvent.comment,
          kicker: 'Your post',
          title: 'Holler Goods replied',
          subtitle: "Not so far, it's a thread embroidery",
          route: '/you/notifications',
          actionLabel: 'See',
          preview: true,
        ),
      ),
      (
        Icons.forum_outlined,
        'Forum reply',
        'No toast. "1 new" on the thread pin in the Market, and a dot on '
            'Community.',
        () {
          final thread = feed().whereType<ThreadItem>().firstOrNull;
          ui.handle(
            UiEvent.forumReply,
            route: thread == null
                ? null
                : '/community/thread/${thread.thread.id}',
            threadId: thread?.thread.id,
            preview: true,
          );
          say(
            thread == null
                ? 'No thread pin in the feed right now; the Community dot is on.'
                : 'Go to the Market: "1 new" is on "${thread.thread.title}".',
          );
        },
      ),
      (
        Icons.circle_outlined,
        'Open chat, getting busy',
        'Never a toast. Five unseen messages put a dot on Community.',
        () {
          for (var i = 0; i < chatDotAfter; i++) {
            ui.handle(UiEvent.chat, preview: true);
          }
        },
      ),
      (
        Icons.tag_rounded,
        'Post under a tag you follow',
        'A toast, and the bell rings.',
        () => ui.handle(
          UiEvent.tagPost,
          kicker: 'New under #Handmade',
          title: 'Madi Winger Art posted',
          subtitle: 'Checkered sunflower arches, back in stock',
          route: '/market',
          actionLabel: 'See',
          preview: true,
        ),
      ),
      (
        Icons.auto_awesome_outlined,
        'New from a maker you follow',
        'No toast: the pin grows in at the top of the Market and its button '
            'hops.',
        () {
          final pin = feed().whereType<ProductItem>().firstOrNull;
          ui.handle(UiEvent.drop, feedKey: pin?.key, preview: true);
          say(
            pin == null
                ? 'No product pin in the feed right now.'
                : 'Go to the Market: "${pin.product.title}" grows in.',
          );
        },
      ),
      (
        Icons.inventory_2_outlined,
        'Delivered',
        'The review prompt grows in, and a dot on You.',
        () {
          final nudge = feed().whereType<NudgeItem>().firstOrNull;
          ui.handle(UiEvent.delivered, feedKey: nudge?.key, preview: true);
          if (nudge == null) {
            say('No review prompt in the feed right now; the You dot is on.');
          }
        },
      ),
      (
        Icons.shopping_bag_outlined,
        'Your own action',
        'The cart toast with the photo. Never a bell.',
        () {
          final pin = feed().whereType<ProductItem>().firstOrNull;
          LbmToast.show(
            context,
            title: 'In your little blue cart',
            subtitle: pin?.product.title ?? 'Wild Plum Jam',
            thumbnailUrl: pin?.product.imageUrls.firstOrNull,
          );
        },
      ),
      (
        Icons.bedtime_outlined,
        'After quiet hours',
        'The one-line "waiting" strip, as the first open in the morning shows.',
        () => ui.previewQuietStrip(3),
      ),
    ];

    return LbmCard(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
            child: Text(
              'How each notification looks on this phone. Nothing is sent; '
              'each one shows exactly what the real event would.',
              style: LbmText.tiny.copyWith(color: c.ink2, height: 1.5),
            ),
          ),
          for (final (icon, title, what, onTap) in previews)
            ListRow(
              leading: Icon(icon, size: 22, color: c.accentText),
              title: Text(title),
              subtitle: Text(what),
              trailing: Icon(
                Icons.play_circle_outline_rounded,
                size: 22,
                color: c.ink3,
              ),
              onTap: onTap,
            ),
        ],
      ),
    );
  }
}
