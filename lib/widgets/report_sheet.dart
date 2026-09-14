import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/repositories.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'async.dart';
import 'primitives.dart';
import 'sheets.dart';

/// The "…" menu on someone's profile and on a post: Report, and Block.
///
/// Guests are sent to make a profile first, since both have to come from
/// someone. Two different things, deliberately offered together: a report
/// asks Little Blue Market to look at somebody, a block just takes them off
/// your own screen and tells them nothing. Both are required by the app
/// stores for an app that carries what people write.
Future<void> showMoreSheet(
  BuildContext context,
  WidgetRef ref, {
  required String subjectUid,
  required String subjectName,
  required String subjectHandle,
  String? postId,
}) {
  final me = ref.read(currentUidProvider);
  return showLbmSheet<void>(context, (sheetContext) {
    final c = sheetContext.c;
    final isSelf = me != null && me == subjectUid;
    return LbmSheet(
      children: [
        ListRow(
          leading: Icon(Icons.flag_outlined, color: isSelf ? c.ink3 : c.clay),
          title: Text(postId == null ? 'Report $subjectHandle' : 'Report this post'),
          subtitle: Text(
            isSelf
                ? 'This is you.'
                : 'Tell Little Blue Market about spam, harassment, a fake shop '
                      'or anything else that should not be here.',
          ),
          onTap: isSelf
              ? null
              : () {
                  Navigator.of(sheetContext).pop();
                  requireProfile(context, ref, () {
                    showReportSheet(
                      context,
                      subjectUid: subjectUid,
                      subjectName: subjectName,
                      subjectHandle: subjectHandle,
                      postId: postId,
                    );
                  });
                },
        ),
        if (!isSelf) _BlockRow(subjectUid: subjectUid, handle: subjectHandle),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  });
}

/// The report itself: a reason, a few words, Send.
Future<void> showReportSheet(
  BuildContext context, {
  required String subjectUid,
  required String subjectName,
  required String subjectHandle,
  String? postId,
}) => showLbmSheet<void>(
  context,
  (_) => _ReportSheet(
    subjectUid: subjectUid,
    subjectName: subjectName,
    subjectHandle: subjectHandle,
    postId: postId,
  ),
);

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({
    required this.subjectUid,
    required this.subjectName,
    required this.subjectHandle,
    this.postId,
  });

  final String subjectUid;
  final String subjectName;
  final String subjectHandle;
  final String? postId;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _text = TextEditingController();
  ReportReason? _reason;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  NewReport? get _draft {
    final reason = _reason;
    if (reason == null) return null;
    final session = ref.read(sessionProvider).value;
    return NewReport(
      subjectUid: widget.subjectUid,
      subjectName: widget.subjectName,
      subjectHandle: widget.subjectHandle,
      kind: widget.postId == null ? ReportKind.user : ReportKind.post,
      postId: widget.postId,
      reason: reason,
      text: _text.text,
      reporterName: session is MemberSession ? session.profile.name : '',
    );
  }

  Future<void> _send() async {
    final draft = _draft;
    if (draft == null || !draft.isValid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(reportRepositoryProvider).submit(draft);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Reported. Thank you; Little Blue Market will look.'),
        ),
      );
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(error).body;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final draft = _draft;
    final what = widget.postId == null
        ? widget.subjectHandle
        : 'this post by ${widget.subjectHandle}';
    return LbmSheet(
      children: [
        Text(
          'Report $what',
          style: LbmText.display.copyWith(fontSize: 20, color: c.ink),
        ),
        const SizedBox(height: 6),
        Text(
          'Only Little Blue Market sees this. ${widget.subjectName} is not told '
          'who reported them.',
          style: LbmText.tiny.copyWith(color: c.ink2, height: 1.5),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final reason in ReportReason.values)
              ChoiceChip(
                label: Text(reason.label),
                selected: _reason == reason,
                onSelected: (_) => setState(() => _reason = reason),
              ),
          ],
        ),
        const SizedBox(height: 14),
        LbmField(
          label: _reason == ReportReason.other
              ? 'What happened?'
              : 'Anything else? (optional)',
          controller: _text,
          maxLines: 4,
          hintText: 'What did you see, and where?',
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: LbmText.tiny.copyWith(
              color: c.clay,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 16),
        PillButton(
          _busy ? 'Sending…' : 'Send report',
          onPressed: _busy || draft == null || !draft.isValid ? null : _send,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Block or unblock, from the "…" sheet.
///
/// Reads the live blocked set rather than a flag passed in, so the row says
/// Unblock the moment it has been used and cannot go stale.
class _BlockRow extends ConsumerWidget {
  const _BlockRow({required this.subjectUid, required this.handle});

  final String subjectUid;
  final String handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final blocked = ref.watch(blockedUidsProvider).value ?? const <String>{};
    final isBlocked = blocked.contains(subjectUid);

    return ListRow(
      leading: Icon(
        isBlocked ? Icons.person_add_alt_1_outlined : Icons.block_outlined,
        color: isBlocked ? c.ink2 : c.clay,
      ),
      title: Text(isBlocked ? 'Unblock $handle' : 'Block $handle'),
      subtitle: Text(
        isBlocked
            ? 'Their posts, comments and messages come back.'
            : 'You stop seeing their posts, comments, chat and messages. '
                  'They are not told.',
      ),
      onTap: () async {
        final messenger = ScaffoldMessenger.maybeOf(context);
        final navigator = Navigator.of(context);
        final repo = ref.read(reportRepositoryProvider);
        if (!isBlocked) {
          final sure = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Block $handle?'),
              content: const Text(
                'You will stop seeing their posts, comments, chat messages '
                'and messages. They are not told, and you can undo this in '
                'Edit profile.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Not now'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Block'),
                ),
              ],
            ),
          );
          if (sure != true) return;
        }
        try {
          if (isBlocked) {
            await repo.unblockUser(subjectUid);
          } else {
            await repo.blockUser(subjectUid);
          }
          if (navigator.canPop()) navigator.pop();
          messenger?.showSnackBar(
            SnackBar(
              content: Text(
                isBlocked ? 'Unblocked $handle.' : 'Blocked $handle.',
              ),
            ),
          );
        } on RepositoryException catch (error) {
          messenger?.showSnackBar(
            SnackBar(content: Text(describeError(error).body)),
          );
        }
      },
    );
  }
}
