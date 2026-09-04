import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app_assets.dart';
import '../data/repositories/repositories.dart';
import '../models/models.dart';
import '../router/nav.dart';
import '../state/providers.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'async.dart';
import 'primitives.dart';
import 'product_art.dart';

/// The shared bottom-sheet body: the grip, the soft top radius, and padding.
class LbmSheet extends StatelessWidget {
  const LbmSheet({super.key, required this.children});

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

/// Presents [builder] as the app's bottom sheet, keyboard-aware.
Future<T?> showLbmSheet<T>(BuildContext context, WidgetBuilder builder) {
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
  return showLbmSheet(context, (sheetContext) {
    final c = sheetContext.c;
    return LbmSheet(
      children: [
        Column(
          children: [
            Image.asset(LbmAssets.cartMark, width: 80),
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
  if (ref.read(isGuestProvider)) {
    showGateSheet(context);
    return false;
  }
  action();
  return true;
}

/// Runs [action] only if the current user is a seller.
///
/// The seller-only affordances — posting a listing, the sales tab, revenue — go
/// through here, the same way every profile-gated one goes through
/// [requireProfile]. Note the order: both gates are checked *before* the action
/// runs, so a buyer never reaches a seller-only screen.
bool requireSeller(BuildContext context, WidgetRef ref, VoidCallback action) {
  if (ref.read(isGuestProvider)) {
    showGateSheet(context);
    return false;
  }
  if (!ref.read(isSellerProvider)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Turn on selling in Edit profile to list your work.'),
      ),
    );
    return false;
  }
  action();
  return true;
}

// ------------------------------------------------------------------- the buy

/// "Buy" adds to the cart and opens it.
///
/// The prototype's buy sheet confirmed an order against invented numbers — a
/// hardcoded ship-to address, a flat "$5.60 · USPS Ground", and a total that
/// ignored the selected variant — and then navigated as though an order had
/// been placed. None of that was true, and the parts that are true are only
/// knowable at checkout.
Future<void> showBuySheet(
  BuildContext context,
  Product product, {
  Variant? variant,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context);
  try {
    await container
        .read(commerceRepositoryProvider)
        .addLine(productId: product.id, variantId: variant?.name);
    if (!context.mounted) return;
    context.push('${branchPrefix(context)}/cart');
  } on RepositoryException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(describeError(error).body)));
  }
}

// -------------------------------------------------------------- the checkout

/// Hands the cart over to whoever takes the money.
///
/// Deliberately does not claim the purchase succeeded. The app cannot observe
/// a hosted checkout completing -- the sheet closing means the person dismissed
/// it, not that they paid -- so the copy says what is actually true and the
/// order arrives through the paid webhook.
Future<void> showCheckoutSheet(BuildContext context, CheckoutHandoff handoff) {
  return showLbmSheet(context, (sheetContext) {
    final c = sheetContext.c;
    return LbmSheet(
      children: [
        Image.asset(LbmAssets.cartMark, width: 64),
        const SizedBox(height: 10),
        Text(
          'Finish in checkout',
          textAlign: TextAlign.center,
          style: LbmText.display.copyWith(fontSize: 21, color: c.ink),
        ),
        const SizedBox(height: 8),
        Text(
          'Payment, shipping and tax are handled by the store. Your order shows '
          'up under Packages once it is confirmed.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, height: 1.55, color: c.ink2),
        ),
        const SizedBox(height: 18),
        PillButton(
          'Open checkout',
          onPressed: () {
            Navigator.of(sheetContext).pop();
            // The web handoff itself lands with the commerce proxy.
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Checkout: ${handoff.webUrl}')),
            );
          },
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text(
            'Keep shopping',
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
