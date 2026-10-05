import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repositories.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';

/// Reports members made about each other, on the Admin screen: open ones on
/// top, each with who, why and the words. Resolve closes one; Ban disables
/// the person's sign-in, removes their posts and closes every report about
/// them (a confirm dialog stands in the way). Unban is here too, for a
/// mistake.
class AdminReportsSection extends ConsumerStatefulWidget {
  const AdminReportsSection({super.key});

  @override
  ConsumerState<AdminReportsSection> createState() => _AdminReportsSectionState();
}

class _AdminReportsSectionState extends ConsumerState<AdminReportsSection> {
  bool _showClosed = false;
  final _busy = <String>{};

  Future<void> _run(
    String key,
    Future<void> Function() action,
    String done,
  ) async {
    setState(() => _busy.add(key));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on RepositoryException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeError(error).body)),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _ban(Report r) async {
    final who = r.subjectName.isEmpty ? r.subjectHandle : r.subjectName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Ban $who?'),
        content: const Text(
          'Their sign-in is disabled, their posts are removed from the feed, '
          'and every open report about them is closed. You can unban later, '
          'but the posts do not come back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Ban'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      'ban-${r.subjectUid}',
      () => ref
          .read(reportRepositoryProvider)
          .banUser(r.subjectUid, reportId: r.id, reason: r.reason.label),
      'Banned ${r.subjectHandle}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LbmAsync<List<Report>>(
      ref.watch(reportsProvider),
      skeleton: const SizedBox(height: 60),
      data: (list) {
        final open = list.where((r) => r.isOpen).toList();
        final closed = list.where((r) => !r.isOpen).toList();
        final shown = _showClosed ? list : open;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LbmCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      open.isEmpty
                          ? 'Nothing open. ${closed.length} closed.'
                          : '${open.length} open · ${closed.length} closed',
                      style: LbmText.tiny.copyWith(
                        color: c.ink2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (closed.isNotEmpty)
                    TextButton(
                      onPressed: () =>
                          setState(() => _showClosed = !_showClosed),
                      child: Text(_showClosed ? 'Hide closed' : 'Show closed'),
                    ),
                ],
              ),
            ),
            for (final r in shown) ...[
              const SizedBox(height: 8),
              _ReportCard(
                report: r,
                busy: _busy,
                onResolve: () => _run(
                  'resolve-${r.id}',
                  () => ref.read(reportRepositoryProvider).resolve(r.id),
                  'Resolved.',
                ),
                onBan: () => _ban(r),
                onUnban: () => _run(
                  'unban-${r.subjectUid}',
                  () =>
                      ref.read(reportRepositoryProvider).unbanUser(r.subjectUid),
                  'Unbanned ${r.subjectHandle}.',
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.busy,
    required this.onResolve,
    required this.onBan,
    required this.onUnban,
  });

  final Report report;
  final Set<String> busy;
  final VoidCallback onResolve;
  final VoidCallback onBan;
  final VoidCallback onUnban;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = report;
    final subject = r.subjectName.isEmpty
        ? r.subjectHandle
        : '${r.subjectName} (${r.subjectHandle})';
    return LbmCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              LbmChip(r.reason.label),
              if (!r.isOpen) LbmChip(r.status.label),
              if (r.subjectBanned && r.status != ReportStatus.banned)
                const LbmChip('Banned'),
              Text(r.age, style: LbmText.tiny.copyWith(color: c.ink3)),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => context.goToSeller(r.subjectUid),
            child: Text(
              '${r.kind == ReportKind.post ? 'A post by ' : ''}$subject',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: c.skyDeep,
              ),
            ),
          ),
          Text(
            'reported by ${r.reporterName.isEmpty ? r.reporterUid : r.reporterName}',
            style: LbmText.tiny.copyWith(color: c.ink3),
          ),
          if (r.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              r.text,
              style: TextStyle(fontSize: 13.5, height: 1.5, color: c.ink),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (r.postId != null)
                PillButton(
                  'Open the post',
                  style: PillStyle.ghost,
                  small: true,
                  expand: false,
                  onPressed: () => context.goToPost(r.postId!),
                ),
              if (r.isOpen)
                PillButton(
                  'Resolve',
                  style: PillStyle.quiet,
                  small: true,
                  expand: false,
                  onPressed: busy.contains('resolve-${r.id}') ? null : onResolve,
                ),
              if (!r.subjectBanned)
                PillButton(
                  'Ban ${r.subjectHandle}',
                  small: true,
                  expand: false,
                  onPressed: busy.contains('ban-${r.subjectUid}') ? null : onBan,
                )
              else
                PillButton(
                  'Unban',
                  style: PillStyle.ghost,
                  small: true,
                  expand: false,
                  onPressed:
                      busy.contains('unban-${r.subjectUid}') ? null : onUnban,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
