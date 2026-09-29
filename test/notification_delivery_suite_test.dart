import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/push/push_service.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/state/notification_delivery_suite.dart';

/// The Diagnostics delivery suite has one job: never say "delivered" when
/// it was not. These tests hand it a backend that follows the real rules,
/// then break one thing at a time and check that the suite notices.

/// A stand-in for the backend and the phone, following the real rules, with
/// switches that break them.
class _World {
  _World({
    this.channelWorks = true,
    this.rateLimitWorks = true,
    this.quietWorks = true,
    this.bellRowsWritten = true,
    this.mentionCarriesNonce = true,
    this.announcementArrives = true,
    this.heldPushArrivesLate = false,
  });

  final bool channelWorks;
  final bool rateLimitWorks;
  final bool quietWorks;
  final bool bellRowsWritten;
  final bool mentionCarriesNonce;
  final bool announcementArrives;
  final bool heldPushArrivesLate;

  final pushes = StreamController<ReceivedPush>.broadcast();
  final bell = StreamController<List<AppNotification>>.broadcast();
  final _rows = <AppNotification>[];
  final steps = <String>[];
  final topics = <String>[];

  bool _pushedRecently = false;
  bool _quiet = false;
  bool _digestWaiting = false;

  void _push(String title, String body, {String type = 'x'}) {
    Timer(const Duration(milliseconds: 20), () {
      pushes.add(
        ReceivedPush(title: title, body: body, type: type, at: DateTime.now()),
      );
    });
  }

  void _row(String text) {
    if (!bellRowsWritten) return;
    _rows.add(
      AppNotification(
        id: 'n${_rows.length}',
        kind: NotificationKind.comment,
        postId: '',
        fromUid: 'diag-bot',
        text: text,
        createdAt: DateTime.now(),
      ),
    );
    Timer(const Duration(milliseconds: 10), () => bell.add([..._rows]));
  }

  /// Held pushes that will turn up late: released when the next step
  /// starts, which is after their own check has passed and before the run
  /// ends, whatever the machine's speed.
  final _late = <String>[];

  Future<Map<String, Object?>> step(String step, String nonce) async {
    steps.add(step);
    for (final body in _late) {
      _push('Diagnostics bot commented on your post', body, type: 'comment');
    }
    _late.clear();
    final text = 'Diagnostics $nonce';
    switch (step) {
      case 'setup':
        return {'topic': 'diag_me'};
      case 'comment':
        _row(text);
        final limited = rateLimitWorks && _pushedRecently;
        final hushed = quietWorks && _quiet;
        if (!limited && !hushed) {
          _push('Diagnostics bot commented on your post', text);
          _pushedRecently = true;
        } else if (heldPushArrivesLate) {
          _late.add(text);
        }
      case 'mention':
        _row(text);
        _push(
          'Diagnostics bot mentioned you',
          mentionCarriesNonce ? text : 'Diagnostics something else',
        );
      case 'dm':
        _push('Diagnostics bot', text, type: 'newMessage');
      case 'quietOn':
        _quiet = true;
        _pushedRecently = false;
      case 'quietOff':
        _quiet = false;
        _pushedRecently = false;
      case 'announcement':
        if (announcementArrives) {
          _push('Diagnostics announcement', text, type: 'announcement');
        }
      case 'forumReply':
        _row(text);
        _digestWaiting = true;
      case 'digestNow':
        if (_digestWaiting) {
          _push(
            'New in your forums',
            '1 new reply in 1 thread',
            type: 'forumReply',
          );
          return {'outcome': 'sent'};
        }
        return {'outcome': 'nothing waiting'};
    }
    return {};
  }

  Future<void> sendTest() async {
    if (channelWorks) {
      _push(
        'Little Blue Market',
        'This phone is set up for notifications.',
        type: 'test',
      );
    }
  }

  NotificationDeliverySuite suite() => NotificationDeliverySuite(
    DeliverySuiteDeps(
      step: step,
      sendTest: sendTest,
      received: pushes.stream,
      bell: bell.stream,
      subscribe: (t) async => topics.add('+$t'),
      unsubscribe: (t) async => topics.add('-$t'),
      arrive: const Duration(milliseconds: 300),
      silence: const Duration(milliseconds: 150),
    ),
  );
}

Map<String, CheckStatus> _byName(List<CheckResult> results) => {
  for (final r in results) r.name: r.status,
};

void main() {
  test('rules working: every check passes, and it cleans up', () async {
    final world = _World();
    final results = await world.suite().run();

    expect(
      results.where((r) => r.status != CheckStatus.pass).map((r) => r.line),
      isEmpty,
    );
    expect(results, hasLength(10));
    expect(world.steps.last, 'restore');
    expect(world.topics, ['+diag_me', '-diag_me']);
  });

  test('a dead channel stops the run INCONCLUSIVE, never PASS', () async {
    final world = _World(channelWorks: false);
    final results = await world.suite().run();

    expect(results, hasLength(1));
    expect(results.single.status, CheckStatus.inconclusive);
    // It still puts things back.
    expect(world.steps.last, 'restore');
  });

  test('a rate limit that does not hold fails, with what arrived', () async {
    final results = await _World(rateLimitWorks: false).suite().run();
    final byName = _byName(results);

    expect(byName['Rate limit: a second comment is held'], CheckStatus.fail);
    expect(
      results.firstWhere((r) => r.name.startsWith('Rate limit')).detail,
      contains('pushed anyway'),
    );
  });

  test('quiet hours that do not hold fail', () async {
    final results = await _World(quietWorks: false).suite().run();
    expect(
      _byName(results)['Quiet hours: a comment is held'],
      CheckStatus.fail,
    );
  });

  test(
    'silence without a bell row is not a pass: the trigger may be dead',
    () async {
      final results = await _World(bellRowsWritten: false).suite().run();
      final held = results.where(
        (r) => r.name.contains('held') || r.name.contains('not pushed'),
      );

      expect(held, isNotEmpty);
      for (final r in held) {
        expect(r.status, CheckStatus.fail, reason: r.name);
        expect(r.detail, contains('no bell row'));
      }
    },
  );

  test('a push that does not carry its own nonce does not count', () async {
    final results = await _World(mentionCarriesNonce: false).suite().run();
    expect(
      _byName(results)['A mention gets through the rate limit'],
      CheckStatus.fail,
    );
  });

  test('a held push that turns up late fails the run at the end', () async {
    final results = await _World(heldPushArrivesLate: true).suite().run();
    expect(results.where((r) => r.name.endsWith('(late)')), isNotEmpty);
    expect(
      results
          .where((r) => r.name.endsWith('(late)'))
          .every((r) => r.status == CheckStatus.fail),
      isTrue,
    );
  });

  test('an announcement that never arrives fails', () async {
    final results = await _World(announcementArrives: false).suite().run();
    expect(
      _byName(
        results,
      )['An announcement arrives (private topic), even in quiet hours'],
      CheckStatus.fail,
    );
  });

  test(
    'a backend that refuses (not an admin) is reported, and cleaned up',
    () async {
      final world = _World();
      final suite = NotificationDeliverySuite(
        DeliverySuiteDeps(
          step: (step, nonce) async {
            world.steps.add(step);
            if (step == 'restore') return {};
            throw Exception('Admins only.');
          },
          sendTest: world.sendTest,
          received: world.pushes.stream,
          bell: world.bell.stream,
          subscribe: (_) async {},
          unsubscribe: (_) async {},
          arrive: const Duration(milliseconds: 300),
          silence: const Duration(milliseconds: 150),
        ),
      );
      final results = await suite.run();

      expect(results.single.status, CheckStatus.fail);
      expect(results.single.detail, contains('Admins only'));
      expect(world.steps.last, 'restore');
    },
  );
}
