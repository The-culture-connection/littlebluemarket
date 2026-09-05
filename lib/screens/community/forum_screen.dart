import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/repositories.dart';
import '../../models/models.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import '../../widgets/sheets.dart';
import '../../widgets/skeleton.dart';

/// Threads inside one forum: a vote column, the title, the author and a
/// comment count.
class ForumScreen extends ConsumerWidget {
  const ForumScreen({super.key, required this.forumId});

  final String forumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final forum = ref.watch(forumProvider(forumId));
    final threads = ref.watch(threadsProvider(forumId));

    return LbmScreen(
      appBar: LbmAppBar(
        title: forum.value?.title ?? 'Forum',
        actions: [_JoinButton(forumId: forumId)],
      ),
      child: LbmAsync<Forum>(
        forum,
        skeleton: const ListRowSkeleton(rows: 1, withAvatar: false),
        onRetry: () => ref.invalidate(forumProvider(forumId)),
        data: (forum) => ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    forum.description,
                    style: TextStyle(fontSize: 13, height: 1.5, color: c.ink2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${forum.membersLabel} · '
                    '${Fmt.count(forum.threadCount)} threads',
                    style: LbmText.xtiny.copyWith(
                      color: c.ink2,
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            LbmAsync<List<ForumThread>>(
              threads,
              skeleton: const ListRowSkeleton(rows: 2, withAvatar: false),
              isEmpty: (threads) => threads.isEmpty,
              empty: const LbmEmpty(
                title: 'No threads yet',
                body: 'Start the conversation.',
              ),
              data: (threads) => Column(
                children: [
                  for (final thread in threads)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      child: _ThreadCard(thread: thread),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 26),
              child: PillButton(
                'New thread',
                icon: Icons.add_rounded,
                style: PillStyle.ghost,
                onPressed: () => requireProfile(
                  context,
                  ref,
                  () => showLbmSheet(
                    context,
                    (_) => NewThreadComposer(forumId: forumId),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinButton extends ConsumerWidget {
  const _JoinButton({required this.forumId});

  final String forumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final joined = ref.watch(forumMembershipProvider(forumId)).value ?? false;

    return PillButton(
      joined ? 'Joined' : 'Join',
      small: true,
      expand: false,
      style: joined ? PillStyle.quiet : PillStyle.solid,
      onPressed: () => requireProfile(context, ref, () {
        // The state wanted, not a toggle, so the member count moves once.
        ref.read(socialRepositoryProvider).setForumMembership(forumId, !joined);
      }),
    );
  }
}

/// Start a thread in this forum.
class NewThreadComposer extends ConsumerStatefulWidget {
  const NewThreadComposer({super.key, required this.forumId});

  final String forumId;

  @override
  ConsumerState<NewThreadComposer> createState() => _NewThreadComposerState();
}

class _NewThreadComposerState extends ConsumerState<NewThreadComposer> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final navigator = Navigator.of(context);
    try {
      await ref
          .read(socialRepositoryProvider)
          .createThread(
            NewThread(
              forumId: widget.forumId,
              title: _title.text,
              body: _body.text,
            ),
          );
      navigator.pop();
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeError(error).body;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return LbmSheet(
      children: [
        Text(
          'Start a thread',
          style: LbmText.display.copyWith(fontSize: 21, color: c.ink),
        ),
        const SizedBox(height: 14),
        LbmField(label: 'Title', controller: _title, autofocus: true),
        const SizedBox(height: 14),
        LbmField(
          label: 'What do you want to ask?',
          controller: _body,
          maxLines: 4,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: LbmText.tiny.copyWith(color: c.clay)),
        ],
        const SizedBox(height: 16),
        PillButton(
          _saving ? 'Posting…' : 'Post thread',
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }
}

class _ThreadCard extends ConsumerWidget {
  const _ThreadCard({required this.thread});

  final ForumThread thread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final author = ref.watch(personProvider(thread.authorId));

    return LbmCard(
      onTap: () => context.push('/community/thread/${thread.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    thread.title,
                    style: LbmText.display.copyWith(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      height: 1.32,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  LbmAsync<Person>(
                    author,
                    skeleton: const LbmSkeleton(width: 160, height: 11),
                    errorBuilder: (_, _) => const SizedBox.shrink(),
                    data: (person) => Text(
                      '${person.handle} · ${thread.age} · '
                      '${Fmt.count(thread.commentCount)} comments',
                      style: LbmText.xtiny.copyWith(color: c.ink2),
                    ),
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
