import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/fixtures/fixture_repositories.dart';
import 'package:little_blue_market/data/fixtures/fixture_store.dart';
import 'package:little_blue_market/models/models.dart';

/// The initiative hashtags on a profile are tappable chips that run a search.
/// Before this, only the catalog was searched, so tapping one found nothing.
void main() {
  late FixtureBackend backend;

  setUp(() => backend = FixtureBackend(store: FixtureStore()));
  tearDown(() => backend.store.dispose());

  test(
    'a hashtag search finds the people who carry it on their profile',
    () async {
      final search = FixtureSearchRepository(backend);
      final results = await search.search(
        const SearchFilters(query: '#LGBTQOwned', scope: SearchScope.hashtags),
      );
      // rae carries it; maya does not.
      expect(results.sellers.map((p) => p.id), contains('rae'));
      expect(results.sellers.map((p) => p.id), isNot(contains('maya')));
    },
  );

  test('the case people type does not matter', () async {
    final search = FixtureSearchRepository(backend);
    final results = await search.search(
      const SearchFilters(query: '#lgbtqowned', scope: SearchScope.hashtags),
    );
    expect(results.sellers.map((p) => p.id), contains('rae'));
  });

  test('the lowercase mirror a profile stores', () {
    expect(lowerTags(['#WomanOwned', '#BIPOCOwned']), [
      '#womanowned',
      '#bipocowned',
    ]);
    expect(lowerTags(['WomanOwned', '#womanowned']), ['#womanowned']);
    expect(lowerTags(const []), isEmpty);
  });
}
