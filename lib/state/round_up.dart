import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the buyer asked to round up, and by how much.
///
/// The arithmetic is duplicated from `functions/src/donations.ts` on purpose
/// and the two are kept identical: the app has to show the amount before
/// the checkout is built, and the server has to refuse a number it did not
/// compute itself. Neither trusts the other, which is the right shape for
/// something that ends in a charge.

/// Round a subtotal up to the next whole dollar. Pure.
///
/// A subtotal already on a dollar rounds up a whole one rather than giving
/// nothing: a switch that adds a zero line reads as broken, and "round up"
/// on $63.00 meaning "give nothing" is not what anybody turning it on
/// expects.
int roundUpCentsFor(int subtotalCents) {
  if (subtotalCents <= 0) return 0;
  final remainder = subtotalCents % 100;
  return remainder == 0 ? 100 : 100 - remainder;
}

/// Off, every time.
///
/// Not remembered between visits, and deliberately: a preference that
/// silently re-arms is how a one-off gift becomes a recurring charge nobody
/// agreed to. It is one tap, and the line is visible in the totals.
class RoundUp extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool on) => state = on;
  void toggle() => state = !state;
}

final roundUpProvider = NotifierProvider<RoundUp, bool>(RoundUp.new);
