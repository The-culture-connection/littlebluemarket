import 'dart:async';

import '../push/push_service.dart';

/// Push on the demo backend: the permission flips when asked, the test
/// button "sends", and nothing ever arrives. Enough for every screen to
/// render and every button to answer.
class FixturePushService implements PushService {
  PushPermission _permission = PushPermission.notDetermined;
  final _opened = StreamController<String>.broadcast();

  @override
  Stream<String> get openedRoutes => _opened.stream;

  @override
  Future<PushPermission> permissionStatus() async => _permission;

  @override
  Future<PushPermission> requestPermission() async =>
      _permission = PushPermission.granted;

  @override
  Future<void> start(String uid) async {}

  @override
  Future<void> stop(String uid) async {}

  @override
  Future<void> setTopics({required bool seller, required bool directory}) async {}

  @override
  Future<void> sendTest() async {}
}
