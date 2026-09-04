import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/fixtures/fixture_data.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';

/// One room, everyone in it.
///
/// The grip at the very top pulls down to Forums — the same gesture as the
/// prototype's, wired to an overscroll rather than a tap alone.
class ChatroomScreen extends StatefulWidget {
  const ChatroomScreen({super.key});

  @override
  State<ChatroomScreen> createState() => _ChatroomScreenState();
}

class _ChatroomScreenState extends State<ChatroomScreen> {
  final _messages = List<ChatMessage>.of(Fx.chatroom);
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

  void _send(String text) {
    setState(() {
      _messages.add(
        ChatMessage(
          authorId: Fx.meId,
          createdAt: DateTime.now(),
          text: text,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return LbmScreen(
      bottom: Composer(hintText: 'Message the room…', onSend: _send),
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
                    style: LbmText.display.copyWith(
                      fontSize: 20,
                      color: c.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '· 1,284 here now',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LbmText.xtiny.copyWith(color: c.ink2),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onOverscroll,
              child: ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: _messages.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (context, i) =>
                    _ChatBubble(message: _messages[i]),
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

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final author = Fx.person(message.authorId);
    // Whether a message is yours is a fact about the viewer, not the message.
    final mine = message.authorId == Fx.meId;

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
      child: HashtagText(
        message.text,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.5,
          color: mine ? c.accentInk : c.ink,
        ),
      ),
    );

    return Row(
      textDirection: mine ? TextDirection.rtl : TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Avatar(
          author,
          size: AvatarSize.sm,
          onTap: mine ? null : () => context.goToSeller(author.id),
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: c.ink2,
                      ),
                      children: [
                        TextSpan(text: '${author.name} '),
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
              bubble,
            ],
          ),
        ),
      ],
    );
  }
}
