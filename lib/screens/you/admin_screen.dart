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
          const SectionHead('Bugs and critiques'),
          const SizedBox(height: 8),
          const _FeedbackSection(),
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

/// What the floating bug button collected: newest first, open ones on top,
/// each with the screen it came from. Tap the picture to see it large;
/// Mark done moves it out of the way without deleting anything.
class _FeedbackSection extends ConsumerStatefulWidget {
  const _FeedbackSection();

  @override
  ConsumerState<_FeedbackSection> createState() => _FeedbackSectionState();
}

class _FeedbackSectionState extends ConsumerState<_FeedbackSection> {
  bool _showDone = false;
  final _busy = <String>{};

  Future<void> _setStatus(FeedbackItem item, FeedbackStatus status) async {
    setState(() => _busy.add(item.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(feedbackRepositoryProvider).setStatus(item.id, status);
    } on RepositoryException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeError(error).body)),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  void _showShot(String url) {
    showDialog<void>(
      context: context,
      builder: (dialog) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.of(dialog).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final all = ref.watch(feedbackListProvider);
    return LbmAsync<List<FeedbackItem>>(
      all,
      skeleton: const SizedBox(height: 60),
      data: (list) {
        final open = list.where((f) => f.isOpen).toList();
        final done = list.where((f) => !f.isOpen).toList();
        final shown = _showDone ? list : open;
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
                          ? 'Nothing open. ${done.length} done.'
                          : '${open.length} open · ${done.length} done',
                      style: LbmText.tiny.copyWith(
                        color: c.ink2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (done.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => _showDone = !_showDone),
                      child: Text(_showDone ? 'Hide done' : 'Show done'),
                    ),
                ],
              ),
            ),
            for (final item in shown) ...[
              const SizedBox(height: 8),
              LbmCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.screenshotUrl != null &&
                        item.screenshotUrl!.startsWith('http'))
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: GestureDetector(
                          onTap: () => _showShot(item.screenshotUrl!),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              item.screenshotUrl!,
                              width: 64,
                              height: 114,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 64,
                                height: 114,
                                color: c.skyMist,
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: c.ink3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              LbmChip(
                                item.kind == FeedbackKind.bug
                                    ? 'Bug'
                                    : 'Critique',
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${item.isGuest ? 'a guest' : (item.fromName.isEmpty ? item.uid : item.fromName)} · ${item.age}',
                                  style: LbmText.tiny.copyWith(color: c.ink3),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.text,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.5,
                              color: c.ink,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${item.route} · ${item.platform}',
                            style: LbmText.tiny.copyWith(color: c.ink3),
                          ),
                          const SizedBox(height: 10),
                          PillButton(
                            item.isOpen ? 'Mark done' : 'Reopen',
                            style: PillStyle.quiet,
                            small: true,
                            expand: false,
                            onPressed: _busy.contains(item.id)
                                ? null
                                : () => _setStatus(
                                    item,
                                    item.isOpen
                                        ? FeedbackStatus.done
                                        : FeedbackStatus.open,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
