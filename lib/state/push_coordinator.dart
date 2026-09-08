import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/dev_error_sink.dart';
import '../router/app_router.dart';
import 'providers.dart';
import 'session.dart';

/// Ties push to the session.
///
/// A member's phone is registered once per sign-in and its topics follow the
/// facts that decide an announcement's audience (seller, directory). A tapped
/// banner becomes a route. Watched once from the app widget; there is no UI.
final pushCoordinatorProvider = Provider<void>((ref) {
  final push = ref.watch(pushServiceProvider);
  String? started;

  ref.listen<AsyncValue<Session>>(sessionProvider, (_, next) {
    final session = next.value;
    if (session is! MemberSession) return;
    if (started != session.uid) {
      started = session.uid;
      unawaited(
        push.start(session.uid).catchError((Object error, StackTrace stack) {
          DevErrorSink.report(error, stack, 'push start');
        }),
      );
    }
    unawaited(
      push
          .setTopics(
            seller: session.isSeller,
            directory: ref.read(directoryLinkProvider).value?.linked ?? false,
          )
          .catchError((Object _) {}),
    );
  }, fireImmediately: true);

  // The directory link can land after sign-in; the topic follows it.
  ref.listen(directoryLinkProvider, (_, next) {
    final session = ref.read(sessionProvider).value;
    if (session is! MemberSession) return;
    unawaited(
      push
          .setTopics(
            seller: session.isSeller,
            directory: next.value?.linked ?? false,
          )
          .catchError((Object _) {}),
    );
  });

  final sub = push.openedRoutes.listen((route) {
    ref.read(routerProvider).go(route);
  });
  ref.onDispose(sub.cancel);
});
