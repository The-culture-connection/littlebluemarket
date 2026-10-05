import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repositories.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';

/// Everyone this account has blocked, and the way to undo it.
///
/// A block has to be undoable somewhere that is easy to find, or it is a
/// trap rather than a tool: the sheet that sets it is on the person's post,
/// and once they are blocked their posts are exactly what you can no longer
/// see. So the list lives in Edit profile.
class BlockedScreen extends ConsumerWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final blocked = ref.watch(blockedUidsProvider);

    return LbmScreen(
      appBar: const LbmAppBar(title: 'Blocked people'),
      child: LbmAsync<Set<String>>(
        blocked,
        skeleton: const ListRowSkeleton(rows: 3),
        onRetry: () => ref.invalidate(blockedUidsProvider),
        isEmpty: (ids) => ids.isEmpty,
        empty: const LbmEmpty(
          title: 'Nobody is blocked',
          body:
              'Tap the three dots on anyone\'s post or profile to block them. '
              'They are never told, and you can undo it here.',
        ),
        data: (ids) => ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 26),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(
                'You do not see their posts, comments, chat messages or '
                'messages. They have not been told.',
                style: LbmText.tiny.copyWith(color: c.ink2, height: 1.5),
              ),
            ),
            LbmCard(
              child: RowStack(
                children: [
                  for (final uid in ids) _BlockedRow(uid: uid),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One blocked person, named if their profile can still be read.
class _BlockedRow extends ConsumerWidget {
  const _BlockedRow({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(personProvider(uid)).value;

    return ListRow(
      leading: person == null
          ? const LbmSkeleton(width: 38, height: 38, radius: 19)
          : Avatar(person),
      // A blocked person whose profile has since gone is still blocked, and
      // still has to be unblockable, so the uid stands in for the name.
      title: Text(person?.name ?? uid),
      subtitle: Text(person?.handle ?? 'This profile is no longer readable'),
      trailing: PillButton(
        'Unblock',
        small: true,
        expand: false,
        style: PillStyle.quiet,
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            await ref.read(reportRepositoryProvider).unblockUser(uid);
            messenger.showSnackBar(
              SnackBar(content: Text('Unblocked ${person?.handle ?? uid}.')),
            );
          } on RepositoryException catch (error) {
            messenger.showSnackBar(
              SnackBar(content: Text(describeError(error).body)),
            );
          }
        },
      ),
    );
  }
}
