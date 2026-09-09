import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/push/push_service.dart';
import '../../data/repositories/repositories.dart';
import '../../models/models.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';

/// Notifications: whether this phone may show them, a test button that
/// proves it, and the switches for what you hear about. The switches live
/// on the account, so a second phone inherits them.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  PushPermission? _permission;
  String? _notice;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPermission());
  }

  Future<void> _refreshPermission() async {
    final status = await ref.read(pushServiceProvider).permissionStatus();
    if (mounted) setState(() => _permission = status);
  }

  Future<void> _allow() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    final status = await ref.read(pushServiceProvider).requestPermission();
    if (!mounted) return;
    setState(() {
      _permission = status;
      _busy = false;
      _notice = switch (status) {
        PushPermission.granted => 'Notifications are on for this phone.',
        PushPermission.denied =>
          'Turned off for this app. Allow it in the phone\'s Settings → Apps → '
              'Little Blue Market → Notifications, then come back.',
        PushPermission.notDetermined => 'Not decided yet.',
        PushPermission.unsupported => 'This device cannot show notifications.',
      };
    });
  }

  Future<void> _test() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(pushServiceProvider).sendTest();
      if (!mounted) return;
      setState(
        () => _notice =
            'Sent. Press Home and watch for the banner; it also lands under '
            'the bell.',
      );
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error).body);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(NotificationPrefs next) async {
    try {
      await ref.read(socialRepositoryProvider).saveNotificationPrefs(next);
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error).body);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final prefs = ref.watch(notificationPrefsProvider);
    final permission = _permission;
    final granted = permission == PushPermission.granted;

    final statusLine = switch (permission) {
      null => 'Checking…',
      PushPermission.granted => 'Allowed on this phone.',
      PushPermission.denied =>
        'Turned off for this app in the phone\'s Settings.',
      PushPermission.notDetermined => 'Not asked yet.',
      PushPermission.unsupported => 'Not available on this device.',
    };

    return LbmScreen(
      appBar: const LbmAppBar(title: 'Notifications'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          LbmCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'On this phone',
                  style: LbmText.display.copyWith(fontSize: 18, color: c.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  statusLine,
                  style: LbmText.tiny.copyWith(color: c.ink2, height: 1.5),
                ),
                const SizedBox(height: 12),
                if (granted)
                  PillButton(
                    _busy ? 'Sending…' : 'Send me a test notification',
                    style: PillStyle.quiet,
                    onPressed: _busy ? null : _test,
                  )
                else
                  PillButton(
                    _busy ? 'One moment…' : 'Allow notifications',
                    onPressed: _busy || permission == null ? null : _allow,
                  ),
                if (_notice != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _notice!,
                    style: LbmText.tiny.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.sage,
                      height: 1.5,
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
          const SectionHead('What you hear about'),
          const SizedBox(height: 8),
          LbmAsync<NotificationPrefs>(
            prefs,
            skeleton: const SizedBox(height: 120),
            data: (p) => LbmCard(
              child: RowStack(
                children: [
                  _Switch(
                    title: 'Mentions and shoutouts',
                    subtitle: 'Someone names you in a post',
                    value: p.mentions,
                    onChanged: (v) => _save(p.copyWith(mentions: v)),
                  ),
                  _Switch(
                    title: 'Comments',
                    subtitle: 'Someone comments on your post',
                    value: p.comments,
                    onChanged: (v) => _save(p.copyWith(comments: v)),
                  ),
                  _Switch(
                    title: 'Forums',
                    subtitle:
                        'New threads where you are a member, and replies to '
                        'you',
                    value: p.forums,
                    onChanged: (v) => _save(p.copyWith(forums: v)),
                  ),
                  _Switch(
                    title: 'Reviews',
                    subtitle: 'Someone reviews one of your products',
                    value: p.reviews,
                    onChanged: (v) => _save(p.copyWith(reviews: v)),
                  ),
                  _Switch(
                    title: 'New from shops you bought from',
                    subtitle: 'A seller you have ordered from adds something',
                    value: p.newProducts,
                    onChanged: (v) => _save(p.copyWith(newProducts: v)),
                  ),
                  _Switch(
                    title: 'Posts from people you follow',
                    subtitle: 'Anyone you tapped Notify me on posts something',
                    value: p.newPosts,
                    onChanged: (v) => _save(p.copyWith(newPosts: v)),
                  ),
                  _Switch(
                    title: 'Announcements',
                    subtitle: 'News from Little Blue Market',
                    value: p.announcements,
                    onChanged: (v) => _save(p.copyWith(announcements: v)),
                  ),
                  if (p.mutedForums.isNotEmpty)
                    ListRow(
                      title: Text(
                        '${p.mutedForums.length} muted '
                        '${p.mutedForums.length == 1 ? 'forum' : 'forums'}',
                      ),
                      subtitle: const Text('Tap to hear from them again'),
                      trailing: Icon(
                        Icons.volume_up_outlined,
                        size: 22,
                        color: c.ink3,
                      ),
                      onTap: () => _save(p.copyWith(mutedForums: const [])),
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

class _Switch extends StatelessWidget {
  const _Switch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListRow(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Switch.adaptive(value: value, onChanged: onChanged),
      onTap: () => onChanged(!value),
    );
  }
}
