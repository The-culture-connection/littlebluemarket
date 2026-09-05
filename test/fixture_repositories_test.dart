import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/fixtures/fixture_repositories.dart';
import 'package:little_blue_market/data/fixtures/fixture_store.dart';
import 'package:little_blue_market/data/repositories/repositories.dart';
import 'package:little_blue_market/models/models.dart';

/// These test the demo backend, but they are really testing the contract every
/// backend has to keep. The behaviours asserted here are the ones the prototype
/// got wrong in ways that only become visible with real data.
void main() {
  late FixtureBackend backend;

  setUp(() {
    backend = FixtureBackend(store: FixtureStore());
  });

  tearDown(() => backend.store.dispose());

  group('catalog says no', () {
    test('a missing product throws instead of substituting another', () {
      final catalog = FixtureCatalogRepository(backend);
      // The prototype returned p1 here, so a bad deep link showed the wrong
      // product — and the same fallback on people showed the wrong profile.
      expect(
        () => catalog.product('does-not-exist'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('a stale id in a list costs one card, not the screen', () async {
      final catalog = FixtureCatalogRepository(backend);
      final products = await catalog.productsByIds(['p1', 'gone', 'p2']);
      expect(products.map((p) => p.id), ['p1', 'p2']);
    });

    test('a seller with no listings has an empty storefront', () async {
      final catalog = FixtureCatalogRepository(backend);
      // dee is a buyer. The prototype showed her Kali's products as her own.
      final page = await catalog.productsBySeller('dee');
      expect(page.items, isEmpty);
    });
  });

  group('profile says no', () {
    test('an unknown person throws rather than returning the current user', () {
      final profiles = FixtureProfileRepository(backend);
      expect(
        () => profiles.person('nobody'),
        throwsA(isA<NotFoundException>()),
      );
    });
  });

  group('search is honest', () {
    late FixtureSearchRepository search;

    setUp(() => search = FixtureSearchRepository(backend));

    test('returns nothing when nothing matches', () async {
      // The prototype fell back to ['p1','p4'], which is why no screen ever
      // needed an empty state.
      final results = await search.search(
        const SearchFilters(query: 'zzzzzz'),
      );
      expect(results.isEmpty, isTrue);
    });

    test('finds by hashtag', () async {
      final results = await search.search(
        const SearchFilters(query: '#PlasticFree', scope: SearchScope.hashtags),
      );
      expect(results.products, isNotEmpty);
      expect(
        results.products.every((p) => p.tags.contains('#PlasticFree')),
        isTrue,
      );
    });

    test('finds by seller name', () async {
      final results = await search.search(
        const SearchFilters(query: 'kalibalm', scope: SearchScope.sellers),
      );
      expect(results.products.every((p) => p.sellerId == 'kali'), isTrue);
      expect(results.sellers.map((s) => s.id), contains('kali'));
    });

    test('finds by good or service type', () async {
      final results = await search.search(
        const SearchFilters(query: 'Services', scope: SearchScope.productType),
      );
      expect(results.products.map((p) => p.id), contains('p6'));
    });

    group('radius', () {
      // Detroit. Hamtramck is a few miles away; Nashville is ~525.
      const detroit = SearchOrigin(
        lat: 42.3314,
        lng: -83.0458,
        label: 'Detroit',
      );

      test('a 20 mile default excludes another state', () async {
        final results = await search.search(
          const SearchFilters(
            query: '#WomanOwned',
            nearMe: true,
            origin: detroit,
          ),
        );
        final ids = results.products.map((p) => p.id);
        expect(ids, isNot(contains('p3')), reason: 'Nashville is 500+ miles');
        expect(ids, contains('p1'), reason: 'Detroit is 0 miles');
      });

      test('a wide enough radius lets the far listing back in', () async {
        final results = await search.search(
          const SearchFilters(
            query: '#WomanOwned',
            nearMe: true,
            origin: detroit,
            radiusMiles: 900,
          ),
        );
        expect(results.products.map((p) => p.id), contains('p3'));
      });

      test('near me without an origin does not filter', () async {
        final results = await search.search(
          const SearchFilters(query: '#WomanOwned', nearMe: true),
        );
        expect(results.products.map((p) => p.id), contains('p3'));
      });
    });

    test('recent searches persist and de-duplicate', () async {
      await search.recordSearch('soy candle');
      await search.recordSearch('soy candle');
      final recents = await search.recentSearches();
      expect(recents.where((r) => r == 'soy candle').length, 1);
      expect(recents.first, 'soy candle');

      await search.clearRecentSearches();
      expect(await search.recentSearches(), isEmpty);
    });
  });

  group('cart', () {
    late FixtureCommerceRepository commerce;

    setUp(() => commerce = FixtureCommerceRepository(backend));

    test('prices the selected variant, not the product', () async {
      // p1 is $8, but the "Plain (unflavoured)" variant is $7. The prototype's
      // buy sheet ignored the variant entirely and would have charged $8.
      final cart = await commerce.addLine(
        productId: 'p1',
        variantId: 'Plain (unflavoured)',
      );
      expect(cart.lines.single.unitPriceCents, 700);
    });

    test('adding the same variant twice increments rather than duplicating', () async {
      await commerce.addLine(productId: 'p1', variantId: 'Cocoa Mint');
      final cart = await commerce.addLine(
        productId: 'p1',
        variantId: 'Cocoa Mint',
      );
      expect(cart.lines.length, 1);
      expect(cart.lines.single.quantity, 2);
    });

    test('two variants of one product are two lines', () async {
      await commerce.addLine(productId: 'p1', variantId: 'Cocoa Mint');
      final cart = await commerce.addLine(
        productId: 'p1',
        variantId: 'Vanilla Latte',
      );
      expect(cart.lines.length, 2);
    });

    test('refuses a sold-out variant', () async {
      // The Denim hat is marked unavailable.
      expect(
        () => commerce.addLine(productId: 'p3', variantId: 'Denim'),
        throwsA(isA<ValidationException>()),
      );
    });

    test('changing the cart invalidates the quote', () async {
      var cart = await commerce.addLine(productId: 'p1', variantId: 'Cocoa Mint');
      backend.store.cart.value = cart.copyWith(shippingCents: 560, taxCents: 40);
      expect(backend.store.cart.value.totalCents, isNotNull);

      cart = await commerce.addLine(productId: 'p2', variantId: 'Pack of 5');
      expect(
        cart.totalCents,
        isNull,
        reason: 'a stale total is worse than no total',
      );
    });

    test('setting a quantity to zero removes the line', () async {
      final added = await commerce.addLine(
        productId: 'p1',
        variantId: 'Cocoa Mint',
      );
      final cart = await commerce.updateLine(
        lineId: added.lines.single.id,
        quantity: 0,
      );
      expect(cart.isEmpty, isTrue);
    });

    test('will not check out an empty cart', () {
      expect(
        () => commerce.beginCheckout(),
        throwsA(isA<ValidationException>()),
      );
    });

    test('the cart stream reports the write', () async {
      final seen = <int>[];
      final sub = commerce.watchCart().listen((c) => seen.add(c.itemCount));
      await commerce.addLine(productId: 'p1', variantId: 'Cocoa Mint');
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, [0, 1]);
    });
  });

  group('social writes stick', () {
    late FixtureSocialRepository social;

    setUp(() => social = FixtureSocialRepository(backend));

    test('a like is idempotent, so a double tap cannot double count', () async {
      final before = (await social.postsBy('kali')).first;
      await social.setLike(before.id, true);
      await social.setLike(before.id, true);
      final after = await social.post(before.id);
      expect(after.likeCount, before.likeCount + 1);
      expect(after.likedByMe, isTrue);
    });

    test('unliking returns to where it started', () async {
      final before = (await social.postsBy('kali')).first;
      await social.setLike(before.id, true);
      await social.setLike(before.id, false);
      expect((await social.post(before.id)).likeCount, before.likeCount);
    });

    test('a comment survives being written', () async {
      final post = (await social.postsBy('holler')).first;
      await social.addComment(postId: post.id, text: 'Is it true to size?');
      final comments = await social.watchComments(post.id).first;
      expect(comments.last.text, 'Is it true to size?');
    });

    test('an empty comment is not written', () async {
      final post = (await social.postsBy('holler')).first;
      final before = (await social.watchComments(post.id).first).length;
      await social.addComment(postId: post.id, text: '   ');
      expect((await social.watchComments(post.id).first).length, before);
    });

    test('a new review moves the rating summary', () async {
      final before = await social.watchRating('p4').first;
      await social.addReview(
        const NewReview(productId: 'p4', rating: 1, text: 'Melted.'),
      );
      final after = await social.watchRating('p4').first;
      expect(after.total, before.total + 1);
      expect(after.average, lessThan(before.average));
    });

    test('reviewing a purchase marks it reviewed', () async {
      final commerce = FixtureCommerceRepository(backend);
      final purchases = await commerce.watchPurchases(backend.uid).first;
      final unreviewed = purchases.firstWhere((p) => !p.reviewed);

      await social.addReview(
        NewReview(
          productId: unreviewed.productId,
          rating: 5,
          text: 'Lovely.',
          purchaseId: unreviewed.id,
        ),
      );

      final after = await commerce.watchPurchases(backend.uid).first;
      expect(after.firstWhere((p) => p.id == unreviewed.id).reviewed, isTrue);
    });

    test('creating a forum makes you its first member', () async {
      final id = await social.createForum(
        const NewForum(title: 'Refill Programs', description: 'Vessel returns.'),
      );
      final forum = await social.watchForum(id).first;
      expect(forum.memberCount, 1);
      expect(await social.watchForumMembership(id).first, isTrue);
    });

    test('a forum needs a name', () {
      expect(
        () => social.createForum(const NewForum(title: '  ', description: 'x')),
        throwsA(isA<ValidationException>()),
      );
    });

    test('joining moves the member count once, not per tap', () async {
      final before = await social.watchForum('f2').first;
      await social.setForumMembership('f2', true);
      await social.setForumMembership('f2', true);
      expect((await social.watchForum('f2').first).memberCount, before.memberCount + 1);
    });

    test('a new thread raises its forum thread count', () async {
      final before = await social.watchForum('f3').first;
      await social.createThread(
        const NewThread(forumId: 'f3', title: 'Dim weight', body: 'Help.'),
      );
      final after = await social.watchForum('f3').first;
      expect(after.threadCount, before.threadCount + 1);
      expect(await social.watchThreads('f3').first, hasLength(1));
    });

    test('thread comments belong to their thread, not to every thread', () async {
      // The prototype rendered one global comment list under every thread.
      expect(await social.watchThreadComments('t1').first, isNotEmpty);
      expect(await social.watchThreadComments('t2').first, isEmpty);

      await social.addThreadComment(threadId: 't2', text: 'Same here.');
      expect(await social.watchThreadComments('t2').first, hasLength(1));
      expect(await social.watchThreadComments('t3').first, isEmpty);
    });

    test('an unknown forum throws', () {
      expect(
        () => social.watchForum('nope').first,
        throwsA(isA<NotFoundException>()),
      );
    });
  });

  group('messaging', () {
    late FixtureMessagingRepository messaging;

    setUp(() => messaging = FixtureMessagingRepository(backend));

    test('a chatroom message is kept', () async {
      final before = (await messaging.watchChatroom().first).length;
      await messaging.sendToChatroom('Tabling Sunday, bring a chair.');
      final after = await messaging.watchChatroom().first;
      expect(after.length, before + 1);
      expect(after.last.authorId, backend.uid);
    });

    test('conversations are per person, not one global thread', () async {
      // The prototype loaded the same scripted thread for every contact.
      final withKali = await messaging.conversationWith('kali');
      final withRae = await messaging.conversationWith('rae');
      expect(withKali, isNot(withRae));

      await messaging.send(conversationId: withKali, text: 'On my way.');
      expect(await messaging.watchConversation(withRae).first, isNot(contains('On my way.')));
      expect(
        (await messaging.watchConversation(withKali).first).last.text,
        'On my way.',
      );
    });

    test('the conversation id does not depend on who opened it', () async {
      expect(
        await messaging.conversationWith('kali'),
        Conversation.idFor(backend.uid, 'kali'),
      );
    });

    test('messaging an unknown person throws', () {
      expect(
        () => messaging.conversationWith('nobody'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('reading clears the unread badge', () async {
      final inbox = await messaging.watchInbox().first;
      final unread = inbox.firstWhere((c) => c.unread > 0);
      await messaging.markRead(unread.id);
      final after = await messaging.watchInbox().first;
      expect(after.firstWhere((c) => c.id == unread.id).unread, 0);
    });
  });

  group('profile edits persist', () {
    late FixtureProfileRepository profiles;

    setUp(() => profiles = FixtureProfileRepository(backend));

    test('a saved bio comes back', () async {
      await profiles.updateProfile(const ProfileEdit(bio: 'New bio.'));
      expect((await profiles.person(backend.uid)).bio, 'New bio.');
    });

    test('a taken handle is refused', () async {
      expect(await profiles.handleAvailable('@kalibalm'), isFalse);
      expect(
        () => profiles.updateProfile(const ProfileEdit(handle: '@kalibalm')),
        throwsA(isA<ValidationException>()),
      );
    });

    test('keeping your own handle is allowed', () async {
      final me = await profiles.person(backend.uid);
      expect(await profiles.handleAvailable(me.handle), isTrue);
    });

  group('claiming a shop', () {
    late FixtureStore store;
    late FixtureProfileRepository buyer;

    setUp(() {
      store = FixtureStore(currentUid: 'dee');
      buyer = FixtureProfileRepository(FixtureBackend(store: store));
      addTearDown(store.dispose);
    });

    test('a valid code grants selling, and names the shop', () async {
      expect((await buyer.person('dee')).isSeller, isFalse);

      final grant = await buyer.requestSellerStatus('gwynstone');

      expect(grant.vendorName, 'Gwynstone');
      expect((await buyer.person('dee')).isSeller, isTrue);
    });

    test('an unknown code grants nothing', () async {
      await expectLater(
        buyer.requestSellerStatus('nope'),
        throwsA(isA<ValidationException>()),
      );

      // The point of the whole phase: a refused claim must leave the account
      // exactly as it was. `becomeSeller()` is gone, so this is the only way
      // in, and it has to fail closed.
      expect((await buyer.person('dee')).isSeller, isFalse);
    });

    test('each failure says something different', () async {
      // Three of these are actionable in different ways — ask for a new code,
      // get in touch, check for typos — so a single "something went wrong"
      // would be the wrong call.
      final messages = <String>{};
      for (final code in ['USED-CODE', 'EXPIRED-CODE', 'TAKEN-CODE', 'junk']) {
        try {
          await buyer.requestSellerStatus(code);
          fail('$code should not have been accepted');
        } on ValidationException catch (error) {
          messages.add(error.message);
        }
      }
      expect(messages, hasLength(4));
    });

    test('the code is not case or whitespace sensitive', () async {
      // People paste these out of an email. Refusing a trailing space would
      // be a support ticket, not a security boundary.
      final grant = await buyer.requestSellerStatus('  GwYnStOnE  ');
      expect(grant.vendorName, 'Gwynstone');
    });
  });

    test('an address round-trips', () async {
      const address = Address(
        name: 'Maya Ellison',
        line1: '1 Test St',
        city: 'Detroit',
        region: 'MI',
        postalCode: '48216',
      );
      final before = (await profiles.addresses()).length;
      await profiles.saveAddress(address);
      final after = await profiles.addresses();
      expect(after.length, before + 1);
      expect(after.last.id, isNotNull);
    });
  });

  group('fulfillment', () {
    test('a tracking number needs to be a tracking number', () {
      final fulfillment = FixtureFulfillmentRepository(backend);
      expect(
        () => fulfillment.addTracking(
          orderId: 'o1',
          trackingNumber: '   ',
          carrier: 'USPS',
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
