import 'package:flutter/foundation.dart';

import 'formatting.dart';
import 'notification.dart';

/// Who an announcement goes to.
enum AnnouncementAudience {
  all('all', 'Everyone'),
  sellers('sellers', 'Sellers'),
  buyers('buyers', 'Buyers'),
  directory('directory', 'Directory');

  const AnnouncementAudience(this.value, this.label);

  /// The backend's word for it.
  final String value;
  final String label;

  static AnnouncementAudience fromValue(String? value) => values.firstWhere(
    (a) => a.value == value,
    orElse: () => AnnouncementAudience.all,
  );

  /// Whether this viewer is in the audience. Decided on the phone from the
  /// same facts the topics follow.
  bool includes({required bool isSeller, required bool directoryLinked}) =>
      switch (this) {
        AnnouncementAudience.all => true,
        AnnouncementAudience.sellers => isSeller,
        AnnouncementAudience.buyers => !isSeller,
        AnnouncementAudience.directory => directoryLinked,
      };
}

/// News from Little Blue Market. Written only by the backend.
@immutable
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.audience,
    required this.route,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final AnnouncementAudience audience;

  /// Where a tap goes.
  final String route;
  final DateTime createdAt;

  String get age => Fmt.relative(createdAt);

  /// This announcement as a bell row: from Little Blue Market, read when it
  /// is no newer than the account's seen-stamp.
  AppNotification asNotification({DateTime? seenAt}) => AppNotification(
    id: 'announcement_$id',
    kind: NotificationKind.announcement,
    postId: '',
    fromUid: '',
    text: body,
    createdAt: createdAt,
    read: seenAt != null && !createdAt.isAfter(seenAt),
    route: route,
    title: title,
  );
}

/// What the Admin screen sends.
@immutable
class NewAnnouncement {
  const NewAnnouncement({
    required this.title,
    required this.body,
    required this.audience,
    this.route = '',
  });

  static const titleMax = 60;
  static const bodyMax = 180;

  final String title;
  final String body;
  final AnnouncementAudience audience;
  final String route;

  bool get isValid =>
      title.trim().isNotEmpty &&
      title.trim().length <= titleMax &&
      body.trim().isNotEmpty &&
      body.trim().length <= bodyMax;
}
