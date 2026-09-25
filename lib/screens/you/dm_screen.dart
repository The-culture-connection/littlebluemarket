import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/message_product_card.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/unclaimed_shop.dart';

/// One conversation.
///
/// Keyed by the conversation, not by a person: two people have exactly one
/// thread, its id derived from the pair, and the inbox already knows it. The
/// prototype keyed this by person and then served the same scripted thread for
/// every contact.
///
/// The `?to=` form is the other entry point — "message this seller" from a
/// storefront, where the conversation may not exist yet.
class DmScreen extends ConsumerStatefulWidget {
  const DmScreen({
    super.key,
    this.conversationId,
    this.personId,
    this.aboutProductId,
  }) : assert(
         conversationId != null || personId != null,
         'a conversation or a person is required',
       );

  final String? conversationId;

  /// Set when arriving from a storefront rather than the inbox.
  final String? personId;

  /// Set when arriving from "Ask" on a product page: the thread opens with
  /// the question written and the listing attached to it.
  final String? aboutProductId;

  @override
  ConsumerState<DmScreen> createState() => _DmScreenState();
}

class _DmScreenState extends ConsumerState<DmScreen> {
  @override
  Widget build(BuildContext context) {
    final direct = widget.conversationId;
    if (direct != null) {
      return _Conversation(
        conversationId: direct,
        aboutProductId: widget.aboutProductId,
      );
    }

    // Arrived from a storefront: find or create the thread first.
    final resolved = ref.watch(conversationIdProvider(widget.personId!));
    return LbmAsync<String>(
      resolved,
      skeleton: const LbmScreen(
        appBar: LbmAppBar(title: 'Message'),
        child: ListRowSkeleton(rows: 3),
      ),
      onRetry: () => ref.invalidate(conversationIdProvider(widget.personId!)),
      errorBuilder: (error, retry) => LbmScreen(
        appBar: const LbmAppBar(title: 'Message'),
        child: LbmErrorCard(error: error, onRetry: retry),
      ),
      data: (id) => _Conversation(
        conversationId: id,
        aboutProductId: widget.aboutProductId,
      ),
    );
  }
}

class _Conversation extends ConsumerStatefulWidget {
  const _Conversation({required this.conversationId, this.aboutProductId});

  final String conversationId;
  final String? aboutProductId;

  @override
  ConsumerState<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends ConsumerState<_Conversation> {
  String get conversationId => widget.conversationId;

  /// Reading a thread clears its badge. Best effort: a failure here is not
  /// worth a card, the badge simply stays until the next open.
  void _markRead() {
    ref
        .read(messagingRepositoryProvider)
        .markRead(conversationId)
        .catchError((_) {});
  }

  @override
  void initState() {
    super.initState();
    // Once on open, on both paths (from the inbox and from a storefront).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _markRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider) ?? '';
    final messages = ref.watch(conversationProvider(conversationId));
    // And again for every message that arrives while the thread is open,
    // otherwise the badge counts messages you have already seen.
    ref.listen(conversationProvider(conversationId), (_, next) {
      final list = next.asData?.value;
      if (list != null && list.isNotEmpty && list.last.authorId != uid) {
        _markRead();
      }
    });
    final otherId = ref
        .watch(inboxProvider)
        .value
        ?.where((c) => c.id == conversationId)
        .firstOrNull
        ?.otherThan(uid);
    final about = widget.aboutProductId == null
        ? null
        : ref.watch(productProvider(widget.aboutProductId!)).value;

    return LbmScreen(
      appBar: LbmAppBar(
        titleWidget: otherId == null
            ? const Text('Message')
            : _HeaderName(personId: otherId),
      ),
      bottom: Composer(
        hintText: 'Message…',
        // The questions makers are asked most, so a buyer does not have to
        // compose one from nothing.
        quickReplies: const [
          'Is this still available?',
          'Do you do pickup?',
          'Could you make one in another colour?',
        ],
        initialText: about == null
            ? ''
            : 'Hi! Is the ${about.title} still available?',
        onSend: (text) => ref
            .read(messagingRepositoryProvider)
            .send(
              conversationId: conversationId,
              text: text,
              attachedProductId: widget.aboutProductId,
            ),
      ),
      child: Column(
        children: [
          // What they came to ask about, before the thread, so the question
          // in the field has something visible attached to it.
          if (widget.aboutProductId case final productId?)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: MessageProductCard(productId: productId),
            ),
          // A shop that is on the market but has nobody reading yet. Said
          // before the first message rather than after it, because that is
          // when it changes what somebody writes (Grace, 2026-09-24).
          if (otherId != null) _UnclaimedNotice(personId: otherId),
          Expanded(
            child: LbmAsync<List<Message>>(
              messages,
              skeleton: const ListRowSkeleton(rows: 4),
              isEmpty: (messages) => messages.isEmpty,
              empty: const LbmEmpty(
                title: 'No messages yet',
                body: 'Ask about stock, sizing, or a pickup.',
              ),
              data: (messages) => ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: messages.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _Bubble(message: messages[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The strip above the thread, when the other side is a shop nobody has
/// claimed. Silent for a person, and silent while the profile is loading.
class _UnclaimedNotice extends ConsumerWidget {
  const _UnclaimedNotice({required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(personProvider(personId)).value;
    if (person == null) return const SizedBox.shrink();
    return UnclaimedShopStrip(person: person);
  }
}

class _HeaderName extends ConsumerWidget {
  const _HeaderName({required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(personProvider(personId));
    return LbmAsync<Person>(
      person,
      skeleton: const LbmSkeleton(width: 120, height: 16),
      errorBuilder: (_, _) => const Text('Message'),
      data: (person) => GestureDetector(
        onTap: () => context.goToSeller(person.id),
        child: Text(person.name),
      ),
    );
  }
}

class _Bubble extends ConsumerWidget {
  const _Bubble({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final mine = message.authorId == ref.watch(currentUidProvider);
    final author = ref.watch(personProvider(message.authorId));

    return Row(
      textDirection: mine ? TextDirection.rtl : TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LbmAsync<Person>(
          author,
          skeleton: const LbmSkeleton(width: 28, height: 28, radius: 14),
          errorBuilder: (_, _) =>
              const LbmSkeleton(width: 28, height: 28, radius: 14),
          data: (person) => Avatar(person, size: AvatarSize.xs),
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.7,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
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
                    // What the message is about, when it is about something.
                    // A question sent from a product page arrives with the
                    // thing attached, so the maker does not have to ask which
                    // one, and the buyer can cart it from the conversation.
                    if (message.attachedProductId case final productId?) ...[
                      MessageProductCard(productId: productId, onDark: mine),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      message.text,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        color: mine ? c.accentInk : c.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                message.hasFailed ? 'Not sent' : message.time,
                style: LbmText.xtiny.copyWith(
                  color: message.hasFailed ? c.clay : c.ink3,
                  fontFeatures: kTabularFigures,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
