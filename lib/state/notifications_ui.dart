import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/feed_item.dart' show NudgeKind;
import '../models/models.dart';
import '../router/app_router.dart';
import 'providers.dart';
import 'session.dart';

/// Something that happened, as far as what the screen should do about it.
///
/// Not the backend's push type: a DM and an open-chat message never push,
/// and the person's own actions are not notifications at all, but all three
/// still decide what appears where.
enum UiEvent {
  /// News from Little Blue Market. Its popup-once, hero and bell path is the
  /// existing one; the only rule added here is that it is never a toast.
  announcement,

  /// A seller's advert. The feed's banner, labelled, and nothing else.
  promo,

  /// A direct message.
  dm,
  mention,

  /// A comment on your post, or a review of your product: somebody talking
  /// to you about something of yours.
  comment,

  /// A reply in a forum thread you are in.
  forumReply,

  /// A message in the open chatroom.
  chat,

  /// A post under a hashtag you asked to be told about.
  tagPost,

  /// Something new from a maker you follow.
  drop,

  /// Something you bought arrived.
  delivered,

  /// Something you just did: carted, reposted, reviewed, followed.
  ownAction,
}

/// Every place an event can show up.
enum Surface {
  /// The one toast slot at the top.
  toast,

  /// The DM banner: face, name, the message, and Reply.
  banner,

  /// The bell swings.
  bellRing,

  /// The bell's unread dot.
  bellBadge,

  /// The feed's banner at the top (announcements, and promos labelled so).
  heroPin,

  /// "N new" on the thread's pin.
  threadPill,

  /// The chat pin gains the message, live.
  chatPin,

  /// "N new ↓" above the composer, for somebody already in the room.
  chatPill,

  /// A new pin grows in at the top of the feed.
  dropPin,

  /// The review prompt grows in.
  nudgePin,

  communityDot,

  /// The mail count on the You tab.
  youMail,
  youDot,

  /// Held for the "N waiting" strip on the next open, because it arrived in
  /// quiet hours.
  quietQueue,
}

/// What [decide] needs to know about right now.
@immutable
class DecideContext {
  const DecideContext({
    this.viewingSubject = false,
    this.quiet = false,
    this.chatUnseen = 0,
    this.inChatroom = false,
  });

  /// The person is already looking at the thread or conversation the event
  /// belongs to, so telling them about it would be telling them what is in
  /// front of them.
  final bool viewingSubject;

  /// Inside the person's quiet hours.
  final bool quiet;

  /// Open-chat messages since they last looked, this one included.
  final int chatUnseen;

  /// They are in the chatroom.
  final bool inChatroom;
}

/// How many unseen chat messages before Community gets a dot. The room is
/// ambient: one message is not news, a conversation is.
const chatDotAfter = 5;

/// The matrix from the mockup's panel: for this event, right now, which
/// surfaces show it. Pure, so every row can be checked.
///
/// The Following-tab dot the mockup draws for a tag post is not here: the
/// Following tab was taken out of the feed (Grace, 2026-09-25), so there is
/// nothing for it to sit on.
Set<Surface> decide(UiEvent event, DecideContext ctx) {
  final out = switch (event) {
    UiEvent.announcement => {
      Surface.bellRing,
      Surface.bellBadge,
      Surface.heroPin,
    },
    UiEvent.promo => {Surface.heroPin},
    UiEvent.dm => {Surface.banner, Surface.youMail},
    UiEvent.mention ||
    UiEvent.comment => {Surface.toast, Surface.bellRing, Surface.bellBadge},
    UiEvent.forumReply => {
      Surface.bellBadge,
      Surface.threadPill,
      Surface.communityDot,
    },
    UiEvent.chat => {
      Surface.chatPin,
      if (ctx.inChatroom) Surface.chatPill,
      if (!ctx.inChatroom && ctx.chatUnseen >= chatDotAfter)
        Surface.communityDot,
    },
    UiEvent.tagPost => {Surface.toast, Surface.bellRing, Surface.bellBadge},
    UiEvent.drop => {Surface.bellRing, Surface.bellBadge, Surface.dropPin},
    UiEvent.delivered => {
      Surface.bellRing,
      Surface.bellBadge,
      Surface.nudgePin,
      Surface.youDot,
    },
    UiEvent.ownAction => {Surface.toast},
  };

  // Already looking at it: no interruption, the screen is the notification.
  if (ctx.viewingSubject) {
    out
      ..remove(Surface.toast)
      ..remove(Surface.banner);
  }

  // Quiet hours hold back interruptions, except a person talking to you
  // directly (a DM, a mention) and your own actions, which are not
  // notifications. The same line the backend draws for pushes at night.
  final interrupts =
      out.contains(Surface.toast) || out.contains(Surface.banner);
  final allowedAtNight =
      event == UiEvent.dm ||
      event == UiEvent.mention ||
      event == UiEvent.ownAction;
  if (ctx.quiet && interrupts && !allowedAtNight) {
    out
      ..remove(Surface.toast)
      ..remove(Surface.banner)
      ..add(Surface.quietQueue);
  }
  return out;
}

/// Whether [now] falls inside quiet hours running from [start] to [end]
/// (minutes after midnight). The default window, 22:00 to 08:00, crosses
/// midnight, which is the case worth getting right.
bool isQuietAt(DateTime now, {int start = 22 * 60, int end = 8 * 60}) {
  final minute = now.hour * 60 + now.minute;
  if (start == end) return false;
  return start < end
      ? minute >= start && minute < end
      : minute >= start || minute < end;
}

/// One thing for the toast slot.
@immutable
class UiToast {
  const UiToast({
    required this.id,
    required this.event,
    required this.title,
    this.kicker,
    this.subtitle,
    this.route,
    this.personId,
    this.actionLabel = 'Open',
  });

  /// Increases with every toast, so showing the same words twice is still
  /// two toasts.
  final int id;
  final UiEvent event;
  final String title;

  /// The small caps line above the title: "MENTION", "NEW UNDER #HANDMADE".
  final String? kicker;
  final String? subtitle;

  /// Where tapping it goes.
  final String? route;

  /// Whose face goes on a DM banner.
  final String? personId;
  final String actionLabel;

  bool get isBanner => event == UiEvent.dm;
}

/// Everything the choreography is showing, or holding to show.
@immutable
class NotificationsUiState {
  const NotificationsUiState({
    this.toast,
    this.bellRingPending = false,
    this.communityDot = false,
    this.youDot = false,
    this.chatUnseen = 0,
    this.chatPillCount = 0,
    this.threadNew = const {},
    this.pendingWhileQuiet = 0,
    this.quietStrip,
    this.fresh = const {},
  });

  /// The one toast slot. A newer one replaces it.
  final UiToast? toast;

  /// The bell should swing the next time it is on screen.
  final bool bellRingPending;
  final bool communityDot;

  /// Something arrived for the You tab (a delivery).
  final bool youDot;

  /// Open-chat messages since the person last looked.
  final int chatUnseen;

  /// New messages below where somebody in the room has scrolled to.
  final int chatPillCount;

  /// Thread id to replies since the person last opened it.
  final Map<String, int> threadNew;

  /// Interruptions held back in quiet hours.
  final int pendingWhileQuiet;

  /// "🌙 N waiting", once, on the next open after quiet hours held some.
  final String? quietStrip;

  /// Feed keys that arrived while the feed was up, which grow in.
  final Set<String> fresh;

  NotificationsUiState copyWith({
    UiToast? toast,
    bool clearToast = false,
    bool? bellRingPending,
    bool? communityDot,
    bool? youDot,
    int? chatUnseen,
    int? chatPillCount,
    Map<String, int>? threadNew,
    int? pendingWhileQuiet,
    String? quietStrip,
    bool clearQuietStrip = false,
    Set<String>? fresh,
  }) => NotificationsUiState(
    toast: clearToast ? null : toast ?? this.toast,
    bellRingPending: bellRingPending ?? this.bellRingPending,
    communityDot: communityDot ?? this.communityDot,
    youDot: youDot ?? this.youDot,
    chatUnseen: chatUnseen ?? this.chatUnseen,
    chatPillCount: chatPillCount ?? this.chatPillCount,
    threadNew: threadNew ?? this.threadNew,
    pendingWhileQuiet: pendingWhileQuiet ?? this.pendingWhileQuiet,
    quietStrip: clearQuietStrip ? null : quietStrip ?? this.quietStrip,
    fresh: fresh ?? this.fresh,
  );
}

/// What the person is looking at, for dedupe and for "in the room".
typedef LocationReader = String Function();

/// The clock, so a test can stand at 10:30 pm.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The quiet-hours window in minutes after midnight, from the person's own
/// settings; 22:00 to 08:00 until they change it.
final quietHoursProvider = Provider<({int start, int end})>((ref) {
  final prefs = ref.watch(notificationPrefsProvider).value;
  return (prefs ?? const NotificationPrefs()).quietMinutes;
});

/// Where the app is, as a path. Read off the router, so it follows pushes as
/// well as tab switches.
final currentPathProvider = Provider<LocationReader>((ref) {
  return () {
    try {
      return ref.read(routerProvider).state.uri.path;
    } on Object {
      return '';
    }
  };
});

final notificationsUiProvider =
    NotifierProvider<NotificationsUi, NotificationsUiState>(
      NotificationsUi.new,
    );

/// The choreography: takes events, asks [decide], and holds the result for
/// the widgets that draw it.
class NotificationsUi extends Notifier<NotificationsUiState> {
  var _toastIds = 0;

  @override
  NotificationsUiState build() => const NotificationsUiState();

  /// [subjects] are the path endings that mean "already looking at it":
  /// `/community/thread/t1`, or for a DM both `/dm/<conversation>` and
  /// `/dm/<person>`, since a conversation opened from a storefront is
  /// addressed by the person.
  DecideContext _context({
    Iterable<String> subjects = const [],
    int chatUnseen = 0,
  }) {
    final path = ref.read(currentPathProvider)();
    final hours = ref.read(quietHoursProvider);
    return DecideContext(
      viewingSubject: subjects.any((s) => s.isNotEmpty && path.endsWith(s)),
      quiet: isQuietAt(
        ref.read(nowProvider)(),
        start: hours.start,
        end: hours.end,
      ),
      chatUnseen: chatUnseen,
      inChatroom: path == '/community',
    );
  }

  /// Handles one event and returns where it went, which the tests read.
  Set<Surface> handle(
    UiEvent event, {
    String title = '',
    String? kicker,
    String? subtitle,
    String? route,
    String? personId,
    String actionLabel = 'Open',
    String? threadId,
    String? feedKey,
    Iterable<String> viewing = const [],
    bool preview = false,
  }) {
    final chatUnseen = event == UiEvent.chat
        ? state.chatUnseen + 1
        : state.chatUnseen;
    final surfaces = decide(
      event,
      // A Diagnostics preview shows the surface whatever the clock says and
      // wherever the phone is: it exists to be looked at.
      preview
          ? DecideContext(chatUnseen: chatUnseen)
          : _context(subjects: [?route, ...viewing], chatUnseen: chatUnseen),
    );

    var next = state;
    if (surfaces.contains(Surface.toast) || surfaces.contains(Surface.banner)) {
      next = next.copyWith(
        toast: UiToast(
          id: ++_toastIds,
          event: event,
          title: title,
          kicker: kicker,
          subtitle: subtitle,
          route: route,
          personId: personId,
          actionLabel: event == UiEvent.dm ? 'Reply' : actionLabel,
        ),
      );
    }
    if (surfaces.contains(Surface.bellRing)) {
      next = next.copyWith(bellRingPending: true);
    }
    if (surfaces.contains(Surface.communityDot)) {
      next = next.copyWith(communityDot: true);
    }
    if (surfaces.contains(Surface.youDot)) next = next.copyWith(youDot: true);
    if (event == UiEvent.chat) {
      next = next.copyWith(
        chatUnseen: surfaces.contains(Surface.chatPill) ? 0 : chatUnseen,
        chatPillCount: surfaces.contains(Surface.chatPill)
            ? next.chatPillCount + 1
            : next.chatPillCount,
      );
    }
    if (surfaces.contains(Surface.threadPill) && threadId != null) {
      next = next.copyWith(
        threadNew: {
          ...next.threadNew,
          threadId: (next.threadNew[threadId] ?? 0) + 1,
        },
      );
    }
    if ((surfaces.contains(Surface.dropPin) ||
            surfaces.contains(Surface.nudgePin)) &&
        feedKey != null) {
      next = next.copyWith(fresh: {...next.fresh, feedKey});
    }
    if (surfaces.contains(Surface.quietQueue)) {
      next = next.copyWith(pendingWhileQuiet: next.pendingWhileQuiet + 1);
    }
    state = next;
    return surfaces;
  }

  /// The toast went away, by time, swipe or tap.
  void toastGone(int id) {
    if (state.toast?.id == id) state = state.copyWith(clearToast: true);
  }

  /// The bell has swung.
  void bellRung() => state = state.copyWith(bellRingPending: false);

  /// The Community tab was opened.
  void seenCommunity() =>
      state = state.copyWith(communityDot: false, chatUnseen: 0);

  /// The You tab was opened.
  void seenYou() => state = state.copyWith(youDot: false);

  /// The thread was opened; its "N new" goes.
  void seenThread(String threadId) {
    if (!state.threadNew.containsKey(threadId)) return;
    state = state.copyWith(threadNew: {...state.threadNew}..remove(threadId));
  }

  /// The room was scrolled back down to the newest message.
  void seenChatBottom() => state = state.copyWith(chatPillCount: 0);

  /// A grown-in pin has finished growing.
  void settled(String feedKey) {
    if (!state.fresh.contains(feedKey)) return;
    state = state.copyWith(fresh: {...state.fresh}..remove(feedKey));
  }

  /// The app came back to the front: say what quiet hours held, once.
  void resumed() {
    final held = state.pendingWhileQuiet;
    if (held == 0) return;
    final now = ref.read(nowProvider)();
    final hours = ref.read(quietHoursProvider);
    // Still the middle of the night: keep holding.
    if (isQuietAt(now, start: hours.start, end: hours.end)) return;
    state = state.copyWith(
      pendingWhileQuiet: 0,
      quietStrip: held == 1 ? '1 notification waiting' : '$held waiting',
    );
  }

  /// Diagnostics: the "N waiting" strip, now, as the next open after quiet
  /// hours would show it.
  void previewQuietStrip(int held) => state = state.copyWith(
    quietStrip: held == 1 ? '1 notification waiting' : '$held waiting',
  );

  /// The strip has been shown.
  void quietStripShown() => state = state.copyWith(clearQuietStrip: true);
}

/// The mail count on the You tab: unread messages across the inbox.
final mailUnreadProvider = Provider<int>((ref) {
  final inbox = ref.watch(inboxProvider).value ?? const <Conversation>[];
  return inbox.fold(0, (sum, c) => sum + c.unread);
});

/// Feeds [NotificationsUi] from the streams the app already has: the bell,
/// the inbox, the chatroom, and deliveries.
///
/// Watched once, from the tab shell. Each stream's first value is the
/// baseline, not news: opening the app must not replay yesterday as a burst
/// of toasts.
final notificationsChoreographyProvider = Provider<void>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || ref.watch(isGuestProvider)) return;
  final ui = ref.read(notificationsUiProvider.notifier);

  Future<String> nameOf(String personId) async {
    if (personId.isEmpty) return 'Someone';
    try {
      final person = await ref.read(personProvider(personId).future);
      return person.name;
    } on Object {
      return 'Someone';
    }
  }

  // ------------------------------------------------------------ the bell
  Set<String>? bellSeen;
  ref.listen<AsyncValue<List<AppNotification>>>(notificationsProvider, (
    _,
    next,
  ) {
    final list = next.value;
    if (list == null) return;
    final seen = bellSeen;
    bellSeen = {for (final n in list) n.id};
    if (seen == null) return;
    final fresh = [
      for (final n in list)
        if (!seen.contains(n.id) && !n.read) n,
    ].reversed;
    for (final n in fresh) {
      unawaited(_fromBell(ui, n, nameOf));
    }
  }, fireImmediately: true);

  // ------------------------------------------------------- announcements
  // Their own stream, not the bell's list. Only the bell's part is added
  // here; the popup-once and the banner are the existing path, untouched.
  Set<String>? announcementsSeen;
  ref.listen<AsyncValue<List<Announcement>>>(announcementsProvider, (_, next) {
    final list = next.value;
    if (list == null) return;
    final seen = announcementsSeen;
    announcementsSeen = {for (final a in list) a.id};
    if (seen == null) return;
    for (final a in list) {
      if (!seen.contains(a.id)) ui.handle(UiEvent.announcement);
    }
  }, fireImmediately: true);

  // ----------------------------------------------------------- the inbox
  Map<String, int>? unreadSeen;
  ref.listen<AsyncValue<List<Conversation>>>(inboxProvider, (_, next) {
    final list = next.value;
    if (list == null) return;
    final seen = unreadSeen;
    unreadSeen = {for (final c in list) c.id: c.unread};
    if (seen == null) return;
    for (final c in list) {
      if (c.unread <= (seen[c.id] ?? 0)) continue;
      final other = c.participantIds.firstWhere(
        (p) => p != uid,
        orElse: () => '',
      );
      unawaited(
        nameOf(other).then(
          (name) => ui.handle(
            UiEvent.dm,
            title: name,
            subtitle: c.preview,
            route: '/you/dm/${c.id}',
            personId: other,
            viewing: ['/dm/${c.id}', if (other.isNotEmpty) '/dm/$other'],
          ),
        ),
      );
    }
  }, fireImmediately: true);

  // -------------------------------------------------------- the chatroom
  String? lastChat;
  ref.listen<AsyncValue<List<Message>>>(chatroomProvider, (_, next) {
    final list = next.value;
    if (list == null || list.isEmpty) return;
    final previous = lastChat;
    lastChat = list.last.id;
    if (previous == null) return;
    final at = list.indexWhere((m) => m.id == previous);
    for (final m in list.skip(at < 0 ? list.length - 1 : at + 1)) {
      if (m.authorId == uid) continue;
      ui.handle(UiEvent.chat);
    }
  }, fireImmediately: true);

  // ---------------------------------------------------------- deliveries
  Set<String>? deliveredSeen;
  ref.listen<AsyncValue<List<Purchase>>>(purchasesProvider, (_, next) {
    final list = next.value;
    if (list == null) return;
    final seen = deliveredSeen;
    deliveredSeen = {
      for (final p in list)
        if (p.delivered) p.id,
    };
    if (seen == null) return;
    for (final p in list) {
      if (!p.delivered || seen.contains(p.id)) continue;
      ui.handle(
        UiEvent.delivered,
        feedKey: 'nudge:${NudgeKind.reviewDelivered.name}:${p.id}',
      );
    }
  }, fireImmediately: true);
});

Future<void> _fromBell(
  NotificationsUi ui,
  AppNotification n,
  Future<String> Function(String) nameOf,
) async {
  final route =
      n.route ?? (n.postId.isEmpty ? null : '/market/post/${n.postId}');
  switch (n.kind) {
    case NotificationKind.mention:
      ui.handle(
        UiEvent.mention,
        kicker: 'Mention',
        title: '${await nameOf(n.fromUid)} mentioned you',
        subtitle: n.text,
        route: route,
      );
    case NotificationKind.comment:
    case NotificationKind.review:
      ui.handle(
        UiEvent.comment,
        kicker: n.kind == NotificationKind.review
            ? 'Your product'
            : 'Your post',
        title:
            '${await nameOf(n.fromUid)} '
            '${n.kind == NotificationKind.review ? 'reviewed it' : 'replied'}',
        subtitle: n.text,
        route: route,
        actionLabel: 'See',
      );
    case NotificationKind.forumReply:
    case NotificationKind.forumThread:
      final thread = RegExp(r'/thread/([^/?]+)').firstMatch(route ?? '');
      ui.handle(UiEvent.forumReply, route: route, threadId: thread?.group(1));
    case NotificationKind.tagPost:
      ui.handle(
        UiEvent.tagPost,
        kicker: n.title ?? 'A tag you follow',
        title: '${await nameOf(n.fromUid)} posted',
        subtitle: n.text,
        route: route,
        actionLabel: 'See',
      );
    case NotificationKind.newPost:
    case NotificationKind.newProduct:
      ui.handle(
        UiEvent.drop,
        route: route,
        feedKey: n.postId.isEmpty ? null : 'product:${n.postId}',
      );
    case NotificationKind.announcement:
      ui.handle(UiEvent.announcement, route: route);
    case NotificationKind.other:
      ui.handle(UiEvent.comment, title: n.text, route: route);
  }
}
