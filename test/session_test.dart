import 'dart:ui' show Brightness;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/auth/auth_service.dart';
import 'package:little_blue_market/data/providers.dart';
import 'package:little_blue_market/data/repositories/repositories.dart';
import 'package:little_blue_market/state/session.dart';

/// Waits until [test] holds for the session, so these do not depend on how many
/// microtasks the auth and profile streams happen to take.
Future<Session> _settle(
  ProviderContainer container,
  bool Function(Session) test,
) async {
  for (var i = 0; i < 50; i++) {
    final session = container.read(sessionProvider).value;
    if (session != null && test(session)) return session;
    await Future<void>.delayed(Duration.zero);
  }
  fail('session never satisfied the condition: '
      '${container.read(sessionProvider)}');
}

ProviderContainer _container() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  // Keep the session alive for the whole test; nothing is watching it here.
  container.listen(sessionProvider, (_, _) {});
  return container;
}

void main() {
  test('starts as a guest', () async {
    final container = _container();
    await _settle(container, (s) => s is GuestSession);
    expect(container.read(isGuestProvider), isTrue);
    expect(container.read(meProvider), isNull);
  });

  test('a confirmed code produces a member session', () async {
    final container = _container();
    await _settle(container, (s) => s is GuestSession);

    await container
        .read(sessionProvider.notifier)
        .confirmCode(email: 'maya@example.com', code: '123456');

    final session = await _settle(container, (s) => s is MemberSession);
    expect((session as MemberSession).profile.handle, '@mayamakes');
    expect(container.read(isGuestProvider), isFalse);
    expect(container.read(currentUidProvider), 'maya');
    expect(container.read(isSellerProvider), isTrue);
  });

  test('a bad code is refused', () async {
    final container = _container();
    await expectLater(
      container
          .read(sessionProvider.notifier)
          .confirmCode(email: 'maya@example.com', code: '12'),
      throwsA(isA<ValidationException>()),
    );
    expect(container.read(isGuestProvider), isTrue);
  });

  test('a guest still gets a uid, so a pre-signup cart can survive', () async {
    final container = _container();
    await container.read(sessionProvider.notifier).continueAsGuest();
    final session = await _settle(
      container,
      (s) => s is GuestSession && s.uid != null,
    );
    expect(session.uid, isNotNull);
    expect(container.read(isGuestProvider), isTrue);
  });

  test('signing out returns to guest', () async {
    final container = _container();
    container.read(sessionProvider.notifier).signIn();
    await _settle(container, (s) => s is MemberSession);

    await container.read(sessionProvider.notifier).signOut();
    await _settle(container, (s) => s is GuestSession);
    expect(container.read(meProvider), isNull);
  });

  test('a profile edit reaches the session', () async {
    final container = _container();
    container.read(sessionProvider.notifier).signIn();
    await _settle(container, (s) => s is MemberSession);

    await container
        .read(profileRepositoryProvider)
        .updateProfile(const ProfileEdit(bio: 'Edited.'));

    // The session watches the profile rather than fetching it once, so an edit
    // made on one screen reaches every screen showing the current user.
    final session = await _settle(
      container,
      (s) => s is MemberSession && s.profile.bio == 'Edited.',
    );
    expect((session as MemberSession).profile.bio, 'Edited.');
  });

  test('a buyer is not a seller', () async {
    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWith((ref) {
          final service = FixtureAuthService(demoUid: 'dee');
          ref.onDispose(service.dispose);
          return service;
        }),
      ],
    );
    addTearDown(container.dispose);
    container.listen(sessionProvider, (_, _) {});

    container.read(sessionProvider.notifier).signIn();
    await _settle(container, (s) => s is MemberSession);

    expect(container.read(isSellerProvider), isFalse);
    expect(container.read(isGuestProvider), isFalse);
  });

  test('the theme override is not part of the session', () {
    // It used to be, which made the router re-run its redirect on every
    // dark-mode toggle.
    final container = _container();
    expect(container.read(themeModeProvider), isNull);
    container.read(themeModeProvider.notifier).set(Brightness.dark);
    expect(container.read(themeModeProvider), Brightness.dark);
  });
}
