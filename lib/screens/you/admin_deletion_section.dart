import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/skeleton.dart';

/// People asking for their account or their data to go, newest first.
///
/// Open ones first, because they are the ones with a clock on them. Doing it
/// is deliberately two taps behind a confirm: it cannot be undone, and the
/// request may have come from someone who only typed an address.
class AdminDeletionSection extends ConsumerStatefulWidget {
  const AdminDeletionSection({super.key});

  @override
  ConsumerState<AdminDeletionSection> createState() =>
      _AdminDeletionSectionState();
}

class _AdminDeletionSectionState extends ConsumerState<AdminDeletionSection> {
  var _showClosed = false;
  String? _busyId;

  Future<void> _run(String id, Future<void> Function() action) async {
    setState(() => _busyId = id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeError(error).body)),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(DeletionRequest request) async {
    final uid = request.uid;
    if (uid == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this account?'),
        content: Text(
          request.scope == DeletionScope.data
              ? 'Their profile details, photos and posts go. Their sign-in '
                    'stays. Orders are kept. This cannot be undone.'
              : 'Their sign-in, profile, photos and posts all go. Orders are '
                    'kept as financial records. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(request.id, () async {
      await ref
          .read(accountRepositoryProvider)
          .deleteAccountNow(
            uid: uid,
            requestId: request.id,
            keepAccount: request.scope == DeletionScope.data,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final requests = ref.watch(deletionRequestsProvider);

    return LbmAsync<List<DeletionRequest>>(
      requests,
      skeleton: const ListRowSkeleton(rows: 2, withAvatar: false),
      isEmpty: (all) => all.where((r) => r.isOpen).isEmpty && !_showClosed,
      empty: const LbmEmpty(
        title: 'Nothing to do',
        body: 'Requests to delete an account land here.',
        compact: true,
      ),
      data: (all) {
        final shown = _showClosed ? all : all.where((r) => r.isOpen).toList();
        final closed = all.length - all.where((r) => r.isOpen).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final request in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LbmCard(
                  padding: const EdgeInsets.all(14),
                  child: RowStack(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              request.email,
                              style: LbmText.body.copyWith(
                                fontWeight: FontWeight.w800,
                                color: c.ink,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          LbmChip(request.status.label, fontSize: 11),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${request.scope.label} · ${request.age}'
                        '${request.name.isEmpty ? '' : ' · ${request.name}'}'
                        '${request.uid == null ? ' · not signed in' : ''}',
                        style: LbmText.tiny.copyWith(color: c.ink2),
                      ),
                      if (request.note.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          request.note,
                          style: LbmText.tiny.copyWith(color: c.ink2),
                        ),
                      ],
                      if (request.isOpen) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            PillButton(
                              _busyId == request.id ? 'Working…' : 'Mark done',
                              small: true,
                              expand: false,
                              style: PillStyle.quiet,
                              onPressed: _busyId != null
                                  ? null
                                  : () => _run(
                                      request.id,
                                      () => ref
                                          .read(accountRepositoryProvider)
                                          .setDeletionStatus(
                                            request.id,
                                            DeletionStatus.done,
                                          ),
                                    ),
                            ),
                            if (request.uid != null)
                              PillButton(
                                'Delete now',
                                small: true,
                                expand: false,
                                style: PillStyle.ghost,
                                onPressed: _busyId != null
                                    ? null
                                    : () => _delete(request),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (closed > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: PillButton(
                  _showClosed ? 'Hide closed' : 'Show closed ($closed)',
                  small: true,
                  expand: false,
                  style: PillStyle.ghost,
                  onPressed: () => setState(() => _showClosed = !_showClosed),
                ),
              ),
          ],
        );
      },
    );
  }
}
