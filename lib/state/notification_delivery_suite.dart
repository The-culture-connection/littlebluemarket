import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../data/push/push_service.dart';
import '../models/models.dart';
import 'providers.dart';

/// How one delivery check came out.
enum CheckStatus { pass, fail, skip, inconclusive }

@immutable
class CheckResult {
  const CheckResult(this.name, this.status, [this.detail = '']);

  final String name;
  final CheckStatus status;
  final String detail;

  String get line =>
      '${status.name.toUpperCase().padRight(12)} $name'
      '${detail.isEmpty ? '' : '  ·  $detail'}';
}

/// What the suite needs from the app, so a test can stand in for the phone,
/// the backend and the bell.
class DeliverySuiteDeps {
  const DeliverySuiteDeps({
    required this.step,
    required this.sendTest,
    required this.received,
    required this.bell,
    required this.subscribe,
    required this.unsubscribe,
    this.arrive = const Duration(seconds: 60),
    this.silence = const Duration(seconds: 30),
  });

  /// One backend step (`diagNotifyTest`).
  final Future<Map<String, Object?>> Function(String step, String nonce) step;

  /// The existing "Send me a test notification".
  final Future<void> Function() sendTest;

  /// Pushes that actually reached this phone.
  final Stream<ReceivedPush> received;

  /// This account's bell rows, live.
  final Stream<List<AppNotification>> bell;
  final Future<void> Function(String topic) subscribe;
  final Future<void> Function(String topic) unsubscribe;

  /// How long a push may take to arrive.
  final Duration arrive;

  /// How long a push must not arrive before "held" counts.
  final Duration silence;
}

/// The notification delivery suite on the Diagnostics screen.
///
/// This phone is the device under test. The backend makes one real thing
/// happen at a time, as a bot (a comment on your post, a mention, a DM, a
/// forum reply, the digest, an announcement), and a check passes only on
/// what this phone actually receives:
///
///  * every action carries a nonce, and a push only matches its own;
///  * a "held" check needs the bell row for that action (so the backend ran
///    and chose not to push) and no push, and a push later on the same
///    channel shows the silence was not a dead line;
///  * a held push that turns up later still fails the run;
///  * the channel is checked first: if the plain test push does not arrive,
///    the run stops INCONCLUSIVE, because nothing after it would mean
///    anything.
///
/// Keep the app open on this screen: a phone only hands the app pushes that
/// arrive while it is in the foreground.
class NotificationDeliverySuite {
  NotificationDeliverySuite(this.deps);

  final DeliverySuiteDeps deps;
  final _pushes = <ReceivedPush>[];
  final _bellRows = <AppNotification>[];
  final _held = <({String name, String nonce})>[];
  final results = <CheckResult>[];

  static final _random = Random();
  static String nonce(String what) =>
      '$what-${_random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0')}';

  Future<List<CheckResult>> run({void Function(CheckResult)? onResult}) async {
    void add(CheckResult r) {
      results.add(r);
      onResult?.call(r);
    }

    final pushSub = deps.received.listen(_pushes.add);
    final bellSub = deps.bell.listen((rows) {
      _bellRows
        ..clear()
        ..addAll(rows);
    });
    String? topic;
    try {
      final setup = await deps.step('setup', nonce('setup'));
      topic = setup['topic'] as String?;
      if (topic != null) await deps.subscribe(topic);

      // 0. The channel.
      final since = DateTime.now();
      await deps.sendTest();
      final channel = await _waitFor(
        (p) => p.at.isAfter(since) && p.type == 'test',
        deps.arrive,
      );
      if (channel == null) {
        add(
          CheckResult(
            'Channel: a test push reaches this phone',
            CheckStatus.inconclusive,
            'nothing arrived. Allow notifications for this app, keep it open '
                'on this screen, and run again. Nothing below would mean anything.',
          ),
        );
        return results;
      }
      add(
        CheckResult(
          'Channel: a test push reaches this phone',
          CheckStatus.pass,
          channel.body,
        ),
      );

      // 1. A comment pushes.
      add(
        await _expectPush(
          'A comment on your post pushes',
          'comment',
          (t) => t.contains('commented'),
        ),
      );
      // 2. The rate limit holds the next one.
      add(await _expectHeld('Rate limit: a second comment is held', 'comment'));
      // 3. A mention and a DM get through the limit.
      add(
        await _expectPush(
          'A mention gets through the rate limit',
          'mention',
          (t) => t.contains('mentioned you'),
        ),
      );
      add(
        await _expectPush(
          'A direct message gets through the rate limit',
          'dm',
          (t) => t == 'Diagnostics bot',
        ),
      );
      // 4. Quiet hours.
      await deps.step('quietOn', nonce('quiet'));
      add(await _expectHeld('Quiet hours: a comment is held', 'comment'));
      add(
        await _expectPush(
          'Quiet hours: a direct message still gets through',
          'dm',
          (t) => t == 'Diagnostics bot',
        ),
      );
      // 5. Announcements are on their own path: through, even in quiet hours.
      add(
        await _expectPush(
          'An announcement arrives (private topic), even in quiet hours',
          'announcement',
          (t) => t == 'Diagnostics announcement',
          type: 'announcement',
        ),
      );
      // 6. Forum replies wait for the digest.
      await deps.step('quietOff', nonce('quiet'));
      add(
        await _expectHeld(
          'A forum reply is not pushed on its own',
          'forumReply',
        ),
      );
      add(await _expectDigest());

      // Anything held must still be held at the end, after one more silence
      // window: a push that was only slow must not escape by the run ending.
      await Future<void>.delayed(deps.silence);
      for (final h in _held) {
        final late = _pushes.where((p) => p.body.contains(h.nonce)).firstOrNull;
        if (late != null) {
          add(
            CheckResult(
              '${h.name} (late)',
              CheckStatus.fail,
              'arrived after all: "${late.title}"',
            ),
          );
        }
      }
    } on Object catch (error) {
      add(CheckResult('The run itself', CheckStatus.fail, '$error'));
    } finally {
      try {
        await deps.step('restore', nonce('restore'));
      } on Object catch (error) {
        add(
          CheckResult(
            'Clean up',
            CheckStatus.fail,
            'test content or settings may be left behind: $error',
          ),
        );
      }
      if (topic != null) {
        try {
          await deps.unsubscribe(topic);
        } on Object {
          // Leaving a private topic can wait for the next run.
        }
      }
      await pushSub.cancel();
      await bellSub.cancel();
    }
    return results;
  }

  Future<ReceivedPush?> _waitFor(
    bool Function(ReceivedPush) match,
    Duration within,
  ) async {
    final deadline = DateTime.now().add(within);
    while (DateTime.now().isBefore(deadline)) {
      final hit = _pushes.where(match).firstOrNull;
      if (hit != null) return hit;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return _pushes.where(match).firstOrNull;
  }

  Future<CheckResult> _expectPush(
    String name,
    String step,
    bool Function(String title) titleOk, {
    String? type,
  }) async {
    final n = nonce(step);
    await deps.step(step, n);
    final hit = await _waitFor((p) => p.body.contains(n), deps.arrive);
    if (hit == null) {
      return CheckResult(
        name,
        CheckStatus.fail,
        'nothing carrying $n arrived within ${deps.arrive.inSeconds}s',
      );
    }
    if (!titleOk(hit.title) || (type != null && hit.type != type)) {
      return CheckResult(
        name,
        CheckStatus.fail,
        'arrived, but as [${hit.type}] "${hit.title}"',
      );
    }
    return CheckResult(name, CheckStatus.pass, '"${hit.title}" · ${hit.body}');
  }

  Future<CheckResult> _expectHeld(String name, String step) async {
    final n = nonce(step);
    await deps.step(step, n);
    final deadline = DateTime.now().add(deps.arrive);
    var row = false;
    while (!row && DateTime.now().isBefore(deadline)) {
      row = _bellRows.any((r) => r.text.contains(n));
      if (!row) await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (!row) {
      return CheckResult(
        name,
        CheckStatus.fail,
        'no bell row for $n: the backend never ran, so silence proves nothing',
      );
    }
    final hit = await _waitFor((p) => p.body.contains(n), deps.silence);
    if (hit != null) {
      return CheckResult(
        name,
        CheckStatus.fail,
        'pushed anyway: "${hit.title}"',
      );
    }
    _held.add((name: name, nonce: n));
    return CheckResult(
      name,
      CheckStatus.pass,
      'bell row written, no push in ${deps.silence.inSeconds}s',
    );
  }

  Future<CheckResult> _expectDigest() async {
    const name = 'The forum digest arrives: "1 new reply in 1 thread"';
    final since = DateTime.now();
    final outcome = await deps.step('digestNow', nonce('digest'));
    final hit = await _waitFor(
      (p) => !p.at.isBefore(since) && p.title == 'New in your forums',
      deps.arrive,
    );
    if (hit == null) {
      return CheckResult(
        name,
        CheckStatus.fail,
        'nothing arrived (the backend said ${outcome['outcome']})',
      );
    }
    if (hit.body != '1 new reply in 1 thread') {
      return CheckResult(name, CheckStatus.fail, 'said "${hit.body}"');
    }
    return CheckResult(name, CheckStatus.pass, hit.body);
  }
}

/// The suite wired to this app's real push service, backend and bell.
final notificationDeliverySuiteProvider = Provider<NotificationDeliverySuite>((
  ref,
) {
  final push = ref.watch(pushServiceProvider);
  final diagnostics = ref.watch(diagnosticsRepositoryProvider);
  final social = ref.watch(socialRepositoryProvider);
  return NotificationDeliverySuite(
    DeliverySuiteDeps(
      step: diagnostics.notifyStep,
      sendTest: push.sendTest,
      received: push.received,
      bell: social.watchNotifications(),
      subscribe: push.subscribeToTopic,
      unsubscribe: push.unsubscribeFromTopic,
    ),
  );
});
