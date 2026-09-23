import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/fixtures/fixture_data.dart';
import 'package:little_blue_market/data/fixtures/fixture_repositories.dart';
import 'package:little_blue_market/data/fixtures/fixture_store.dart';
import 'package:little_blue_market/data/repositories/repositories.dart';

/// Save for later (Grace's testers, 2026-09-23): a second shelf on the cart,
/// for the thing somebody is not ready to buy and not ready to lose.
void main() {
  late FixtureBackend backend;
  late FixtureCommerceRepository commerce;

  setUp(() {
    backend = FixtureBackend(store: FixtureStore());
    commerce = FixtureCommerceRepository(backend);
  });
  tearDown(() => backend.store.dispose());

  String firstProductId() => Fx.products.keys.first;

  test('a saved line leaves the cart and the total', () async {
    final id = firstProductId();
    var cart = await commerce.addLine(productId: id);
    final line = cart.lines.single;
    final wasSubtotal = cart.subtotalCents;
    expect(wasSubtotal, greaterThan(0));

    cart = await commerce.saveForLater(line.id);
    expect(cart.lines, isEmpty);
    expect(cart.saved.single.productId, id);
    expect(cart.subtotalCents, 0, reason: 'saved is in no total');
    expect(cart.itemCount, 0, reason: 'and in no badge');
  });

  test('a cart with nothing to buy but something saved is not bare', () async {
    var cart = await commerce.addLine(productId: firstProductId());
    cart = await commerce.saveForLater(cart.lines.single.id);
    expect(cart.isEmpty, isTrue, reason: 'nothing to check out with');
    expect(cart.isBare, isFalse, reason: 'but the screen is not empty');
  });

  test('moving it back restores the quantity, repriced', () async {
    final id = firstProductId();
    var cart = await commerce.addLine(productId: id, quantity: 3);
    final lineId = cart.lines.single.id;
    cart = await commerce.saveForLater(lineId);
    cart = await commerce.moveToCart(cart.saved.single.id);

    expect(cart.saved, isEmpty);
    expect(cart.lines.single.quantity, 3);
    // The price came back off the listing, not off the saved copy.
    expect(cart.lines.single.unitPriceCents, Fx.products[id]!.priceCents);
  });

  test('saving the same line twice leaves one entry', () async {
    final id = firstProductId();
    var cart = await commerce.addLine(productId: id);
    final lineId = cart.lines.single.id;
    cart = await commerce.saveForLater(lineId);
    cart = await commerce.moveToCart(cart.saved.single.id);
    cart = await commerce.saveForLater(cart.lines.single.id);
    expect(cart.saved.length, 1);
  });

  test('removing a saved line takes it off the shelf, not the cart', () async {
    var cart = await commerce.addLine(productId: firstProductId());
    cart = await commerce.saveForLater(cart.lines.single.id);
    cart = await commerce.removeSaved(cart.saved.single.id);
    expect(cart.saved, isEmpty);
    expect(cart.isBare, isTrue);
  });

  test('a line that is not there is an error, not a silent no-op', () async {
    expect(
      () => commerce.saveForLater('nothing'),
      throwsA(isA<NotFoundException>()),
    );
    expect(
      () => commerce.moveToCart('nothing'),
      throwsA(isA<NotFoundException>()),
    );
  });
}
