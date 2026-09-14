import 'package:flutter/foundation.dart';

import 'announcement.dart';
import 'formatting.dart';

/// Advert or announcement. Grace asked for two features; they carry the same
/// fields and are drawn by the same card, so they are one model with a label
/// on it rather than two that drift apart.
///
/// The difference is what else happens when one is posted: an announcement
/// still pushes to the audience topic and still shows under the bell (see
/// `Announcement`), an advert does neither, because an advert is not news.
enum PromoKind {
  ad('ad', 'Advert'),
  announcement('announcement', 'Announcement');

  const PromoKind(this.value, this.label);

  /// The backend's word for it.
  final String value;
  final String label;

  static PromoKind fromValue(String? value) =>
      values.firstWhere((k) => k.value == value, orElse: () => PromoKind.ad);
}

/// One card that fades in over whatever is on screen. Written only by the
/// backend, from the admin website.
@immutable
class Promo {
  const Promo({
    required this.id,
    required this.kind,
    required this.title,
    required this.caption,
    required this.audience,
    this.imageUrls = const [],
    this.ctaLabel = '',
    this.ctaUrl = '',
    this.active = true,
    this.createdAt,
    this.startsAt,
    this.endsAt,
    this.impressions = 0,
    this.clicks = 0,
  });

  final String id;
  final PromoKind kind;
  final String title;
  final String caption;
  final AnnouncementAudience audience;

  /// Photographs, in order. The popup shows the first one.
  final List<String> imageUrls;

  /// The button's words, e.g. "Shop the sale". Empty means no button.
  final String ctaLabel;

  /// Where the button goes.
  final String ctaUrl;

  /// Paused from the admin website without deleting it.
  final bool active;
  final DateTime? createdAt;

  /// Optional window. Null at either end means "no bound that side".
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// How many phones have seen it, and how many tapped the button. Both
  /// maintained with `FieldValue.increment`, never read-modify-write.
  final int impressions;
  final int clicks;

  bool get hasPhoto => imageUrls.isNotEmpty;

  bool get hasCta => ctaLabel.trim().isNotEmpty && ctaUri != null;

  /// The button's destination, or null when it is not a usable web address.
  /// A link typed without a scheme still works, the way the directory card
  /// already treats a business's website.
  Uri? get ctaUri {
    final raw = ctaUrl.trim();
    if (raw.isEmpty) return null;
    final full = raw.startsWith(RegExp('https?://')) ? raw : 'https://$raw';
    final uri = Uri.tryParse(full);
    return uri == null || uri.host.isEmpty ? null : uri;
  }

  /// Live right now: switched on, and inside its window if it has one.
  bool isLiveAt(DateTime now) {
    if (!active) return false;
    final from = startsAt;
    if (from != null && now.isBefore(from)) return false;
    final until = endsAt;
    if (until != null && !now.isBefore(until)) return false;
    return true;
  }

  /// Whether this viewer is in the audience. Decided on the phone from the
  /// same two facts an announcement's audience already takes, so there is no
  /// per-person query behind a popup.
  bool showsTo({required bool isSeller, required bool directoryLinked}) =>
      audience.includes(isSeller: isSeller, directoryLinked: directoryLinked);

  String get age =>
      createdAt == null ? '' : Fmt.relative(createdAt!);
}

/// What the admin website sends.
@immutable
class NewPromo {
  const NewPromo({
    required this.kind,
    required this.title,
    required this.caption,
    required this.audience,
    this.imageUrls = const [],
    this.ctaLabel = '',
    this.ctaUrl = '',
  });

  static const titleMax = 60;
  static const captionMax = 180;
  static const ctaLabelMax = 24;
  static const photosMax = 4;

  final PromoKind kind;
  final String title;
  final String caption;
  final AnnouncementAudience audience;
  final List<String> imageUrls;
  final String ctaLabel;
  final String ctaUrl;

  bool get isValid =>
      title.trim().isNotEmpty &&
      title.trim().length <= titleMax &&
      caption.trim().isNotEmpty &&
      caption.trim().length <= captionMax &&
      ctaLabel.trim().length <= ctaLabelMax &&
      imageUrls.length <= photosMax &&
      // A button with no link, or a link with no words on the button, is a
      // dead end on the phone. Both or neither.
      (ctaLabel.trim().isEmpty == ctaUrl.trim().isEmpty);

  Map<String, Object> toMap() => {
    'kind': kind.value,
    'title': title.trim(),
    'caption': caption.trim(),
    'audience': audience.value,
    'imageUrls': imageUrls,
    'ctaLabel': ctaLabel.trim(),
    'ctaUrl': ctaUrl.trim(),
  };
}
