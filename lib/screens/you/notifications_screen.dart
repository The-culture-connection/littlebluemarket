import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';

/// The bell: who mentioned you, who commented on your post.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the list is reading it. Marked after the first frame so the
    // unread styling is seen once, then cleared.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(socialRepositoryProvider)
          .markNotificationsRead()
          .catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final notifications = ref.watch(notificationsProvider);

    return LbmScreen(
      appBar: const LbmAppBar(title: 'Notifications'),
      child: LbmAsync<List<AppNotification>>(
        notifications,
        skeleton: const ListRowSkeleton(rows: 3),
        onRetry: () => ref.invalidate(notificationsProvider),
        isEmpty: (all) => all.isEmpty,
        empty: const LbmEmpty(
          title: 'Nothing yet',
          body:
              'When someone mentions you or comments on your post, it lands here.',
        ),
        data: (all) => ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 26),
          children: [
            LbmCard(
              child: RowStack(
                children: [
                  for (final n in all)
                    _NotificationRow(notification: n, color: c),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationRow extends ConsumerWidget {
  const _NotificationRow({required this.notification, required this.color});

  final AppNotification notification;
  final LbmColors color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = color;
    final from = ref.watch(personProvider(notification.fromUid));
    final name = from.value?.name ?? 'Someone';
    return ListRow(
      background: notification.read
          ? null
          : c.accentMist.withValues(alpha: 0.4),
      leading: from.value == null
          ? const LbmSkeleton(width: 36, height: 36, radius: 18)
          : Avatar(from.value!, size: AvatarSize.sm),
      title: Text('$name ${notification.headline}'),
      subtitle: Text(
        notification.text.isEmpty
            ? notification.age
            : '${notification.text}\n${notification.age}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      crossAxisAlignment: CrossAxisAlignment.start,
      onTap: () => context.goToPost(notification.postId),
    );
  }
}
