import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/platform_info.dart';

/// Every screen opened and every action taken, sent to the backend in
/// batches and downloadable as JSON from the admin website (Grace,
/// 2026-11-04: "add analytics to the app that record all user events and
/// are downloadable as a JSON from the admin portal. Add the user's id so we
/// can track them across events").
///
/// The member's id is attached by the backend from their sign-in, never
/// taken from the phone, so an event cannot be put in somebody else's name.
/// A guest has no id; their events carry a device id instead, which stays
/// the same after they sign in, so a visit can be followed into an account.
///
/// Recording never fails loudly and never waits: an event is added to a
/// list in memory and the list is sent every [flushEvery], when it reaches
/// [batchSize], and when the app goes to the background.
abstract final class Analytics {
  static const batchSize = 40;
  static const flushEvery = Duration(seconds: 15);

  /// A visit ends after this long in the background.
  static const sessionGap = Duration(minutes: 30);

  static AnalyticsSink? _sink;
  static final List<AnalyticsEvent> _queue = [];
  static Timer? _timer;
  static String _deviceId = '';
  static String _sessionId = _newId();
  static String _appVersion = '';
  static DateTime? _backgroundedAt;
  static String _lastPath = '';
  static _Lifecycle? _lifecycle;
  static GoRouter? _router;

  /// Every event recorded since start, newest last: what tests read, and
  /// the most recent few for anyone debugging on a phone.
  static final List<AnalyticsEvent> recent = [];
  static const _recentMax = 200;

  /// Starts sending. Without a sink (a fixture build, a test) events are
  /// only kept in [recent].
  static Future<void> start({AnalyticsSink? sink}) async {
    _sink = sink;
    try {
      final prefs = await SharedPreferences.getInstance();
      _deviceId = prefs.getString(_deviceKey) ?? '';
      if (_deviceId.isEmpty) {
        _deviceId = _newId();
        await prefs.setString(_deviceKey, _deviceId);
      }
    } catch (_) {
      _deviceId = _deviceId.isEmpty ? _newId() : _deviceId;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      // Left empty; the event is still worth having.
    }
    _lifecycle ??= _Lifecycle()..attach();
    _timer?.cancel();
    _timer = Timer.periodic(flushEvery, (_) => flush());
    track('app_open');
  }

  static const _deviceKey = 'lbm.analytics.deviceId';

  /// Records [name] with [props]. Names are snake_case verbs, e.g.
  /// `add_to_cart`; props are small facts (ids, counts, words searched).
  static void track(String name, [Map<String, Object?> props = const {}]) {
    final event = AnalyticsEvent(
      name: name,
      props: {
        for (final e in props.entries)
          if (e.value != null) e.key: e.value,
      },
      at: DateTime.now().toUtc(),
      sessionId: _sessionId,
      deviceId: _deviceId,
      platform: platformName,
      appVersion: _appVersion,
      path: _lastPath,
    );
    recent.add(event);
    if (recent.length > _recentMax) recent.removeAt(0);
    if (_sink == null) return;
    _queue.add(event);
    if (_queue.length >= batchSize) flush();
  }

  /// Sends what is waiting. A batch that fails goes back on the front of
  /// the list for the next try, up to a limit, so a phone offline for a day
  /// does not grow without end.
  static Future<void> flush() async {
    final sink = _sink;
    if (sink == null || _queue.isEmpty) return;
    final batch = _queue.take(batchSize).toList();
    _queue.removeRange(0, batch.length);
    try {
      await sink(batch);
    } catch (_) {
      _queue.insertAll(0, batch);
      if (_queue.length > 1000) _queue.removeRange(1000, _queue.length);
    }
  }

  /// Every screen opened, from the router. Safe to call on every build.
  static void attachRouter(GoRouter router) {
    if (identical(_router, router)) return;
    _router?.routerDelegate.removeListener(_onRoute);
    _router = router;
    router.routerDelegate.addListener(_onRoute);
    _onRoute();
  }

  static void _onRoute() {
    final config = _router?.routerDelegate.currentConfiguration;
    if (config == null || config.isEmpty) return;
    // Where the router settled, after any redirect, and the screen pushed
    // on top when there is one: the address bar says "/" while the app
    // has already gone on to the feed.
    final top = config.last;
    final uri = top is ImperativeRouteMatch ? top.matches.uri : config.uri;
    final path = uri.path.isEmpty ? '/' : uri.path;
    if (path == _lastPath) return;
    _lastPath = path;
    track('screen_view', {'screen': path, 'q': ?uri.queryParameters['q']});
  }

  static void _resumed() {
    final away = _backgroundedAt;
    // Back from a glance at the control centre is not a return.
    if (away == null) return;
    _backgroundedAt = null;
    if (DateTime.now().difference(away) >= sessionGap) {
      _sessionId = _newId();
      track('session_start');
    }
    track('app_resume');
  }

  static void _paused() {
    // A phone reports hidden and then paused; one is enough.
    if (_backgroundedAt != null) return;
    _backgroundedAt = DateTime.now();
    track('app_background');
    flush();
  }

  /// For tests: forget everything recorded.
  @visibleForTesting
  static void reset() {
    recent.clear();
    _queue.clear();
    _lastPath = '';
  }

  static final _random = Random.secure();
  static String _newId() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Sends one batch. The live one calls the backend; see
/// `data/firebase/firebase_analytics_sink.dart`.
typedef AnalyticsSink = Future<void> Function(List<AnalyticsEvent> batch);

@immutable
class AnalyticsEvent {
  const AnalyticsEvent({
    required this.name,
    required this.props,
    required this.at,
    required this.sessionId,
    required this.deviceId,
    required this.platform,
    required this.appVersion,
    required this.path,
  });

  final String name;
  final Map<String, Object?> props;
  final DateTime at;
  final String sessionId;
  final String deviceId;
  final String platform;
  final String appVersion;

  /// The screen it happened on.
  final String path;

  Map<String, Object?> toJson() => {
    'name': name,
    'props': props,
    'at': at.toIso8601String(),
    'sessionId': sessionId,
    'deviceId': deviceId,
    'platform': platform,
    'appVersion': appVersion,
    'path': path,
  };
}

class _Lifecycle with WidgetsBindingObserver {
  void attach() => WidgetsBinding.instance.addObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        Analytics._resumed();
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        Analytics._paused();
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }
}
