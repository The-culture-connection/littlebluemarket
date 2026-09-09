import 'package:flutter/foundation.dart';

import 'formatting.dart';

/// Why someone is being reported.
enum ReportReason {
  spam('spam', 'Spam or scam'),
  harassment('harassment', 'Harassment or hate'),
  inappropriate('inappropriate', 'Inappropriate content'),
  fake('fake', 'Fake shop or counterfeit'),
  other('other', 'Something else');

  const ReportReason(this.value, this.label);

  final String value;
  final String label;

  static ReportReason fromValue(String? value) => values.firstWhere(
    (r) => r.value == value,
    orElse: () => ReportReason.other,
  );
}

/// What was reported: a person, or one of their posts.
enum ReportKind {
  user('user'),
  post('post');

  const ReportKind(this.value);

  final String value;

  static ReportKind fromValue(String? value) =>
      value == 'post' ? ReportKind.post : ReportKind.user;
}

/// Where a report stands with the merchant.
enum ReportStatus {
  open('open', 'Open'),
  resolved('resolved', 'Resolved'),
  banned('banned', 'Banned');

  const ReportStatus(this.value, this.label);

  final String value;
  final String label;

  static ReportStatus fromValue(String? value) => values.firstWhere(
    (s) => s.value == value,
    orElse: () => ReportStatus.open,
  );
}

/// A report a member made about another member. Read only by admins.
@immutable
class Report {
  const Report({
    required this.id,
    required this.reporterUid,
    required this.reporterName,
    required this.subjectUid,
    required this.subjectName,
    required this.subjectHandle,
    required this.kind,
    required this.reason,
    required this.text,
    required this.createdAt,
    required this.status,
    this.postId,
    this.subjectBanned = false,
  });

  final String id;
  final String reporterUid;
  final String reporterName;

  /// The person reported; for a post report, its author.
  final String subjectUid;
  final String subjectName;
  final String subjectHandle;
  final ReportKind kind;
  final ReportReason reason;
  final String text;
  final DateTime createdAt;
  final ReportStatus status;

  /// The post, when a post was reported.
  final String? postId;

  /// Whether the subject has since been banned (set by the ban itself on
  /// every report about them).
  final bool subjectBanned;

  String get age => Fmt.relative(createdAt);
  bool get isOpen => status == ReportStatus.open;
}

/// What the report sheet sends.
@immutable
class NewReport {
  const NewReport({
    required this.subjectUid,
    required this.subjectName,
    required this.subjectHandle,
    required this.kind,
    required this.reason,
    required this.text,
    this.postId,
    this.reporterName = '',
  });

  static const textMax = 1000;

  final String subjectUid;
  final String subjectName;
  final String subjectHandle;
  final ReportKind kind;
  final ReportReason reason;
  final String text;
  final String? postId;
  final String reporterName;

  /// A reason is enough; words are required only for "Something else".
  bool get isValid =>
      subjectUid.isNotEmpty &&
      text.trim().length <= textMax &&
      (reason != ReportReason.other || text.trim().isNotEmpty);
}
