import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../push/push_service.dart';
import 'firestore_errors.dart';

/// The Android channel every push lands in. Its id is also in the manifest
/// meta-data and in the backend's Android payload; the three must agree.
const kPushChannelId = 'lbm_default';

/// A data-only message arriving while the app is in the background. There
/// is nothing to do: the backend always sends a notification payload, which
/// Android and iOS display on their own. Registered from `main` on live
/// builds so the isolate exists; must be top-level.
@pragma('vm:entry-point')
Future<void> lbmBackgroundMessageHandler(RemoteMessage message) async {}

class FirebasePushService implements PushService {
  FirebasePushService({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? local,
  }) : _db = firestore,
       _functions = functions,
       _messaging = messaging ?? FirebaseMessaging.instance,
       _local = local ?? FlutterLocalNotificationsPlugin();

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _local;

  final _opened = StreamController<String>.broadcast();
  final _subs = <StreamSubscription<dynamic>>[];
  String? _uid;
  String? _token;
  bool _localReady = false;
  bool? _seller;
  bool? _directory;
  bool _onAll = false;

  static const _channel = AndroidNotificationChannel(
    kPushChannelId,
    'Little Blue Market',
    description: 'Mentions, replies, reviews, new products and announcements.',
    importance: Importance.high,
  );

  @override
  Stream<String> get openedRoutes => _opened.stream;

  PushPermission _map(AuthorizationStatus status) => switch (status) {
    AuthorizationStatus.authorized ||
    AuthorizationStatus.provisional => PushPermission.granted,
    AuthorizationStatus.denied ||
    AuthorizationStatus.deniedPermanently => PushPermission.denied,
    AuthorizationStatus.notDetermined => PushPermission.notDetermined,
  };

  @override
  Future<PushPermission> permissionStatus() async {
    try {
      final settings = await _messaging.getNotificationSettings();
      return _map(settings.authorizationStatus);
    } catch (_) {
      return PushPermission.unsupported;
    }
  }

  @override
  Future<PushPermission> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final result = _map(settings.authorizationStatus);
      // A granted permission is worth a token straight away, so the test
      // button works without a restart.
      final uid = _uid;
      if (result == PushPermission.granted && uid != null) {
        await _registerToken(uid);
      }
      return result;
    } catch (_) {
      return PushPermission.unsupported;
    }
  }

  Future<void> _initLocal() async {
    if (_localReady) return;
    _localReady = true;
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_lbm'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final route = response.payload;
        if (route != null && route.isNotEmpty) _opened.add(route);
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
    // iOS shows nothing for a foreground push unless asked to.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  String get _platform => kIsWeb
      ? 'web'
      : Platform.isIOS
      ? 'ios'
      : Platform.isAndroid
      ? 'android'
      : Platform.operatingSystem;

  Future<void> _registerToken(String uid) async {
    String? token;
    try {
      // On iOS this fails until APNs has handed over its token; the refresh
      // stream delivers it a moment later.
      token = await _messaging.getToken();
    } catch (_) {
      return;
    }
    if (token == null || token.isEmpty) return;
    await _writeToken(uid, token);
  }

  Future<void> _writeToken(String uid, String token) async {
    final previous = _token;
    _token = token;
    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('devices')
        .doc(token);
    await guardFirestore(() async {
      final existing = await ref.get();
      await ref.set({
        'token': token,
        'platform': _platform,
        if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (previous != null && previous != token) {
        await ref.parent.doc(previous).delete();
      }
    }, operation: 'firestore users/{uid}/devices');
  }

  void _showForeground(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    // iOS presents it itself (see the presentation options above).
    if (!kIsWeb && Platform.isIOS) return;
    unawaited(
      _local.show(
        id: message.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            kPushChannelId,
            'Little Blue Market',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_stat_lbm',
          ),
        ),
        payload: message.data['route']?.toString(),
      ),
    );
  }

  void _routeFrom(RemoteMessage? message) {
    final route = message?.data['route']?.toString();
    if (route != null && route.isNotEmpty) _opened.add(route);
  }

  @override
  Future<void> start(String uid) async {
    if (_uid == uid) return;
    await _cancel();
    _uid = uid;
    try {
      await _initLocal();
    } catch (_) {
      // A phone that cannot show local banners still gets background ones.
    }
    if (await permissionStatus() == PushPermission.granted) {
      await _registerToken(uid);
    }
    _subs.add(
      _messaging.onTokenRefresh.listen((token) {
        final current = _uid;
        if (current != null) unawaited(_writeToken(current, token));
      }),
    );
    _subs.add(FirebaseMessaging.onMessage.listen(_showForeground));
    _subs.add(FirebaseMessaging.onMessageOpenedApp.listen(_routeFrom));
    // A cold start from a tapped banner.
    unawaited(_messaging.getInitialMessage().then(_routeFrom));
    // A cold start from a tapped *local* banner (foreground push, then killed).
    unawaited(
      _local.getNotificationAppLaunchDetails().then((details) {
        final route = details?.notificationResponse?.payload;
        if (details?.didNotificationLaunchApp == true &&
            route != null &&
            route.isNotEmpty) {
          _opened.add(route);
        }
      }),
    );
  }

  Future<void> _cancel() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
  }

  @override
  Future<void> stop(String uid) async {
    await _cancel();
    final token = _token;
    _uid = null;
    _token = null;
    _seller = null;
    _directory = null;
    if (token == null) return;
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(token)
          .delete();
    } catch (_) {
      // A stale document is pruned by the first failed send.
    }
    // The next person on this phone gets a token of their own.
    try {
      await _messaging.deleteToken();
    } catch (_) {}
    if (_onAll) {
      _onAll = false;
      for (final topic in ['all', 'sellers', 'directory']) {
        try {
          await _messaging.unsubscribeFromTopic(topic);
        } catch (_) {}
      }
    }
  }

  @override
  Future<void> setTopics({
    required bool seller,
    required bool directory,
  }) async {
    Future<void> set(String topic, bool on, bool? was) async {
      if (was == on) return;
      try {
        if (on) {
          await _messaging.subscribeToTopic(topic);
        } else {
          await _messaging.unsubscribeFromTopic(topic);
        }
      } catch (_) {
        // Retried on the next session change.
      }
    }

    await set('all', true, _onAll ? true : null);
    _onAll = true;
    await set('sellers', seller, _seller);
    _seller = seller;
    await set('directory', directory, _directory);
    _directory = directory;
  }

  @override
  Future<void> sendTest() => guardFirestore(() async {
    await _functions
        .httpsCallable('pushTestMe')
        .call<Map<String, dynamic>>(const {});
  }, operation: 'callable pushTestMe');
}
