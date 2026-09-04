import 'package:flutter/foundation.dart';

import 'models.dart';

/// What kind of thing a feed entry is.
///
/// The prototype's feed was a list of product ids, so a listing was the only
/// thing that could appear in it. The product needs three: a seller posting a
/// listing, a buyer reviewing something they bought, and anyone shouting out a
/// seller. They share the like/comment/tag machinery and differ in their body.
enum PostKind { listing, review, shoutout }

/// A feed entry.
///
/// Sealed on purpose: `switch` over a post is exhaustive, so adding a fourth
/// kind later is a compile error at every render site rather than a silently
/// blank card.
@immutable
sealed class Post {
  const Post({
    required this.id,
    required this.authorId,
    required this.createdAt,
    required this.tags,
    required this.likeCount,
    required this.commentCount,
    required this.likedByMe,
  });

  final String id;
  final String authorId;
  final DateTime createdAt;
  final List<String> tags;
  final int likeCount;
  final int commentCount;

  /// Resolved per viewer, from the `likes/{uid}` subcollection.
  final bool likedByMe;

  PostKind get kind;

  String get age => Fmt.relative(createdAt);

  /// The listing a post is about, when there is one. A shoutout has none.
  String? get subjectProductId;
}

/// A seller putting a good or a service in front of people.
@immutable
final class ListingPost extends Post {
  const ListingPost({
    required super.id,
    required super.authorId,
    required super.createdAt,
    required super.tags,
    required super.likeCount,
    required super.commentCount,
    required super.likedByMe,
    required this.product,
    this.caption,
  });

  final Product product;

  /// What the seller wrote. Falls back to the listing's own description.
  final String? caption;

  @override
  PostKind get kind => PostKind.listing;

  @override
  String? get subjectProductId => product.id;

  String get body => caption ?? '${product.title} — ${product.shortDescription}.';
}

/// A buyer reviewing something they actually bought.
///
/// Carries [purchaseId] because a review is only offered for a line the order
/// pipeline recorded — that is what keeps reviews attached to real purchases.
@immutable
final class ReviewPost extends Post {
  const ReviewPost({
    required super.id,
    required super.authorId,
    required super.createdAt,
    required super.tags,
    required super.likeCount,
    required super.commentCount,
    required super.likedByMe,
    required this.productId,
    required this.rating,
    required this.text,
    this.purchaseId,
    this.imageUrls = const [],
  });

  final String productId;
  final int rating;
  final String text;
  final String? purchaseId;
  final List<String> imageUrls;

  @override
  PostKind get kind => PostKind.review;

  @override
  String? get subjectProductId => productId;
}

/// Someone naming a seller they want other people to find.
@immutable
final class ShoutoutPost extends Post {
  const ShoutoutPost({
    required super.id,
    required super.authorId,
    required super.createdAt,
    required super.tags,
    required super.likeCount,
    required super.commentCount,
    required super.likedByMe,
    required this.text,
    this.aboutSellerId,
    this.imageUrls = const [],
  });

  final String text;

  /// The @-mentioned seller, when the mention resolved to a real profile.
  final String? aboutSellerId;
  final List<String> imageUrls;

  @override
  PostKind get kind => PostKind.shoutout;

  @override
  String? get subjectProductId => null;
}

/// What the composer hands to the repository. Not a [Post] — it has no id, no
/// counts, and no author until the write happens.
@immutable
class NewPost {
  const NewPost.listing({
    required this.productId,
    this.caption,
    this.tags = const [],
  }) : kind = PostKind.listing,
       text = null,
       rating = null,
       purchaseId = null,
       aboutSellerId = null,
       imageUrls = const [];

  const NewPost.review({
    required this.productId,
    required this.rating,
    required this.text,
    this.purchaseId,
    this.tags = const [],
    this.imageUrls = const [],
  }) : kind = PostKind.review,
       caption = null,
       aboutSellerId = null;

  const NewPost.shoutout({
    required this.text,
    this.aboutSellerId,
    this.tags = const [],
    this.imageUrls = const [],
  }) : kind = PostKind.shoutout,
       productId = null,
       caption = null,
       rating = null,
       purchaseId = null;

  final PostKind kind;
  final String? productId;
  final String? caption;
  final String? text;
  final int? rating;
  final String? purchaseId;
  final String? aboutSellerId;
  final List<String> tags;
  final List<String> imageUrls;
}
