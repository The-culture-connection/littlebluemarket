import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/fixtures.dart';
import '../models/models.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'primitives.dart';
import 'product_art.dart';

/// The shared bottom-sheet body: the grip, the soft top radius, and padding.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: LbmRadius.sheetR,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: c.skyMist,
                    borderRadius: LbmRadius.pillR,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

Future<T?> _show<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (context) => SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: builder(context),
      ),
    ),
  );
}

// ------------------------------------------------------------------ the gate

/// The sheet a guest gets when they reach for something that needs a profile.
Future<void> showGateSheet(BuildContext context) {
  return _show(context, (sheetContext) {
    final c = sheetContext.c;
    return _Sheet(
      children: [
        Column(
          children: [
            Image.asset(Fx.cart, width: 80),
            const SizedBox(height: 8),
            Text(
              'Make a profile to do that',
              textAlign: TextAlign.center,
              style: LbmText.display.copyWith(fontSize: 21, color: c.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'Guests can browse the market and read posts. Buying, posting, '
              'reviewing, messaging, and the community need a profile.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.55, color: c.ink2),
            ),
          ],
        ),
        const SizedBox(height: 16),
        PillButton(
          'Create a profile',
          onPressed: () {
            Navigator.of(sheetContext).pop();
            context.push('/signin?create=1');
          },
        ),
        const SizedBox(height: 10),
        PillButton(
          'Sign in',
          style: PillStyle.ghost,
          onPressed: () {
            Navigator.of(sheetContext).pop();
            context.push('/signin');
          },
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text(
            'Keep looking around',
            style: TextStyle(
              fontFamily: kBodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.ink3,
            ),
          ),
        ),
      ],
    );
  });
}

/// Runs [action] if there is a profile, and opens the gate if there is not.
///
/// Every gated affordance — Buy, Message, post, review, the Community and You
/// tabs — goes through here, so the rule lives in one place.
bool requireProfile(BuildContext context, WidgetRef ref, VoidCallback action) {
  if (ref.read(sessionProvider).isGuest) {
    showGateSheet(context);
    return false;
  }
  action();
  return true;
}

// ------------------------------------------------------------------- the buy

/// The buy sheet. Confirm quantity, address and total.
Future<void> showBuySheet(BuildContext context, Product product) {
  return _show(context, (sheetContext) => _BuySheet(product: product));
}

class _BuySheet extends StatefulWidget {
  const _BuySheet({required this.product});

  final Product product;

  @override
  State<_BuySheet> createState() => _BuySheetState();
}

class _BuySheetState extends State<_BuySheet> {
  int _quantity = 1;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final p = widget.product;
    final seller = Fx.person(p.sellerId);
    final total = p.priceCents * _quantity + Fx.shippingCents;

    return _Sheet(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 60,
              child: ProductArt(
                p,
                square: true,
                borderRadius: const BorderRadius.all(Radius.circular(14)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                      color: c.ink,
                    ),
                  ),
                  Text(
                    '${seller.name} · ${p.type}',
                    style: LbmText.tiny.copyWith(color: c.ink2),
                  ),
                  const SizedBox(height: 3),
                  InlineLink(
                    'See full details',
                    fontSize: 11.5,
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push('/market/product/${p.id}');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              p.price,
              style: LbmText.display.copyWith(fontSize: 20, color: c.ink),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.skyWash,
            borderRadius: const BorderRadius.all(Radius.circular(18)),
          ),
          child: Column(
            children: [
              _SummaryRow(
                label: 'Quantity',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StepperButton(
                      icon: Icons.remove_rounded,
                      onTap: _quantity > 1
                          ? () => setState(() => _quantity--)
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '$_quantity',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: c.ink,
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                    ),
                    _StepperButton(
                      icon: Icons.add_rounded,
                      onTap: () => setState(() => _quantity++),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _SummaryRow(label: 'Ship to', value: 'Maya E. · Detroit, MI'),
              const SizedBox(height: 10),
              _SummaryRow(label: 'Shipping', value: '\$5.60 · USPS Ground'),
              const SizedBox(height: 14),
              _SummaryRow(
                label: 'Total',
                value: formatCents(total),
                strong: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PillButton(
          'Place order',
          onPressed: () {
            Navigator.of(context).pop();
            context.go('/you/shipping');
          },
        ),
        const SizedBox(height: 10),
        Text(
          'Lands in Purchases on your profile and in Receiving under Shipping.',
          textAlign: TextAlign.center,
          style: LbmText.xtiny.copyWith(color: c.ink3, height: 1.55),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    this.value,
    this.trailing,
    this.strong = false,
  });

  final String label;
  final String? value;
  final Widget? trailing;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: strong ? 15 : 13.5,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w400,
              color: strong ? c.ink : c.ink2,
            ),
          ),
        ),
        const SizedBox(width: 10),
        if (trailing != null)
          trailing!
        else
          Flexible(
            child: Text(
              value ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: strong ? 15 : 13.5,
                fontWeight: FontWeight.w800,
                color: c.ink,
                fontFeatures: kTabularFigures,
              ),
            ),
          ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 19,
          color: onTap == null ? c.ink3 : c.ink,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- the new post

/// The sheet behind the + on your own profile.
Future<void> showNewPostSheet(BuildContext context) {
  const options = [
    ('A good', 'Something physical you make or resell'),
    ('A service', 'Time, skill, or a booking'),
    ('A review', 'Attached to something you bought'),
  ];

  return _show(context, (sheetContext) {
    final c = sheetContext.c;
    return _Sheet(
      children: [
        Text(
          'What are you posting?',
          style: LbmText.display.copyWith(fontSize: 21, color: c.ink),
        ),
        const SizedBox(height: 14),
        for (final (title, subtitle) in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ListRow(
              background: c.skyWash,
              borderRadius: const BorderRadius.all(Radius.circular(18)),
              title: Text(title),
              subtitle: Text(subtitle),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: c.ink3,
                size: 22,
              ),
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'Every post can carry initiative hashtags. Reviews stay attached to '
          'the product they came from.',
          style: LbmText.xtiny.copyWith(color: c.ink3, height: 1.55),
        ),
      ],
    );
  });
}
