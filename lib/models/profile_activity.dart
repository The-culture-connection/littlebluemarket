import 'package:flutter/foundation.dart';

import 'formatting.dart';

/// Where a comment was left, so a row on a profile can say so.
enum CommentPlace { thread, post }

/// One thing somebody said, somewhere, for their own profile.
///
/// Its own model rather than [ThreadComment] because the thing that makes a
/// comment worth showing on a profile is the thing [ThreadComment] does not
/// carry: where it was. "In Pricing Your Work" is the row; the words alone
/// are a fragment.
@immutable
class ProfileComment {
  const ProfileComment({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.place,
    required this.parentId,
    this.parentTitle = '',
  });

  final String id;
  final String text;
  final DateTime createdAt;

  /// A forum thread or a feed post.
  final CommentPlace place;

  /// The thread or post it belongs to, which is where tapping it goes.
  final String parentId;

  /// Resolved when the parent could be read; empty when it could not, and
  /// the row then says the plainer thing rather than an empty quotation.
  final String parentTitle;

  String get age => Fmt.relative(createdAt);

  /// "in Pricing Your Work", "on a post". Never a blank where a title
  /// should be: a deleted thread leaves a comment that still happened.
  String get where => switch (place) {
    CommentPlace.thread =>
      parentTitle.isEmpty ? 'in a thread' : 'in $parentTitle',
    CommentPlace.post => parentTitle.isEmpty ? 'on a post' : 'on $parentTitle',
  };
}

/// Which sections of a profile its owner lets other people see.
///
/// Stored on the person, written only by them. Everything is on by default:
/// this is a market where people are trying to be found, and a profile that
/// starts hidden is a worse first experience than one somebody chooses to
/// quieten.
@immutable
class ProfileSections {
  const ProfileSections({
    this.bought = true,
    this.reviews = true,
    this.posts = true,
    this.carts = true,
    this.threads = true,
    this.comments = true,
  });

  final bool bought;
  final bool reviews;
  final bool posts;
  final bool carts;
  final bool threads;
  final bool comments;

  bool enabled(String section) => switch (section) {
    'bought' => bought,
    'review' => reviews,
    'post' => posts,
    'cart' => carts,
    'thread' => threads,
    'comment' => comments,
    _ => true,
  };

  ProfileSections copyWith({
    bool? bought,
    bool? reviews,
    bool? posts,
    bool? carts,
    bool? threads,
    bool? comments,
  }) => ProfileSections(
    bought: bought ?? this.bought,
    reviews: reviews ?? this.reviews,
    posts: posts ?? this.posts,
    carts: carts ?? this.carts,
    threads: threads ?? this.threads,
    comments: comments ?? this.comments,
  );

  Map<String, dynamic> toMap() => {
    'bought': bought,
    'reviews': reviews,
    'posts': posts,
    'carts': carts,
    'threads': threads,
    'comments': comments,
  };

  static ProfileSections fromMap(Object? raw) {
    if (raw is! Map) return const ProfileSections();
    bool on(String key) => raw[key] is bool ? raw[key] as bool : true;
    return ProfileSections(
      bought: on('bought'),
      reviews: on('reviews'),
      posts: on('posts'),
      carts: on('carts'),
      threads: on('threads'),
      comments: on('comments'),
    );
  }
}
