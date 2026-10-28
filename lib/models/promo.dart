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

/// A screen in the app an advert's button can open, written `app:<value>`
/// in its link.
///
/// Grace, 2026-10-28: "Get the advertisement button to go to different
/// places in the app specifically the search screen". The button could
/// already open a shop (`@handle`) or a hashtag (`#tag`); these are the
/// places that have no name of their own to type.
enum PromoScreen {
  search('search', 'Search'),
  home('home', 'Home feed'),
  market('market', 'Market'),
  directory('directory', 'Directory'),
  community('community', 'Community chat'),
  forums('forums', 'Forums'),
  cart('cart', 'Check out'),
  donate('donate', 'Chip in');

  const PromoScreen(this.value, this.label);

  /// What follows `app:` in the link.
  final String value;
  final String label;

  static const prefix = 'app:';

  /// The screen an `app:<value>` link names, or null for anything else.
  static PromoScreen? fromLink(String link) {
    final raw = link.trim().toLowerCase();
    if (!raw.startsWith(prefix)) return null;
    final value = raw.substring(prefix.length);
    return values.where((s) => s.value == value).firstOrNull;
  }
}

/// The brand colours an advert's button can be (Grace, 2026-10-28: "Make
/// button color changeable"). Names rather than numbers, so the admin
/// website, the backend and the phone agree without sharing a hex table,
/// and so nothing outside the brand guide can be chosen.
enum PromoButtonColor {
  navy('navy', 'Navy'),
  blue('blue', 'Blue'),
  sky('sky', 'Sky'),
  orchid('orchid', 'Orchid'),
  gold('gold', 'Gold'),
  cream('cream', 'Cream'),
  white('white', 'White');

  const PromoButtonColor(this.value, this.label);

  final String value;
  final String label;

  /// Null for empty or unknown, which means the usual button.
  static PromoButtonColor? fromValue(String? value) =>
      values.where((c) => c.value == value?.trim().toLowerCase()).firstOrNull;
}

/// A colour code for a button, as 0xRRGGBB, or null when [raw] is not one.
///
/// Grace, 2026-10-28 (QA suite): "I would like to be able to put hex numbers
/// to change the color of advert buttons". Six digits, with or without the
/// '#', or the three-digit shorthand. The brand names still work; this is
/// for anything else.
int? promoButtonHex(String raw) {
  final m = RegExp(
    r'^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$',
  ).firstMatch(raw.trim());
  if (m == null) return null;
  var digits = m.group(1)!;
  if (digits.length == 3) digits = digits.split('').map((d) => '$d$d').join();
  return int.parse(digits, radix: 16);
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
    this.mentions = const {},
    this.ctaColor = '',
  });

  /// The button's colour: a brand colour's name, a colour code like
  /// `#1A7F5A`, or empty for the usual button.
  final String ctaColor;

  /// The `@handles` the copy names, lowercased, each with the uid it meant
  /// when it was written. See [MentionedProfiles].
  final Map<String, String> mentions;

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

  bool get hasCta =>
      ctaLabel.trim().isNotEmpty &&
      (ctaProfileUid != null ||
          ctaTag != null ||
          ctaScreen != null ||
          ctaUri != null);

  /// Anything with a photograph is the photograph and its button, nothing
  /// else: no title, no caption, no "From Little Blue Cart" (Grace,
  /// 2026-10-28: "Change advertisements to only show photo banner and no
  /// caption", and from the QA suite the same day, about an announcement
  /// with a photo: "it should only show the advertisement image and the
  /// button"). One without a photograph still needs its words, or there
  /// would be nothing on the card at all. An announcement's words still go
  /// to the bell and the push.
  bool get photoOnly => hasPhoto;

  /// The screen in the app the button opens, or null.
  PromoScreen? get ctaScreen => PromoScreen.fromLink(ctaUrl);

  /// The uid of the profile the button opens, or null.
  ///
  /// Grace, 2026-09-24: "can we also add cta links for things within the
  /// app? I would like to add it to be a search of a hashtag or a person's
  /// profile." The button used to have one destination, a web page, so an
  /// advert about a shop on this market sent people out to a browser to
  /// find something three taps away.
  ///
  /// The uid rather than the handle, from the same [mentions] map the copy
  /// uses: an advert outlives the handle it was written with, and a shop
  /// that renames itself in March should still be the shop the button opens
  /// in September.
  String? get ctaProfileUid {
    final raw = ctaUrl.trim();
    if (!raw.startsWith('@')) return null;
    final uid = mentions[raw.substring(1).toLowerCase()];
    return uid == null || uid.isEmpty ? null : uid;
  }

  /// The hashtag the button searches for, with its '#', or null.
  String? get ctaTag {
    final raw = ctaUrl.trim();
    return raw.startsWith('#') && raw.length > 1 ? raw : null;
  }

  /// The button's destination on the web, or null when it goes somewhere in
  /// the app or is not a usable address. A link typed without a scheme still
  /// works, the way the directory card already treats a business's website.
  Uri? get ctaUri {
    final raw = ctaUrl.trim();
    if (raw.isEmpty ||
        raw.startsWith('@') ||
        raw.startsWith('#') ||
        raw.toLowerCase().startsWith(PromoScreen.prefix)) {
      return null;
    }
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

  String get age => createdAt == null ? '' : Fmt.relative(createdAt!);
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
    this.ctaColor = '',
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
  final String ctaColor;

  bool get isValid =>
      title.trim().isNotEmpty &&
      title.trim().length <= titleMax &&
      // An advert with a photograph shows only the photograph, so its
      // caption is optional; everything else still needs one.
      (caption.trim().isNotEmpty ||
          (kind == PromoKind.ad && imageUrls.isNotEmpty)) &&
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
    'ctaColor': ctaColor.trim(),
  };
}
