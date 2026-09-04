/// Every display string in the app is produced here.
///
/// Models carry real types — cents, counts, `DateTime` — because a backend
/// hands back numbers and timestamps, not "$4,820" and "3d". The prototype
/// stored the rendered string instead, which made the models unsortable,
/// unsummable, and impossible to serialise. This file is where the number
/// becomes the label again, and the only place a format is decided.
///
/// Hand-rolled rather than `intl`: the app is single-locale, these six formats
/// are small, and keeping them dependency-free means the tests are exact rather
/// than dependent on an ICU version. Swap to `intl` the day localisation lands.
library;

/// Relative-time helpers take an explicit [now] so tests are deterministic and
/// fixture ages do not drift as the repository gets older.
abstract final class Fmt {
  /// `$8` for whole dollars, `$13.60` otherwise. Negative values keep the sign
  /// outside the symbol: `-$4.20`.
  static String money(int cents) {
    final sign = cents < 0 ? '-' : '';
    final abs = cents.abs();
    final dollars = count(abs ~/ 100);
    final remainder = abs % 100;
    if (remainder == 0) return '$sign\$$dollars';
    return '$sign\$$dollars.${remainder.toString().padLeft(2, '0')}';
  }

  /// `2412` becomes `2,412`.
  static String count(int n) {
    final digits = n.abs().toString();
    final buffer = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// Compact age, as it reads under a review or a thread: `now`, `4m`, `6h`,
  /// `3d`, `2w`, `5mo`, `1y`.
  static String relative(DateTime t, {DateTime? now}) {
    final d = (now ?? DateTime.now()).difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    if (d.inDays < 30) return '${d.inDays ~/ 7}w';
    if (d.inDays < 365) return '${d.inDays ~/ 30}mo';
    return '${d.inDays ~/ 365}y';
  }

  /// Wall-clock time on a chat bubble: `9:02`, `14:41`.
  static String clock(DateTime t) =>
      '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

  /// Inbox ages read differently from review ages: recent messages want a
  /// duration, older ones want a day name, and anything past a week wants a
  /// date. `2m`, `Yesterday`, `Mon`, `14 Mar`.
  static String inboxAge(DateTime t, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final d = reference.difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';

    final startOfToday = DateTime(reference.year, reference.month, reference.day);
    final daysApart = startOfToday.difference(DateTime(t.year, t.month, t.day)).inDays;
    if (daysApart == 1) return 'Yesterday';
    if (daysApart < 7) return _weekdays[t.weekday - 1];
    return '${t.day} ${_months[t.month - 1]}';
  }

  /// `4 mi`, `0.5 mi`. Distances under ten miles keep one decimal, because the
  /// difference between 2 and 2.4 miles matters when you are deciding whether
  /// to walk.
  static String distanceMiles(double miles) {
    if (miles < 10) {
      final oneDecimal = (miles * 10).round() / 10;
      final text = oneDecimal == oneDecimal.roundToDouble()
          ? oneDecimal.round().toString()
          : oneDecimal.toStringAsFixed(1);
      return '$text mi';
    }
    return '${miles.round()} mi';
  }

  static const _weekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}
