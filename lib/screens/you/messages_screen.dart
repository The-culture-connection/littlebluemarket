import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';

/// The direct-message inbox.
class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final inbox = ref.watch(inboxProvider);

    return LbmScreen(
      appBar: const LbmAppBar(title: 'Messages'),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Text(
              'Buyers and sellers, one thread each.',
              style: LbmText.xtiny.copyWith(color: c.ink2),
            ),
          ),
          LbmAsync<List<Conversation>>(
            inbox,
            skeleton: const ListRowSkeleton(rows: 4),
            onRetry: () => ref.invalidate(inboxProvider),
            isEmpty: (inbox) => inbox.isEmpty,
            empty: const LbmEmpty(
              title: 'No messages yet',
              body: 'Message a seller from their storefront.',
            ),
            data: (inbox) => LbmCard(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              child: RowStack(
                children: [
                  for (final conversation in inbox)
                    _ConversationRow(conversation: conversation),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _ConversationRow extends ConsumerWidget {
  const _ConversationRow({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final uid = ref.watch(currentUidProvider) ?? '';
    final otherId = conversation.otherThan(uid);
    final person = ref.watch(personProvider(otherId));

    return LbmAsync<Person>(
      person,
      skeleton: const ListRowSkeleton(rows: 1),
      errorBuilder: (_, _) => const SizedBox.shrink(),
      data: (person) => ListRow(
        leading: Avatar(person),
        title: Text(person.name),
        subtitle: Text(
          conversation.preview.isEmpty ? 'Say hello' : conversation.preview,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              conversation.age,
              style: LbmText.xtiny.copyWith(
                color: c.ink3,
                fontFeatures: kTabularFigures,
              ),
            ),
            if (conversation.unread > 0) ...[
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: c.accentDeep,
                  borderRadius: LbmRadius.pillR,
                ),
                child: Text(
                  '${conversation.unread}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: c.accentInk,
                  ),
                ),
              ),
            ],
          ],
        ),
        // The conversation id is resolved here rather than on the message
        // screen, so opening a thread is not gated on a round trip.
        onTap: () => context.push('/you/dm/${conversation.id}'),
      ),
    );
  }
}
