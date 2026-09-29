import 'package:flutter/foundation.dart';

/// What it cost to run Little Blue Market in one month, and what came in.
///
/// Read from `funding/{yyyy-mm}`, written only by the order webhook and by
/// Grace. Every number on the Chip in page comes from here: the phase brief
/// is blunt about it — "never invent numbers for the transparency tiles —
/// read them from `funding/{month}` or show —". A made-up bill on a page
/// asking people for money is the one thing that would deserve the cynicism
/// the page is trying to earn its way out of.
@immutable
class Funding {
  const Funding({
    required this.month,
    this.raisedCents = 0,
    this.budgetCents = 0,
    this.donors = 0,
    this.costs = const {},
  });

  /// `yyyy-mm`, the document id.
  final String month;

  /// What members chipped in. Incremented by the order webhook.
  final int raisedCents;

  /// What the month is expected to cost. Grace's number, not a guess.
  final int budgetCents;

  /// How many distinct people gave. Counted once per person per month.
  final int donors;

  /// The bill, broken down: `{'Hosting & push': 4200, ...}`. Shown as tiles
  /// in the order the map gives them.
  final Map<String, int> costs;

  /// True when there is enough here to show a bill rather than dashes.
  bool get hasBill => costs.isNotEmpty;

  /// True when the progress bar means anything. A budget of zero would be
  /// a full bar on the first penny, which flatters and misleads.
  bool get hasTarget => budgetCents > 0;

  /// How far through the month's costs the members have got, 0 to 1.
  double get progress =>
      hasTarget ? (raisedCents / budgetCents).clamp(0.0, 1.0) : 0;

  /// The month before [month], as a document id. Pure, and it has to handle
  /// January without reaching for a DateTime.
  static String previousMonthOf(String month) {
    final parts = month.split('-');
    if (parts.length != 2) return month;
    final year = int.tryParse(parts[0]);
    final index = int.tryParse(parts[1]);
    if (year == null || index == null) return month;
    final previous = index == 1 ? (year - 1, 12) : (year, index - 1);
    return '${previous.$1.toString().padLeft(4, '0')}-'
        '${previous.$2.toString().padLeft(2, '0')}';
  }

  /// `yyyy-mm` for a moment. The one place the format is decided, so the
  /// app and `orders.ts` cannot disagree about which month a gift lands in.
  static String monthOf(DateTime when) =>
      '${when.year.toString().padLeft(4, '0')}-'
      '${when.month.toString().padLeft(2, '0')}';
}
