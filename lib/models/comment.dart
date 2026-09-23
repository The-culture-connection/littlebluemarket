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
    this.editedAt,
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

  /// When the author last rewrote it, or null when they never have. Shown,
  /// because a comment that changed after people replied to it should say so.
  final DateTime? editedAt;

  bool get isEdited => editedAt != null;

  int get depth => parentId == null ? 0 : 1;

  String get age => Fmt.relative(createdAt);

  Comment copyWith({
    int? likeCount,
    bool? likedByMe,
    String? text,
    DateTime? editedAt,
  }) => Comment(
    id: id,
    postId: postId,
    authorId: authorId,
    createdAt: createdAt,
    text: text ?? this.text,
    parentId: parentId,
    likeCount: likeCount ?? this.likeCount,
    likedByMe: likedByMe ?? this.likedByMe,
    editedAt: editedAt ?? this.editedAt,
  );
}
