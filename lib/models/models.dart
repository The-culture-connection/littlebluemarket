import 'package:flutter/foundation.dart';

import 'formatting.dart';

// Re-exported so a screen can keep importing one models file and get the whole
// domain vocabulary. The types live in their own files because they group into
// genuinely separate concerns; this just spares 30 call sites the churn.
export 'address.dart';
export 'cart.dart';
export 'comment.dart';
export 'formatting.dart';
export 'geo.dart';
export 'message.dart';
export 'order.dart';
export 'page.dart';
export 'post.dart';
export 'search.dart';

/// A person — seller, buyer, or both. The prototype's `U`.
///
/// The stat row is remapped from Instagram: Followers becomes [revenueCents],
/// Following becomes [purchases]. There is no follow relationship anywhere in
/// the product; discovery runs on hashtags and search.
@immutable
class Person {
  const Person({
    required this.id,
    required this.name,
    required this.handle,
    required this.tint,
    required this.bio,
    required this.tags,
    required this.revenueCents,
    required this.purchases,
    required this.posts,
    this.isSeller = true,
    this.avatarUrl,
  });

  final String id;
  final String name;

  /// Also the storefront address, which is why signup asks for it first.
  final String handle;

  /// Avatar background, unique per person. Kept as an `int` so it survives a
  /// round trip through JSON; derived from the uid when a profile has none.
  final int tint;
  final String bio;

  /// Initiative hashtags shown on the storefront.
  final List<String> tags;

  /// Lifetime seller revenue. Maintained by the order pipeline, never by the
  /// client — see the Firestore rules.
  final int revenueCents;
  final int purchases;
  final int posts;

  /// Sellers get the storefront, the revenue stat, and the seller half of Edit
  /// Profile. Buyers get none of it.
  final bool isSeller;

  /// A real photograph, once one is uploaded. Falls back to [initials] on
  /// [tint].
  final String? avatarUrl;

  String get revenueLabel => Fmt.money(revenueCents);

  /// Up to two initials, for the avatar.
  String get initials => name
      .split(RegExp(r'\s+'))
      .take(2)
      .map((w) => w.isEmpty ? '' : w[0])
      .join()
      .toUpperCase();

  Person copyWith({
    String? name,
    String? handle,
    String? bio,
    List<String>? tags,
    int? revenueCents,
    int? purchases,
    int? posts,
    bool? isSeller,
    String? avatarUrl,
  }) => Person(
    id: id,
    name: name ?? this.name,
    handle: handle ?? this.handle,
    tint: tint,
    bio: bio ?? this.bio,
    tags: tags ?? this.tags,
    revenueCents: revenueCents ?? this.revenueCents,
    purchases: purchases ?? this.purchases,
    posts: posts ?? this.posts,
    isSeller: isSeller ?? this.isSeller,
    avatarUrl: avatarUrl ?? this.avatarUrl,
  );
}

/// The illustrated line-art tiles used when a listing has no photograph.
///
/// Service listings genuinely do not have a product shot, so they keep the
/// illustration on purpose.
enum ProductGlyph { jar, bowl, camera, candle, zine, mug }

/// A listing — a good or a service. The prototype's `P`.
@immutable
class Product {
  const Product({
    required this.id,
    required this.title,
    required this.priceCents,
    required this.sellerId,
    required this.tags,
    required this.rating,
    required this.ratingCount,
    required this.type,
    required this.description,
    required this.cityState,
    required this.likes,
    required this.commentCount,
    this.imageUrls = const [],
    this.lat,
    this.lng,
    this.freeShipping = false,
    this.glyph,
    this.tileFrom,
    this.tileTo,
  });

  final String id;
  final String title;
  final int priceCents;
  final String sellerId;
  final List<String> tags;
  final double rating;
  final int ratingCount;

  /// The product-type taxonomy, e.g. "Bath, Beauty & Wellness".
  final String type;
  final String description;

  /// Where the seller ships from, e.g. "Detroit, MI". Distance is *not* baked
  /// in — it depends on who is looking, so it is applied at render time.
  final String cityState;

  /// Set once the listing is geocoded; drives the radius search.
  final double? lat;
  final double? lng;
  final bool freeShipping;

  final int likes;
  final int commentCount;

  /// Photographs, in the order they appear in the detail slideshow. An
  /// `asset://` scheme means a bundled demo image; anything else is a URL.
  final List<String> imageUrls;

  /// Line art, for listings without a photograph.
  final ProductGlyph? glyph;

  /// The pastel gradient behind [glyph].
  final int? tileFrom;
  final int? tileTo;

  bool get hasPhoto => imageUrls.isNotEmpty;

  /// "$8", "$450" — whole dollars stay whole, as in the prototype.
  String get price => Fmt.money(priceCents);

  /// "Detroit, MI · 4 mi" once we know where the viewer is, "Nashville, TN ·
  /// ships free" when the listing ships anywhere, "Detroit, MI" otherwise.
  String locationLabel({double? distanceMiles}) {
    if (distanceMiles != null) {
      return '$cityState · ${Fmt.distanceMiles(distanceMiles)}';
    }
    if (freeShipping) return '$cityState · ships free';
    return cityState;
  }

  /// The first sentence of [description], used as the feed caption.
  String get shortDescription {
    final stop = description.indexOf('.');
    return stop == -1 ? description : description.substring(0, stop);
  }

  Product copyWith({
    int? likes,
    int? commentCount,
    double? rating,
    int? ratingCount,
  }) => Product(
    id: id,
    title: title,
    priceCents: priceCents,
    sellerId: sellerId,
    tags: tags,
    rating: rating ?? this.rating,
    ratingCount: ratingCount ?? this.ratingCount,
    type: type,
    description: description,
    cityState: cityState,
    likes: likes ?? this.likes,
    commentCount: commentCount ?? this.commentCount,
    imageUrls: imageUrls,
    lat: lat,
    lng: lng,
    freeShipping: freeShipping,
    glyph: glyph,
    tileFrom: tileFrom,
    tileTo: tileTo,
  );
}

/// A review. Reviews belong to the **product**, not to the seller — a seller
/// with three products has three independent rating sets. That is what lets a
/// review surface in a hashtag search with a link back to its parent product.
@immutable
class Review {
  const Review({
    required this.authorId,
    required this.rating,
    required this.createdAt,
    required this.text,
    required this.tags,
  });

  final String authorId;
  final int rating;
  final DateTime createdAt;
  final String text;
  final List<String> tags;

  String get age => Fmt.relative(createdAt);
}

/// One selectable option on a product.
///
/// Availability is three fields rather than the prototype's single free-text
/// string, because "22 in stock", "3 left" and "Back Oct 4" are three different
/// states and only the last is genuinely prose.
@immutable
class Variant {
  const Variant(
    this.name,
    this.priceCents, {
    this.availableForSale = true,
    this.quantityAvailable,
    this.availabilityNote,
  });

  final String name;
  final int priceCents;
  final bool availableForSale;
  final int? quantityAvailable;

  /// Free text for the cases a count cannot express: "Back Oct 4", "Sept 18,
  /// 24 open". Services genuinely need this.
  final String? availabilityNote;

  String get price => Fmt.money(priceCents);

  String get stockLabel {
    final note = availabilityNote;
    if (note != null) return note;
    if (!availableForSale) return 'Sold out';
    final quantity = quantityAvailable;
    if (quantity == null) return 'In stock';
    if (quantity <= 6) return '$quantity left';
    return '$quantity in stock';
  }
}

/// A label/value pair in a spec or shipping table.
@immutable
class SpecRow {
  const SpecRow(this.label, this.value);
  final String label;
  final String value;
}

/// How a product's ratings are distributed.
///
/// Split out of [ProductSpec] because it is social data maintained by review
/// writes, not commerce data owned by the storefront.
@immutable
class RatingSummary {
  const RatingSummary({required this.average, required this.bars});

  final double average;

  /// Star counts from 5 down to 1.
  final List<({int stars, int count})> bars;

  int get total => bars.fold(0, (sum, bar) => sum + bar.count);

  bool get isEmpty => total == 0;
}

/// The full record behind a listing. The prototype's `SPECS`.
@immutable
class ProductSpec {
  const ProductSpec({
    required this.subtitle,
    required this.lead,
    required this.rows,
    required this.variants,
    required this.shipping,
    required this.returns,
  });

  final String subtitle;

  /// The line above the price in the buy bar, e.g. "Ships in 1-2 business days".
  final String lead;
  final List<SpecRow> rows;
  final List<Variant> variants;
  final List<SpecRow> shipping;
  final String returns;
}

/// An initiative hashtag with its post count.
///
/// Hashtags are a controlled vocabulary, not free text. They sit on goods,
/// services, reviews and forums alike.
@immutable
class TagCount {
  const TagCount(this.tag, this.postCount);
  final String tag;
  final int postCount;

  String get countLabel => '${Fmt.count(postCount)} posts';
}

@immutable
class Forum {
  const Forum({
    required this.id,
    required this.title,
    required this.description,
    required this.memberCount,
    required this.threadCount,
    required this.tint,
  });

  final String id;
  final String title;
  final String description;
  final int memberCount;
  final int threadCount;
  final int tint;

  String get membersLabel => '${Fmt.count(memberCount)} members';
}

@immutable
class ForumThread {
  const ForumThread({
    required this.id,
    required this.forumId,
    required this.authorId,
    required this.title,
    required this.body,
    required this.commentCount,
    required this.createdAt,
  });

  final String id;
  final String forumId;
  final String authorId;
  final String title;
  final String body;
  final int commentCount;
  final DateTime createdAt;

  String get age => Fmt.relative(createdAt);
}

@immutable
class ThreadComment {
  const ThreadComment({
    required this.authorId,
    required this.createdAt,
    required this.text,
    required this.depth,
  });

  final String authorId;
  final DateTime createdAt;
  final String text;

  /// One level of nesting only.
  final int depth;

  String get age => Fmt.relative(createdAt);
}

/// A message in the single open chatroom.
///
/// There is no `mine` flag: whether a message is yours is a fact about the
/// viewer, not about the message, and baking it in is what tied the prototype
/// to one hardcoded user.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.authorId,
    required this.createdAt,
    required this.text,
  });

  final String authorId;
  final DateTime createdAt;
  final String text;

  String get time => Fmt.clock(createdAt);
}

/// A row in the direct-message inbox.
@immutable
class DmSummary {
  const DmSummary({
    required this.personId,
    required this.lastMessageAt,
    required this.preview,
    required this.unread,
  });

  final String personId;
  final DateTime lastMessageAt;
  final String preview;
  final int unread;

  String get age => Fmt.inboxAge(lastMessageAt);
}

/// A message in a one-to-one thread.
@immutable
class DmMessage {
  const DmMessage({
    required this.authorId,
    required this.createdAt,
    required this.text,
  });

  final String authorId;
  final DateTime createdAt;
  final String text;

  String get time => Fmt.clock(createdAt);
}

/// Where a package is. Drives the badge colour, the progress bar, and the step
/// count — a separate `step` field could disagree with the state.
enum ShipmentState {
  labelCreated('Label created'),
  inTransit('In transit'),
  outForDelivery('Out for delivery'),
  delivered('Delivered');

  const ShipmentState(this.label);
  final String label;

  bool get isDelivered => this == ShipmentState.delivered;

  /// 1-4, filling the four-step bar.
  int get step => index + 1;
}

@immutable
class Shipment {
  const Shipment({
    required this.productId,
    required this.counterpartyName,
    required this.state,
    required this.tracking,
    required this.carrierNote,
  });

  final String productId;

  /// "J. Alvarez · Chicago, IL" when sending, "from Rae Ortiz" when receiving.
  final String counterpartyName;
  final ShipmentState state;

  /// Displayed with tabular figures so the groups line up.
  final String tracking;

  final String carrierNote;

  int get step => state.step;
}

/// A granted vendor claim.
///
/// Carries the vendor name back so the confirmation can say *which* shop was
/// claimed. A wrong name there is the one failure the person can catch and we
/// cannot: the code was issued against a vendor record, and only they know
/// whether it is theirs.
@immutable
class SellerGrant {
  const SellerGrant({required this.vendorName, this.shipturtleVendorId});

  /// The exact Shopify `vendor` string. The join key for every future sale.
  final String vendorName;

  /// Shipturtle's `company_id`, when the roster was reachable.
  final String? shipturtleVendorId;
}
