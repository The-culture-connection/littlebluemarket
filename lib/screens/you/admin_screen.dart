import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repositories.dart';
import '../../models/models.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';

/// The merchant's screen, in release builds too (Diagnostics is dev-only).
/// Today: an announcement to everyone or to a role. The screen hides from
/// anyone without the admin claim; the backend refuses them regardless.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  int _audience = 0;
  int _opens = 0;
  bool _busy = false;
  bool _rebuilding = false;
  String? _notice;
  String? _error;
  String? _rebuildNote;

  static const _audiences = AnnouncementAudience.values;
  static const _opensLabels = ['The bell', 'Market', 'Community'];
  static const _opensRoutes = ['/you/notifications', '/market', '/community'];

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
    _body.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  NewAnnouncement get _draft => NewAnnouncement(
    title: _title.text,
    body: _body.text,
    audience: _audiences[_audience],
    route: _opensRoutes[_opens],
  );

  Future<void> _send() async {
    final draft = _draft;
    if (!draft.isValid || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Send to ${draft.audience.label.toLowerCase()}?'),
        content: Text('${draft.title.trim()}\n\n${draft.body.trim()}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not yet'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final sent = await ref.read(adminRepositoryProvider).sendAnnouncement(
        draft,
      );
      if (!mounted) return;
      _title.clear();
      _body.clear();
      setState(() => _notice = 'Sent to ${sent.audience.label.toLowerCase()}.');
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error).body);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rebuild() async {
    if (_rebuilding) return;
    setState(() {
      _rebuilding = true;
      _rebuildNote = null;
    });
    try {
      final progress = await ref.read(adminRepositoryProvider).rebuildBuyerIndex();
      if (!mounted) return;
      setState(
        () => _rebuildNote =
            'Indexed ${progress.total} shop–buyer pairs across '
            '${progress.processed} people.',
      );
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _rebuildNote = describeError(error).body);
    } finally {
      if (mounted) setState(() => _rebuilding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isAdmin = ref.watch(isAdminProvider);
    if (!isAdmin) {
      return const LbmScreen(
        appBar: LbmAppBar(title: 'Admin'),
        child: LbmEmpty(
          title: 'Admins only',
          body:
              'This screen is for the Little Blue Market account. If that is '
              'you, claim admin from Diagnostics first.',
        ),
      );
    }

    final recent = ref.watch(announcementsProvider);
    final draft = _draft;
    final titleLeft = NewAnnouncement.titleMax - _title.text.trim().length;
    final bodyLeft = NewAnnouncement.bodyMax - _body.text.trim().length;

    return LbmScreen(
      appBar: const LbmAppBar(title: 'Admin'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          LbmCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Send an announcement',
                  style: LbmText.display.copyWith(fontSize: 18, color: c.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  'A push to every phone in the audience, and a line under '
                  'their bell.',
                  style: LbmText.tiny.copyWith(color: c.ink2, height: 1.5),
                ),
                const SizedBox(height: 14),
                LbmField(
                  label: 'Title',
                  controller: _title,
                  hintText: 'Hello from Little Blue Market',
                  helper: titleLeft < 0
                      ? '${-titleLeft} over'
                      : '$titleLeft left',
                ),
                const SizedBox(height: 12),
                LbmField(
                  label: 'Message',
                  controller: _body,
                  hintText: 'What is happening, in a sentence or two.',
                  maxLines: 3,
                  helper: bodyLeft < 0 ? '${-bodyLeft} over' : '$bodyLeft left',
                ),
                const SizedBox(height: 6),
                Text(
                  'Who',
                  style: LbmText.xtiny.copyWith(color: c.ink3),
                ),
                SegmentedTabs(
                  labels: [for (final a in _audiences) a.label],
                  selected: _audience,
                  onChanged: (i) => setState(() => _audience = i),
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
                ),
                Text(
                  'A tap opens',
                  style: LbmText.xtiny.copyWith(color: c.ink3),
                ),
                SegmentedTabs(
                  labels: _opensLabels,
                  selected: _opens,
                  onChanged: (i) => setState(() => _opens = i),
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 12),
                ),
                PillButton(
                  _busy ? 'Sending…' : 'Send',
                  onPressed: draft.isValid && !_busy ? _send : null,
                ),
                if (_notice != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _notice!,
                    style: LbmText.tiny.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.sage,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: LbmText.tiny.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.clay,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          LbmCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '"New from a shop you bought from"',
                  style: LbmText.display.copyWith(fontSize: 18, color: c.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  'Every paid order records who bought from whom. Run this once '
                  'to include orders from before today, or after a big import.',
                  style: LbmText.tiny.copyWith(color: c.ink2, height: 1.5),
                ),
                const SizedBox(height: 12),
                PillButton(
                  _rebuilding ? 'Rebuilding…' : 'Rebuild buyer index',
                  style: PillStyle.quiet,
                  onPressed: _rebuilding ? null : _rebuild,
                ),
                if (_rebuildNote != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _rebuildNote!,
                    style: LbmText.tiny.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.ink2,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionHead('Recent announcements'),
          const SizedBox(height: 8),
          LbmAsync<List<Announcement>>(
            recent,
            skeleton: const SizedBox(height: 60),
            data: (list) => list.isEmpty
                ? LbmCard(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Nothing sent yet.',
                      style: LbmText.tiny.copyWith(color: c.ink2),
                    ),
                  )
                : LbmCard(
                    child: RowStack(
                      children: [
                        for (final a in list)
                          ListRow(
                            title: Text(a.title),
                            subtitle: Text(
                              '${a.body}\n${a.audience.label} · ${a.age}',
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                            crossAxisAlignment: CrossAxisAlignment.start,
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
