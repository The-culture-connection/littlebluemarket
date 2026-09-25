import 'package:flutter/foundation.dart';

import 'models.dart';

/// One tile in the grid.
///
/// [Post] is already sealed, but the feed is no longer a list of posts: a
/// forum thread, the open chatroom, an announcement and a prompt to review
/// something all appear in the same two columns. Rather than widen [Post] to
/// hold things nobody ever wrote as a post, the feed gets its own union and
/// carries posts inside it.
///
/// Sealed for the same reason [Post] is: the `switch` that turns an item into
/// a pin is exhaustive, so a new kind is a compile error at the render site
/// instead of a hole in the grid.
@immutable
sealed class FeedItem {
  const FeedItem();

  /// Stable across a re-assembly of the feed, so scroll position and widget
  /// state survive a refresh. Unique within one assembled page.
  String get key;

  /// Full width, breaking the two columns. See `LbmMasonry`.
  bool get isWide => false;
}

/// A seller's listing. The photograph is the card.
final class ProductItem extends FeedItem {
  const ProductItem(this.post, {this.proof = false});

  final ListingPost post;

  /// Enough people have carted it to be worth saying so on the pin.
  final bool proof;

  Product get product => post.product;

  @override
  String get key => 'product:${post.id}';
}

/// Somebody's review of something they bought.
final class ReviewItem extends FeedItem {
  const ReviewItem(this.post);

  final ReviewPost post;

  @override
  String get key => 'review:${post.id}';
}

/// A posted cart: a frozen snapshot of what somebody was buying.
final class CartItem extends FeedItem {
  const CartItem(this.post);

  final CartPost post;

  @override
  String get key => 'cart:${post.id}';
}

/// Someone naming a maker they want other people to find.
final class ShoutoutItem extends FeedItem {
  const ShoutoutItem(this.post);

  final ShoutoutPost post;

  @override
  String get key => 'shoutout:${post.id}';
}

/// A littlebluecart.com business announcing itself.
final class DirectoryItem extends FeedItem {
  const DirectoryItem(this.post);

  final DirectoryPost post;

  @override
  String get key => 'directory:${post.id}';
}

/// A forum question, with whoever is in it.
final class ThreadItem extends FeedItem {
  const ThreadItem(
    this.thread, {
    this.forumName,
    this.topReply,
    this.repliers = const [],
    this.joined = false,
  });

  final ForumThread thread;

  /// The forum's name for the kicker. Null when it has not been resolved,
  /// in which case the pin says "Forum" rather than guessing.
  final String? forumName;

  /// The reply worth showing under the question, if there is one.
  final ThreadComment? topReply;

  /// Faces of the people in the thread, for the "who is here" row.
  final List<Person> repliers;

  /// Whether the viewer is a member of the forum this thread is in.
  final bool joined;

  @override
  String get key => 'thread:${thread.id}';
}

/// The open chatroom, as it stands right now.
final class ChatItem extends FeedItem {
  const ChatItem(this.moment);

  final ChatMoment moment;

  @override
  String get key => 'chat';
}

/// News from Little Blue Market.
final class AnnouncementItem extends FeedItem {
  const AnnouncementItem(this.announcement, {this.promo, this.hero = false});

  final Announcement announcement;

  /// The live promo, when there is one, purely for its photograph.
  final Promo? promo;

  /// The newest one the person has not seen yet, drawn full width at the top
  /// of the feed. Everything after it is the compact version.
  final bool hero;

  @override
  String get key => 'announcement:${announcement.id}';

  @override
  bool get isWide => hero;
}

/// What a nudge is asking for.
enum NudgeKind {
  /// Something arrived and has not been reviewed.
  reviewDelivered,

  /// A brand new member who has not said anything yet.
  sayHi,

  /// A forum the person joined has moved on without them.
  forumActivity,
}

/// A small prompt to do the one thing that would make the app better for
/// this person right now.
///
/// Dismissible, and a dismissed nudge stays gone for a week. At most one per
/// eight items: a grid full of the app asking for things is not a feed.
final class NudgeItem extends FeedItem {
  const NudgeItem(this.nudge, {this.id = '', this.payload});

  final NudgeKind nudge;

  /// What the nudge is about — the purchase, the forum — so that dismissing
  /// one review prompt does not dismiss every future one.
  final String id;

  final Object? payload;

  @override
  String get key => 'nudge:${nudge.name}:$id';

  /// The key a dismissal is remembered under. Mirrors the plan's
  /// `nudge_dismissed_<kind>_<id>`.
  String get dismissKey => 'nudge_dismissed_${nudge.name}_$id';
}

/// A sideways rail of makers, full width.
final class MakersRailItem extends FeedItem {
  const MakersRailItem(this.sellers);

  final List<Person> sellers;

  @override
  String get key => 'makers';

  @override
  bool get isWide => true;
}
