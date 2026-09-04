import 'package:flutter/foundation.dart';

/// A person — seller, buyer, or both. The prototype's `U`.
///
/// The stat row is remapped from Instagram: Followers becomes [revenue],
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
    required this.revenue,
    required this.purchases,
    required this.posts,
  });

  final String id;
  final String name;

  /// Also the storefront address, which is why signup asks for it first.
  final String handle;

  /// Avatar background, unique per person.
  final int tint;
  final String bio;

  /// Initiative hashtags shown on the storefront.
  final List<String> tags;

  final String revenue;
  final int purchases;
  final int posts;

  /// Up to two initials, for the avatar.
  String get initials => name
      .split(RegExp(r'\s+'))
      .take(2)
      .map((w) => w.isEmpty ? '' : w[0])
      .join()
      .toUpperCase();
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
    required this.location,
    required this.likes,
    required this.commentCount,
    this.photo,
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
  final String location;
  final int likes;
  final int commentCount;

  /// Asset key for a real photograph, when there is one.
  final String? photo;

  /// Line art, for listings without a photograph.
  final ProductGlyph? glyph;

  /// The pastel gradient behind [glyph].
  final int? tileFrom;
  final int? tileTo;

  bool get hasPhoto => photo != null;

  /// "$8", "$450" — whole dollars stay whole, as in the prototype.
  String get price => formatCents(priceCents);

  /// The first sentence of [description], used as the feed caption.
  String get shortDescription {
    final stop = description.indexOf('.');
    return stop == -1 ? description : description.substring(0, stop);
  }
}

/// `$8` for whole dollars, `$13.60` otherwise.
String formatCents(int cents) {
  final dollars = cents ~/ 100;
  final remainder = cents % 100;
  if (remainder == 0) return '\$$dollars';
  return '\$$dollars.${remainder.toString().padLeft(2, '0')}';
}

/// A review. Reviews belong to the **product**, not to the seller — a seller
/// with three products has three independent rating sets. That is what lets a
/// review surface in a hashtag search with a link back to its parent product.
@immutable
class Review {
  const Review({
    required this.authorId,
    required this.rating,
    required this.age,
    required this.text,
    required this.tags,
  });

  final String authorId;
  final int rating;

  /// Relative age as written, e.g. "3d", "1w".
  final String age;
  final String text;
  final List<String> tags;
}

/// One selectable option on a product.
@immutable
class Variant {
  const Variant(this.name, this.price, this.stock, {this.selected = false});

  final String name;
  final String price;

  /// Free text: "22 in stock", "3 left", "Back Oct 4", "Sept 18, 24 open".
  final String stock;
  final bool selected;
}

/// A label/value pair in a spec or shipping table.
@immutable
class SpecRow {
  const SpecRow(this.label, this.value);
  final String label;
  final String value;
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
    required this.histogram,
  });

  final String subtitle;

  /// The line above the price in the buy bar, e.g. "Ships in 1-2 business days".
  final String lead;
  final List<SpecRow> rows;
  final List<Variant> variants;
  final List<SpecRow> shipping;
  final String returns;

  /// Star counts from 5 down to 1.
  final List<({int stars, int count})> histogram;

  int get ratingTotal =>
      histogram.fold(0, (sum, bar) => sum + bar.count).clamp(1, 1 << 30);
}

/// An initiative hashtag with its post count.
///
/// Hashtags are a controlled vocabulary, not free text. They sit on goods,
/// services, reviews and forums alike.
@immutable
class TagCount {
  const TagCount(this.tag, this.count);
  final String tag;
  final String count;
}

@immutable
class Forum {
  const Forum({
    required this.id,
    required this.title,
    required this.description,
    required this.members,
    required this.threadCount,
    required this.tint,
  });

  final String id;
  final String title;
  final String description;
  final String members;
  final int threadCount;
  final int tint;
}

@immutable
class ForumThread {
  const ForumThread({
    required this.id,
    required this.forumId,
    required this.authorId,
    required this.title,
    required this.body,
    required this.upvotes,
    required this.commentCount,
    required this.age,
  });

  final String id;
  final String forumId;
  final String authorId;
  final String title;
  final String body;
  final int upvotes;
  final int commentCount;
  final String age;
}

@immutable
class ThreadComment {
  const ThreadComment({
    required this.authorId,
    required this.upvotes,
    required this.age,
    required this.text,
    required this.depth,
  });

  final String authorId;
  final int upvotes;
  final String age;
  final String text;

  /// One level of nesting only.
  final int depth;
}

/// A message in the single open chatroom.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.authorId,
    required this.time,
    required this.text,
    this.mine = false,
  });

  final String authorId;
  final String time;
  final String text;
  final bool mine;
}

/// A row in the direct-message inbox.
@immutable
class DmSummary {
  const DmSummary({
    required this.personId,
    required this.age,
    required this.preview,
    required this.unread,
  });

  final String personId;
  final String age;
  final String preview;
  final int unread;
}

/// A message in a one-to-one thread.
@immutable
class DmMessage {
  const DmMessage({
    required this.mine,
    required this.time,
    required this.text,
  });

  final bool mine;
  final String time;
  final String text;
}

/// Where a package is. Drives both the badge colour and the progress bar.
enum ShipmentState {
  labelCreated('Label created'),
  inTransit('In transit'),
  outForDelivery('Out for delivery'),
  delivered('Delivered');

  const ShipmentState(this.label);
  final String label;

  bool get isDelivered => this == ShipmentState.delivered;
}

@immutable
class Shipment {
  const Shipment({
    required this.productId,
    required this.party,
    required this.state,
    required this.tracking,
    required this.step,
    required this.note,
  });

  final String productId;

  /// "J. Alvarez · Chicago, IL" when sending, "from Rae Ortiz" when receiving.
  final String party;
  final ShipmentState state;

  /// Displayed with tabular figures so the groups line up.
  final String tracking;

  /// 1-4, filling the four-step bar.
  final int step;
  final String note;
}
