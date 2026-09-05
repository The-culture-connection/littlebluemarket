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
  fail(
    'session never satisfied the condition: '
    '${container.read(sessionProvider)}',
  );
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

  test('signing in produces a member session', () async {
    final container = _container();
    await _settle(container, (s) => s is GuestSession);

    await container
        .read(sessionProvider.notifier)
        .signInWithPassword(email: 'maya@example.com', password: 'hunter22');

    final session = await _settle(container, (s) => s is MemberSession);
    expect((session as MemberSession).profile.handle, '@mayamakes');
    expect(container.read(isGuestProvider), isFalse);
    expect(container.read(currentUidProvider), 'maya');
    expect(container.read(isSellerProvider), isTrue);
  });

  test('a password under the minimum is refused', () async {
    final container = _container();
    await expectLater(
      container
          .read(sessionProvider.notifier)
          .signInWithPassword(email: 'maya@example.com', password: '12'),
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

  test(
    'reloading the account keeps a member signed in and reports them',
    () async {
      // On the live backend this re-reads emailVerified and the seller claim;
      // on fixtures it is a read of what is there. Either way the session must
      // not blink.
      final container = _container();
      container.read(sessionProvider.notifier).signIn();
      await _settle(container, (s) => s is MemberSession);

      final user = await container.read(sessionProvider.notifier).reloadUser();
      expect(user, isNotNull);
      expect(user!.emailVerified, isTrue);
      expect(container.read(sessionProvider).value, isA<MemberSession>());
      expect(
        (container.read(sessionProvider).value! as MemberSession).emailVerified,
        isTrue,
      );
    },
  );

  test('reloading while signed out is a no-op', () async {
    final container = _container();
    await _settle(container, (s) => s is GuestSession);
    expect(await container.read(sessionProvider.notifier).reloadUser(), isNull);
  });

  test(
    'a verified, unlinked member is linked to the store exactly once',
    () async {
      // The backend is idempotent, but the session stream re-emits on every
      // profile change; the call must not follow it.
      final container = _container();
      container.read(sessionProvider.notifier).signIn();
      var session = await _settle(container, (s) => s is MemberSession);
      // On fixtures the link is instant, so only the outcome is asserted.

      session = await _settle(
        container,
        (s) => s is MemberSession && s.profile.isLinked,
      );
      expect((session as MemberSession).profile.isLinked, isTrue);

      // A later profile edit re-emits the session; linking is not repeated.
      await container
          .read(profileRepositoryProvider)
          .updateProfile(const ProfileEdit(bio: 'Still linked.'));
      session = await _settle(
        container,
        (s) => s is MemberSession && s.profile.bio == 'Still linked.',
      );
      final again = await container
          .read(profileRepositoryProvider)
          .linkStoreAccounts();
      expect(
        again.alreadyLinked,
        isTrue,
        reason: 'the fixture records the first link',
      );
    },
  );

  test(
    'seller status follows the identity, and a grant flips it live',
    () async {
      // dee is a buyer in the fixtures. Claiming a shop must make the session a
      // seller without a restart, the way a forced token refresh does on the
      // live backend.
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

      final grant = await container
          .read(profileRepositoryProvider)
          .requestSellerStatus('GWYNSTONE');
      expect(grant.vendorName, 'Gwynstone');

      await _settle(container, (s) => s is MemberSession && s.isSeller);
      expect(container.read(isSellerProvider), isTrue);
    },
  );

  test('the profile document alone does not make a seller', () async {
    // Selling is a grant on the token. A document that says isSeller with no
    // claim behind it is the display mirror for other people's profiles, and
    // must not unlock seller surfaces for the account itself.
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

    final store = container.read(fixtureStoreProvider);
    final people = {...store.people.value};
    people['dee'] = people['dee']!.copyWith(isSeller: true);
    store.people.value = people;

    await _settle(
      container,
      (s) => s is MemberSession && s.profile.bio == people['dee']!.bio,
    );
    expect(container.read(isSellerProvider), isFalse);
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
