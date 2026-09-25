import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/message_product_card.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';

/// The single open chatroom anyone can post into.
class ChatroomScreen extends ConsumerStatefulWidget {
  const ChatroomScreen({super.key});

  @override
  ConsumerState<ChatroomScreen> createState() => _ChatroomScreenState();
}

class _ChatroomScreenState extends ConsumerState<ChatroomScreen> {
  bool _navigating = false;

  void _openForums() {
    if (_navigating) return;
    _navigating = true;
    context.push('/community/forums').then((_) {
      if (mounted) _navigating = false;
    });
  }

  /// Pulling the list past its top opens Forums, the way the grip suggests.
  bool _onOverscroll(ScrollNotification notification) {
    if (notification is OverscrollNotification &&
        notification.overscroll < -18) {
      _openForums();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final messages = ref.watch(chatroomProvider);

    return LbmScreen(
      // A guest reads the room; the rules refuse their writes, so the bar
      // is not shown to them rather than failing on send.
      bottom: ref.watch(isGuestProvider)
          ? null
          : Composer(
              hintText: 'Message the room…',
              // Somebody who has not posted anything yet gets an opener;
              // everybody else gets the two things people actually say.
              quickReplies: (ref.watch(meProvider)?.posts ?? 0) == 0
                  ? const ["Say hi, I'm new here", "Where is everyone based?"]
                  : const ["I'm in", 'Claimed one'],
              // Reaches the repository, so it is there when you come back.
              onSend: (text) =>
                  ref.read(messagingRepositoryProvider).sendToChatroom(text),
            ),
      child: Column(
        children: [
          _PullTab(onTap: _openForums),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    'Open chat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LbmText.display.copyWith(fontSize: 20, color: c.ink),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    // The prototype claimed "1,284 here now", which was
                    // invented. A real presence count needs presence.
                    'Everyone in the market',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LbmText.xtiny.copyWith(color: c.ink2),
                  ),
                ),
              ],
            ),
          ),
          const _PinnedAnnouncement(),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onOverscroll,
              child: LbmAsync<List<Message>>(
                messages,
                skeleton: const ListRowSkeleton(rows: 4),
                isEmpty: (messages) => messages.isEmpty,
                empty: const LbmEmpty(
                  title: 'Quiet in here',
                  body: 'Say the first thing.',
                ),
                data: (messages) => ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: messages.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, i) =>
                      _ChatBubble(message: messages[i]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PullTab extends StatelessWidget {
  const _PullTab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: 'Open Forums',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: c.ink3.withValues(alpha: 0.5),
                  borderRadius: LbmRadius.pillR,
                ),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Pull down for Forums',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: c.skyDeep,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: c.skyDeep,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends ConsumerWidget {
  const _ChatBubble({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final author = ref.watch(personProvider(message.authorId));
    // Whether a message is yours is a fact about the viewer, not the message.
    final mine = message.authorId == ref.watch(currentUidProvider);

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? c.accentDeep : c.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(mine ? 18 : 6),
          topRight: Radius.circular(mine ? 6 : 18),
          bottomLeft: const Radius.circular(18),
          bottomRight: const Radius.circular(18),
        ),
        boxShadow: mine ? null : c.shadowSoft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // A maker dropping something into the room: it draws here and it
          // carts from here, which is the point of the room being next to
          // the market rather than behind it.
          if (message.attachedProductId case final productId?) ...[
            MessageProductCard(productId: productId, onDark: mine),
            const SizedBox(height: 8),
          ],
          HashtagText(
            message.text,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: mine ? c.accentInk : c.ink,
            ),
            onTagTap: (tag) => context.goToTag(tag),
          ),
        ],
      ),
    );

    return Row(
      textDirection: mine ? TextDirection.rtl : TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LbmAsync<Person>(
          author,
          skeleton: const LbmSkeleton(width: 34, height: 34, radius: 17),
          errorBuilder: (_, _) =>
              const LbmSkeleton(width: 34, height: 34, radius: 17),
          data: (person) => Avatar(
            person,
            size: AvatarSize.sm,
            onTap: mine ? null : () => context.goToSeller(person.id),
          ),
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: LbmAsync<Person>(
                    author,
                    skeleton: const LbmSkeleton(width: 110, height: 11),
                    errorBuilder: (_, _) => const SizedBox.shrink(),
                    data: (person) => Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: c.ink2,
                        ),
                        children: [
                          TextSpan(text: '${person.name} '),
                          TextSpan(
                            text: message.time,
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontFeatures: kTabularFigures,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              bubble,
            ],
          ),
        ),
      ],
    );
  }
}

/// The newest announcement, pinned above the room.
///
/// The room scrolls away; a pinned row does not. Anything the market needs
/// everybody to have read belongs where it stays put, and this is the one
/// place in the app where everybody is at once.
class _PinnedAnnouncement extends ConsumerWidget {
  const _PinnedAnnouncement();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final announcements = ref.watch(announcementsProvider).value ?? const [];
    if (announcements.isEmpty) return const SizedBox.shrink();
    final latest = announcements.first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: LbmCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: latest.route.isEmpty ? null : () => context.go(latest.route),
        child: Row(
          children: [
            Icon(Icons.push_pin_outlined, size: 17, color: c.accentText),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    latest.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LbmText.pinTitle.copyWith(
                      fontSize: 13,
                      color: c.ink,
                    ),
                  ),
                  Text(
                    latest.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LbmText.pinMeta.copyWith(color: c.ink2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
