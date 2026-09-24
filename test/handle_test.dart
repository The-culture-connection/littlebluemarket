import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/fixtures/fixture_data.dart';
import 'package:little_blue_market/data/fixtures/fixture_repositories.dart';
import 'package:little_blue_market/data/fixtures/fixture_store.dart';
import 'package:little_blue_market/data/repositories/repositories.dart';

/// Setting a name and a handle on a profile that has neither.
///
/// 2026-09-24: a member whose profile had been cleared tried to put her name
/// back and was told "That handle is taken". She had not typed a handle at
/// all: `handleAvailable('')` answers false, quite reasonably, and the empty
/// string was being handed to it as though it were a request. Unreachable
/// while everybody had a handle seeded into the field, and reachable the
/// moment one was blank.
void main() {
  late FixtureBackend backend;
  late FixtureProfileRepository profiles;

  setUp(() {
    backend = FixtureBackend(store: FixtureStore());
    profiles = FixtureProfileRepository(backend);
  });
  tearDown(() => backend.store.dispose());

  test('an empty handle leaves the one you have alone', () async {
    final before = await profiles.person(Fx.meId);
    await profiles.updateProfile(const ProfileEdit(name: 'Erin', handle: ''));
    final after = await profiles.person(Fx.meId);
    expect(after.name, 'Erin');
    expect(after.handle, before.handle, reason: 'not blanked, not refused');
  });

  test('a bare @ is not a handle either', () async {
    await profiles.updateProfile(const ProfileEdit(handle: '@'));
    final after = await profiles.person(Fx.meId);
    expect(after.handle, isNot('@'));
  });

  test('a handle nobody has is accepted', () async {
    await profiles.updateProfile(const ProfileEdit(handle: '@erinrf'));
    expect((await profiles.person(Fx.meId)).handle, '@erinrf');
  });

  test('a handle somebody else has is refused, and named', () async {
    // The message has to say which handle, or there is nothing to act on.
    final taken = Fx.people.values.firstWhere((p) => p.id != Fx.meId);
    await expectLater(
      profiles.updateProfile(ProfileEdit(handle: taken.handle)),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.message,
          'message',
          allOf(contains(taken.handle), contains('Try another')),
        ),
      ),
    );
  });

  test('keeping your own handle is not a collision', () async {
    final me = await profiles.person(Fx.meId);
    await profiles.updateProfile(ProfileEdit(handle: me.handle, name: 'Erin'));
    expect((await profiles.person(Fx.meId)).name, 'Erin');
  });
}
