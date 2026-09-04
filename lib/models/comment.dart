import 'package:flutter/foundation.dart';

import 'formatting.dart';

/// A comment on a post.
///
/// One level of nesting, matching the forum threads: a reply carries [parentId]
/// and renders indented, and a reply to a reply is flattened onto that same
/// level rather than growing a tree nobody can read on a phone.
@immutable
class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.createdAt,
    required this.text,
    this.parentId,
    this.likeCount = 0,
    this.likedByMe = false,
  });

  final String id;
  final String postId;
  final String authorId;
  final DateTime createdAt;
  final String text;

  /// Null for a top-level comment.
  final String? parentId;

  final int likeCount;
  final bool likedByMe;

  int get depth => parentId == null ? 0 : 1;

  String get age => Fmt.relative(createdAt);

  Comment copyWith({int? likeCount, bool? likedByMe}) => Comment(
    id: id,
    postId: postId,
    authorId: authorId,
    createdAt: createdAt,
    text: text,
    parentId: parentId,
    likeCount: likeCount ?? this.likeCount,
    likedByMe: likedByMe ?? this.likedByMe,
  );
}
