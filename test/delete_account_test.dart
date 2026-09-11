import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/fixtures/fixture_repositories.dart';
import 'package:little_blue_market/data/fixtures/fixture_store.dart';
import 'package:little_blue_market/data/repositories/repositories.dart';
import 'package:little_blue_market/models/models.dart';

/// Asking for an account or its data to be removed. The page that files these
/// is reachable by anyone, so the request has to stand on its own.
void main() {
  late FixtureBackend backend;
  late FixtureAccountRepository accounts;

  setUp(() {
    backend = FixtureBackend(store: FixtureStore());
    accounts = FixtureAccountRepository(backend);
  });
  tearDown(() => backend.store.dispose());

  test('a request is filed, and a second one does not duplicate it', () async {
    await accounts.requestDeletion(
      const NewDeletionRequest(
        email: 'Maya@Example.com',
        scope: DeletionScope.account,
        note: 'Please remove everything',
      ),
    );
    var all = await accounts.watchDeletionRequests().first;
    expect(all, hasLength(1));
    expect(all.first.email, 'maya@example.com', reason: 'lowercased');
    expect(all.first.scope, DeletionScope.account);
    expect(all.first.isOpen, isTrue);

    await accounts.requestDeletion(
      const NewDeletionRequest(
        email: 'maya@example.com',
        scope: DeletionScope.data,
      ),
    );
    all = await accounts.watchDeletionRequests().first;
    expect(all, hasLength(1), reason: 'one open request per address');
  });

  test('a request without a usable address is refused', () {
    expect(
      () => accounts.requestDeletion(
        const NewDeletionRequest(
          email: 'not an address',
          scope: DeletionScope.account,
        ),
      ),
      throwsA(isA<ValidationException>()),
    );
  });

  test('closing one takes it off the open list', () async {
    await accounts.requestDeletion(
      const NewDeletionRequest(
        email: 'dee@example.com',
        scope: DeletionScope.data,
      ),
    );
    final open = await accounts.watchDeletionRequests().first;
    await accounts.setDeletionStatus(open.first.id, DeletionStatus.done);
    final after = await accounts.watchDeletionRequests().first;
    expect(after.first.isOpen, isFalse);
    expect(after.first.status, DeletionStatus.done);
  });

  test('both answers are offered, and the scope survives a round trip', () {
    expect(DeletionScope.values, hasLength(2));
    expect(DeletionScope.fromValue('data'), DeletionScope.data);
    expect(DeletionScope.fromValue('anything else'), DeletionScope.account);
  });
}
