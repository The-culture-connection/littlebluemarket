import 'package:flutter/foundation.dart';

import 'formatting.dart';

/// What kind of note the bug button sends.
enum FeedbackKind {
  bug('bug', 'Something is broken'),
  idea('idea', 'A critique or an idea');

  const FeedbackKind(this.value, this.label);

  final String value;
  final String label;

  static FeedbackKind fromValue(String? value) => values.firstWhere(
    (k) => k.value == value,
    orElse: () => FeedbackKind.idea,
  );
}

/// Where a note stands with the merchant.
enum FeedbackStatus {
  open('open'),
  done('done');

  const FeedbackStatus(this.value);

  final String value;

  static FeedbackStatus fromValue(String? value) =>
      value == 'done' ? FeedbackStatus.done : FeedbackStatus.open;
}

/// A bug report or critique sent from the floating button, with the
/// screenshot of the screen it was sent from. Read only by admins.
@immutable
class FeedbackItem {
  const FeedbackItem({
    required this.id,
    required this.uid,
    required this.kind,
    required this.text,
    required this.route,
    required this.platform,
    required this.createdAt,
    required this.status,
    this.screenshotUrl,
    this.fromName = '',
    this.isGuest = false,
  });

  final String id;
  final String uid;
  final FeedbackKind kind;
  final String text;

  /// The screen it was sent from, as a route.
  final String route;
  final String platform;
  final DateTime createdAt;
  final FeedbackStatus status;
  final String? screenshotUrl;

  /// The sender's display name at the time, so the admin list reads as
  /// people, not ids. Empty for a guest.
  final String fromName;
  final bool isGuest;

  String get age => Fmt.relative(createdAt);
  bool get isOpen => status == FeedbackStatus.open;
}

/// What the sheet sends.
@immutable
class NewFeedback {
  const NewFeedback({
    required this.kind,
    required this.text,
    required this.route,
    this.includeScreenshot = true,
    this.fromName = '',
    this.isGuest = false,
  });

  static const textMax = 2000;

  final FeedbackKind kind;
  final String text;
  final String route;
  final bool includeScreenshot;

  /// Who is sending, as the app knows them right now.
  final String fromName;
  final bool isGuest;

  bool get isValid =>
      text.trim().isNotEmpty && text.trim().length <= textMax;
}
