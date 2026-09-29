import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repositories.dart' show RepositoryException;
import '../../models/formatting.dart';
import '../../models/funding.dart';
import '../../state/donation_nudge.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sheets.dart' show showCheckoutHandoff;

/// Asking for money, with the bill shown first.
///
/// The order of this page is the argument: what last month cost, what came
/// in against it, and only then the amounts. An ask that leads with the ask
/// is a donation box; an ask that leads with the bill is a subscription
/// somebody can decide about.
///
/// Every figure is read from `funding/{month}` or shown as an em dash. The
/// phase brief is blunt about it and it is the right instinct: a made-up
/// bill on a page asking for money would deserve the cynicism the page is
/// trying to earn its way out of.
///
/// There is no Monthly card. That becomes a store subscription in Phase 10,
/// because a recurring digital membership is Apple and Google's business,
/// and a "coming soon" card is an advert for something nobody can buy.
class ChipInScreen extends ConsumerStatefulWidget {
  const ChipInScreen({super.key});

  @override
  ConsumerState<ChipInScreen> createState() => _ChipInScreenState();
}

class _ChipInScreenState extends ConsumerState<ChipInScreen> {
  /// The amounts on the product, in cents. Matched by price at checkout, so
  /// this list and Shopify can be compared by reading them.
  static const _amounts = [200, 500, 1000, 2000];

  int _selected = 500;
  bool _busy = false;

  Future<void> _chipIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final handoff = await ref
          .read(commerceRepositoryProvider)
          .chipIn(amountCents: _selected);
      if (!mounted) return;
      // The same hand-off as buying something, deliberately: this is the
      // store's checkout, which is what keeps it out of in-app purchase
      // territory, and the copy above says so plainly.
      await showCheckoutHandoff(context, handoff);
    } on RepositoryException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeError(error).body)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bill = ref.watch(fundingLastMonthProvider);
    final canChipIn = ref.watch(appConfigProvider).value?.canChipIn ?? false;

    return LbmScreen(
      appBar: const LbmAppBar(title: 'Chip in'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 32),
        children: [
          Text(
            'Little Blue Market is member-run',
            style: LbmText.display.copyWith(fontSize: 22, color: c.ink),
          ),
          const SizedBox(height: 6),
          Text(
            'No ads, no investors. The people using it pay for it, and the '
            'bill is published every month.',
            style: TextStyle(fontSize: 14, height: 1.5, color: c.ink2),
          ),
          const SizedBox(height: 16),

          _BillCard(bill: bill),

          if (canChipIn) ...[
            const SizedBox(height: 14),
            LbmCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'One time',
                    style: LbmText.display.copyWith(fontSize: 18, color: c.ink),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final cents in _amounts)
                        LbmChip(
                          Fmt.money(cents),
                          style: cents == _selected
                              ? ChipStyle.on
                              : ChipStyle.quiet,
                          onTap: () => setState(() => _selected = cents),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _SagePill(
                    label: _busy
                        ? 'Opening checkout…'
                        : 'Chip in ${Fmt.money(_selected)}',
                    onPressed: _busy ? null : _chipIn,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Opens the same in-app checkout you buy with. '
                    'Not tax-deductible.',
                    style: LbmText.pinMeta.copyWith(color: c.ink2),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),
          LbmCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Or, at checkout',
                  style: LbmText.display.copyWith(fontSize: 18, color: c.ink),
                ),
                const SizedBox(height: 8),
                Text(
                  'Round up your next order and the change comes here. It is '
                  'off unless you turn it on, and you see it as its own line '
                  'every time.',
                  style: TextStyle(fontSize: 13.5, height: 1.5, color: c.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Last month's bill, or honest dashes.
class _BillCard extends StatelessWidget {
  const _BillCard({required this.bill});

  final AsyncValue<Funding?> bill;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LbmCard(
      padding: const EdgeInsets.all(16),
      child: LbmAsync<Funding?>(
        bill,
        skeleton: const ListRowSkeleton(rows: 2, withAvatar: false),
        // A funding document that does not exist is not an error: it is a
        // month nobody has filled in yet, and the tiles say so.
        errorBuilder: (_, _) => const _BillTiles(funding: null),
        data: (funding) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Last month's bill",
              style: LbmText.display.copyWith(fontSize: 18, color: c.ink),
            ),
            const SizedBox(height: 12),
            _BillTiles(funding: funding),
            const SizedBox(height: 14),
            _Progress(funding: funding),
          ],
        ),
      ),
    );
  }
}

class _BillTiles extends StatelessWidget {
  const _BillTiles({required this.funding});

  final Funding? funding;

  /// The three the mockup shows. Used as labels when there is no document,
  /// so the shape of the answer is visible before the answer is.
  static const _placeholders = [
    'Hosting & push',
    'Directory sync',
    'Town halls',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final costs = funding?.costs ?? const <String, int>{};
    final labels = costs.isNotEmpty ? costs.keys.toList() : _placeholders;

    // Stretch needs a height to stretch to, and a Row in a scrolling column
    // has none, so the tiles are measured first. Without this the three
    // tiles are three different heights whenever one label wraps.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, label) in labels.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 10,
                ),
                decoration: BoxDecoration(
                  color: c.skyWash,
                  borderRadius: LbmRadius.cardR,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      child: Text(
                        // No data, no number. Never an invented one.
                        costs[label] == null ? '—' : Fmt.money(costs[label]!),
                        maxLines: 1,
                        style: LbmText.display.copyWith(
                          fontSize: 18,
                          color: c.ink,
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: LbmText.pinMeta.copyWith(
                        fontSize: 11,
                        color: c.ink2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.funding});

  final Funding? funding;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final f = funding;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: LbmRadius.pillR,
          child: SizedBox(
            height: 10,
            child: Stack(
              children: [
                ColoredBox(color: c.skyMist, child: const SizedBox.expand()),
                if (f != null && f.hasTarget)
                  FractionallySizedBox(
                    widthFactor: f.progress,
                    child: ColoredBox(
                      color: c.sage,
                      child: const SizedBox.expand(),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (f != null && f.hasTarget)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text:
                      '${Fmt.count(f.donors)} '
                      '${f.donors == 1 ? 'member' : 'members'}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const TextSpan(text: ' covered '),
                TextSpan(
                  text:
                      '${Fmt.money(f.totalRaisedCents)} of '
                      '${Fmt.money(f.budgetCents)}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const TextSpan(text: '. No ads, no investors.'),
              ],
            ),
            style: TextStyle(fontSize: 13.5, height: 1.5, color: c.ink2),
          )
        else
          Text(
            // Said plainly rather than dressed up: the figures for last
            // month are not in yet.
            "Last month's figures are not published yet.",
            style: TextStyle(fontSize: 13.5, height: 1.5, color: c.ink2),
          ),
      ],
    );
  }
}

/// The sage action button.
///
/// Not [PillButton]: orchid means the cart and only the cart in this design,
/// and chipping in is not shopping.
///
/// Mist fill with ink on it, and a sage edge to carry the weight, rather
/// than solid sage with white on it. `sage` is a foreground colour here —
/// it inverts between the themes, a mid green in light and a pale one in
/// dark — so a solid fill would need a new "text on sage" token in
/// `tokens.dart`, and white on the light-mode sage is about 3.9:1, which is
/// under the threshold the accent split exists to protect. `sageMist` and
/// `ink` are an existing pair and are comfortable in both themes.
class _SagePill extends StatelessWidget {
  const _SagePill({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final on = onPressed != null;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: c.sageMist,
        borderRadius: LbmRadius.pillR,
        child: InkWell(
          onTap: onPressed,
          borderRadius: LbmRadius.pillR,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: LbmRadius.pillR,
              border: Border.all(color: on ? c.sage : c.sageMist, width: 1.5),
            ),
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: on ? c.ink : c.ink3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
