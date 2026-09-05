import '../../models/models.dart';
import '../auth/auth_service.dart';
import '../repositories/repositories.dart';
import 'fixture_data.dart';
import 'fixture_store.dart';

/// The demo backend.
///
/// Two things it deliberately does that the prototype did not:
///
///  * **It says no.** A missing id throws [NotFoundException] instead of
///    quietly returning `p1` or `maya`, and a search that matches nothing
///    returns nothing instead of falling back to two arbitrary products. Those
///    fallbacks hid the fact that no screen had an empty or not-found state;
///    with real data they would have shown one person another person's profile.
///  * **It remembers.** Writes land in [FixtureStore] and come back through the
///    same stream the screen is watching, so screen code written here needs no
///    changes when Firestore arrives.
///
/// [latency] exists so loading states are actually exercised in the demo. It
/// must be zero under test, or every `pumpAndSettle` pays for it.
class FixtureBackend {
  FixtureBackend({FixtureStore? store, this.latency = Duration.zero, this.auth})
    : store = store ?? FixtureStore();

  final FixtureStore store;
  final Duration latency;

  /// The demo identity, so a fixture grant can flip the seller flag the way
  /// the real backend mints a claim. Null in tests that build a backend alone.
  final FixtureAuthService? auth;

  /// Whoever the identity says is signed in; the store's demo user when no
  /// identity is wired (tests that build a backend on its own).
  String get uid => auth?.currentUser?.uid ?? store.currentUid;

  Future<T> _delayed<T>(T value) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return value;
  }

  Future<void> _settle() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }
}

class FixtureCatalogRepository implements CatalogRepository {
  FixtureCatalogRepository(this._backend);

  final FixtureBackend _backend;

  @override
  Future<Product> product(String id) {
    final found = Fx.products[id];
    if (found == null) throw NotFoundException('product', id);
    return _backend._delayed(found);
  }

  @override
  Future<ProductSpec> spec(String id) {
    final found = Fx.specs[id];
    if (found == null) throw NotFoundException('spec', id);
    return _backend._delayed(found);
  }

  @override
  Future<List<Product>> productsByIds(List<String> ids) {
    // Missing ids are skipped rather than fatal: a stale reference in a feed
    // should cost one card, not the whole screen.
    return _backend._delayed([for (final id in ids) ?Fx.products[id]]);
  }

  @override
  Future<Page<Product>> productsBySeller(String sellerId, {String? cursor}) {
    final owned = Fx.products.values
        .where((p) => p.sellerId == sellerId)
        .toList();
    // No padding and no substitution. A seller with nothing listed has an
    // empty storefront, which is the truth the prototype papered over.
    return _backend._delayed(Page(items: owned));
  }

  @override
  Future<List<Variant>> liveVariants(String productId) async {
    final spec = Fx.specs[productId];
    if (spec == null) throw NotFoundException('product', productId);
    return _backend._delayed(spec.variants);
  }

  @override
  Future<List<TagCount>> popularTags({int limit = 8}) =>
      _backend._delayed(Fx.tags.take(limit).toList());
}

class FixtureCollectionRepository implements CollectionRepository {
  FixtureCollectionRepository(this._backend);

  final FixtureBackend _backend;

  @override
  Future<List<Collection>> collections() {
    final sorted = Fx.collections.where((c) => c.productCount > 0).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return _backend._delayed(sorted);
  }

  @override
  Future<Collection> collection(String handle) {
    for (final c in Fx.collections) {
      if (c.handle == handle) return _backend._delayed(c);
    }
    throw NotFoundException('collection', handle);
  }

  @override
  Future<Page<Product>> productsInCollection(String handle, {String? cursor}) {
    final items = Fx.products.values
        .where((p) => p.collectionHandles.contains(handle))
        .toList();
    return _backend._delayed(Page(items: items));
  }
}

class FixtureSearchRepository implements SearchRepository {
  FixtureSearchRepository(this._backend);

  final FixtureBackend _backend;

  FixtureStore get _store => _backend.store;

  @override
  Future<SearchResults> search(SearchFilters filters, {String? cursor}) {
    final query = filters.query.trim();
    if (query.isEmpty) return _backend._delayed(const SearchResults.empty());

    final q = query.toLowerCase();
    final isTag = query.startsWith('#');

    bool matches(Product p) => switch (filters.scope) {
      SearchScope.hashtags => p.tags.any((t) => t.toLowerCase() == q),
      SearchScope.keywords =>
        p.title.toLowerCase().contains(q) ||
            p.description.toLowerCase().contains(q),
      SearchScope.productType => p.type.toLowerCase().contains(q),
      SearchScope.sellers =>
        _handleOf(p).toLowerCase().contains(q) ||
            _nameOf(p).toLowerCase().contains(q),
      SearchScope.all =>
        p.tags.any((t) => t.toLowerCase() == q) ||
            p.title.toLowerCase().contains(q) ||
            p.type.toLowerCase().contains(q) ||
            p.description.toLowerCase().contains(q) ||
            _nameOf(p).toLowerCase().contains(q) ||
            _handleOf(p).toLowerCase().contains(q),
    };

    var products = Fx.products.values.where(matches).toList();

    // The radius filter, applied the way the live one will be: bound first,
    // then measure. A listing with no coordinates is excluded from a radius
    // search rather than silently included.
    final origin = filters.origin;
    if (filters.isGeoConstrained && origin != null) {
      products = products.where((p) {
        if (p.lat == null || p.lng == null) return false;
        return Geo.milesBetween(origin.lat, origin.lng, p.lat!, p.lng!) <=
            filters.radiusMiles;
      }).toList();
    }

    products = _sorted(products, filters);

    final sellers = filters.scope == SearchScope.productType
        ? <Person>[]
        : Fx.people.values
              .where(
                (person) =>
                    person.isSeller &&
                    (person.name.toLowerCase().contains(q) ||
                        person.handle.toLowerCase().contains(q) ||
                        person.tags.any((t) => t.toLowerCase() == q)),
              )
              .toList();

    final reviews = <TaggedReview>[
      if (isTag)
        for (final entry in _store.reviews.value.entries)
          for (final review in entry.value)
            if (review.tags.any((t) => t.toLowerCase() == q))
              TaggedReview(productId: entry.key, review: review),
    ];

    return _backend._delayed(
      SearchResults(products: products, sellers: sellers, reviews: reviews),
    );
  }

  List<Product> _sorted(List<Product> products, SearchFilters filters) {
    final sorted = [...products];
    switch (filters.sort) {
      case SortOrder.priceLowToHigh:
        sorted.sort((a, b) => a.priceCents.compareTo(b.priceCents));
      case SortOrder.topRated:
        sorted.sort((a, b) => b.rating.compareTo(a.rating));
      case SortOrder.nearest:
        final origin = filters.origin;
        if (origin != null) {
          sorted.sort(
            (a, b) => _distance(a, origin).compareTo(_distance(b, origin)),
          );
        }
      case SortOrder.newest:
      case SortOrder.relevance:
        break;
    }
    return sorted;
  }

  double _distance(Product p, SearchOrigin origin) {
    if (p.lat == null || p.lng == null) return double.infinity;
    return Geo.milesBetween(origin.lat, origin.lng, p.lat!, p.lng!);
  }

  String _nameOf(Product p) => Fx.people[p.sellerId]?.name ?? '';
  String _handleOf(Product p) => Fx.people[p.sellerId]?.handle ?? '';

  @override
  Future<List<String>> recentSearches() =>
      _backend._delayed([..._store.recentSearches.value]);

  @override
  Future<void> recordSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final next = [..._store.recentSearches.value]
      ..removeWhere((q) => q.toLowerCase() == trimmed.toLowerCase())
      ..insert(0, trimmed);
    _store.recentSearches.value = next.take(8).toList();
  }

  @override
  Future<void> removeRecentSearch(String query) async {
    _store.recentSearches.value = [..._store.recentSearches.value]
      ..remove(query);
  }

  @override
  Future<void> clearRecentSearches() async {
    _store.recentSearches.value = [];
  }
}

class FixtureCommerceRepository implements CommerceRepository {
  FixtureCommerceRepository(this._backend);

  final FixtureBackend _backend;

  FixtureStore get _store => _backend.store;

  @override
  Stream<Cart> watchCart() => _store.cart.stream;

  @override
  Future<Cart> addLine({
    required String productId,
    String? variantId,
    int quantity = 1,
  }) async {
    final product = Fx.products[productId];
    if (product == null) throw NotFoundException('product', productId);

    final variants = Fx.specs[productId]?.variants ?? const <Variant>[];
    // A null variant means the default, which is what the feed's add-to-cart
    // has to work with — there is no variant picker on a feed card.
    final variant = variantId == null
        ? (variants.isEmpty
              ? Variant(product.title, product.priceCents)
              : variants.first)
        : variants.firstWhere(
            (v) => v.name == variantId,
            orElse: () => Variant(product.title, product.priceCents),
          );

    if (!variant.availableForSale) {
      throw ValidationException('${variant.name} is sold out');
    }

    final resolvedVariantId = variant.name;
    final cart = _store.cart.value;
    final existing = cart.lineFor(resolvedVariantId);
    final lines = [...cart.lines];
    if (existing == null) {
      lines.add(
        CartLine(
          id: _store.newId('line_'),
          productId: productId,
          variantId: resolvedVariantId,
          title: product.title,
          variantTitle: variant.name,
          // The variant's price, not the product's — the prototype's buy sheet
          // ignored the selected variant and would have shipped wrong totals.
          unitPriceCents: variant.priceCents,
          quantity: quantity,
          sellerId: product.sellerId,
          imageUrl: product.imageUrls.isEmpty ? null : product.imageUrls.first,
        ),
      );
    } else {
      lines[lines.indexOf(existing)] = existing.copyWith(
        quantity: existing.quantity + quantity,
      );
    }
    // Any change invalidates the quote: shipping and tax must be re-asked.
    _store.cart.value = cart.copyWith(lines: lines, clearQuote: true);
    await _backend._settle();
    return _store.cart.value;
  }

  @override
  Future<Cart> updateLine({
    required String lineId,
    required int quantity,
  }) async {
    if (quantity <= 0) return removeLine(lineId);
    final cart = _store.cart.value;
    final lines = [
      for (final line in cart.lines)
        if (line.id == lineId) line.copyWith(quantity: quantity) else line,
    ];
    _store.cart.value = cart.copyWith(lines: lines, clearQuote: true);
    await _backend._settle();
    return _store.cart.value;
  }

  @override
  Future<Cart> removeLine(String lineId) async {
    final cart = _store.cart.value;
    _store.cart.value = cart.copyWith(
      lines: cart.lines.where((line) => line.id != lineId).toList(),
      clearQuote: true,
    );
    await _backend._settle();
    return _store.cart.value;
  }

  @override
  Future<Cart> clearCart() async {
    _store.cart.value = _store.cart.value.copyWith(lines: [], clearQuote: true);
    return _store.cart.value;
  }

  @override
  Future<CheckoutHandoff> beginCheckout() async {
    final cart = _store.cart.value;
    if (cart.isEmpty) throw const ValidationException('Your cart is empty');
    await _backend._settle();
    return CheckoutHandoff(
      cartId: cart.id,
      webUrl: Uri.parse('https://example.invalid/checkout/${cart.id}'),
    );
  }

  @override
  Future<Page<Order>> orders({String? cursor}) =>
      _backend._delayed(const Page<Order>.empty());

  @override
  Future<Order> order(String id) async => throw NotFoundException('order', id);

  @override
  Stream<List<Purchase>> watchPurchases(String uid) => _store.purchases.stream;
}

class FixtureSocialRepository implements SocialRepository {
  FixtureSocialRepository(this._backend);

  final FixtureBackend _backend;

  FixtureStore get _store => _backend.store;

  @override
  Stream<List<Post>> watchFeed({List<String> tags = const [], int limit = 20}) {
    return _store.posts.stream.map((posts) {
      final filtered = tags.isEmpty
          ? posts
          : posts.where((p) => p.tags.any(tags.contains)).toList();
      return filtered.take(limit).toList();
    });
  }

  @override
  Future<Page<Post>> feedPage({String? cursor, int limit = 20}) =>
      _backend._delayed(Page(items: _store.posts.value.take(limit).toList()));

  @override
  Future<Post> post(String id) {
    for (final post in _store.posts.value) {
      if (post.id == id) return _backend._delayed(post);
    }
    throw NotFoundException('post', id);
  }

  @override
  Future<List<Post>> postsBy(String personId, {PostKind? kind}) =>
      _backend._delayed([
        for (final post in _store.posts.value)
          if (post.authorId == personId && (kind == null || post.kind == kind))
            post,
      ]);

  @override
  Future<String> createPost(NewPost draft) async {
    final id = _store.newId('post_');
    final now = DateTime.now();
    final post = switch (draft.kind) {
      PostKind.listing => ListingPost(
        id: id,
        authorId: _backend.uid,
        createdAt: now,
        tags: draft.tags,
        likeCount: 0,
        commentCount: 0,
        likedByMe: false,
        product: Fx.products[draft.productId] ?? Fx.product('p1'),
        caption: draft.caption,
      ),
      PostKind.review => ReviewPost(
        id: id,
        authorId: _backend.uid,
        createdAt: now,
        tags: draft.tags,
        likeCount: 0,
        commentCount: 0,
        likedByMe: false,
        productId: draft.productId!,
        rating: draft.rating!,
        text: draft.text!,
        purchaseId: draft.purchaseId,
        imageUrls: draft.imageUrls,
      ),
      PostKind.shoutout => ShoutoutPost(
        id: id,
        authorId: _backend.uid,
        createdAt: now,
        tags: draft.tags,
        likeCount: 0,
        commentCount: 0,
        likedByMe: false,
        text: draft.text!,
        aboutSellerId: draft.aboutSellerId,
        imageUrls: draft.imageUrls,
      ),
    };
    _store.posts.value = [post, ..._store.posts.value];
    return id;
  }

  @override
  Future<void> deletePost(String id) async {
    _store.posts.value = _store.posts.value.where((p) => p.id != id).toList();
  }

  @override
  Future<void> setLike(String postId, bool liked) async {
    final already = _store.likedPosts.contains(postId);
    if (already == liked) return;
    liked ? _store.likedPosts.add(postId) : _store.likedPosts.remove(postId);

    _store.posts.value = [
      for (final post in _store.posts.value)
        if (post.id == postId) _withLike(post, liked) else post,
    ];
  }

  Post _withLike(Post post, bool liked) {
    final delta = liked ? 1 : -1;
    final count = (post.likeCount + delta).clamp(0, 1 << 30);
    return switch (post) {
      ListingPost p => ListingPost(
        id: p.id,
        authorId: p.authorId,
        createdAt: p.createdAt,
        tags: p.tags,
        likeCount: count,
        commentCount: p.commentCount,
        likedByMe: liked,
        product: p.product,
        caption: p.caption,
      ),
      ReviewPost p => ReviewPost(
        id: p.id,
        authorId: p.authorId,
        createdAt: p.createdAt,
        tags: p.tags,
        likeCount: count,
        commentCount: p.commentCount,
        likedByMe: liked,
        productId: p.productId,
        rating: p.rating,
        text: p.text,
        purchaseId: p.purchaseId,
        imageUrls: p.imageUrls,
      ),
      ShoutoutPost p => ShoutoutPost(
        id: p.id,
        authorId: p.authorId,
        createdAt: p.createdAt,
        tags: p.tags,
        likeCount: count,
        commentCount: p.commentCount,
        likedByMe: liked,
        text: p.text,
        aboutSellerId: p.aboutSellerId,
        imageUrls: p.imageUrls,
      ),
    };
  }

  @override
  Stream<List<Comment>> watchComments(String postId) =>
      _store.comments.stream.map((all) => all[postId] ?? const []);

  @override
  Future<void> addComment({
    required String postId,
    required String text,
    String? parentId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final comment = Comment(
      id: _store.newId('comment_'),
      postId: postId,
      authorId: _backend.uid,
      createdAt: DateTime.now(),
      text: trimmed,
      parentId: parentId,
    );
    final all = {..._store.comments.value};
    all[postId] = [...?all[postId], comment];
    _store.comments.value = all;
  }

  @override
  Future<void> setCommentLike(String commentId, bool liked) async {
    final already = _store.likedComments.contains(commentId);
    if (already == liked) return;
    liked
        ? _store.likedComments.add(commentId)
        : _store.likedComments.remove(commentId);

    final all = {..._store.comments.value};
    for (final key in all.keys) {
      all[key] = [
        for (final c in all[key]!)
          if (c.id == commentId)
            c.copyWith(
              likeCount: (c.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 30),
              likedByMe: liked,
            )
          else
            c,
      ];
    }
    _store.comments.value = all;
  }

  @override
  Stream<List<Review>> watchReviews(String productId) =>
      _store.reviews.stream.map((all) => all[productId] ?? const []);

  @override
  Stream<RatingSummary> watchRating(String productId) =>
      _store.reviews.stream.map((all) {
        final reviews = all[productId] ?? const <Review>[];
        if (reviews.isEmpty) {
          return const RatingSummary(
            average: 0,
            bars: [
              (stars: 5, count: 0),
              (stars: 4, count: 0),
              (stars: 3, count: 0),
              (stars: 2, count: 0),
              (stars: 1, count: 0),
            ],
          );
        }
        // Recomputed from the reviews themselves so a newly written review
        // moves the histogram, rather than reading a frozen fixture.
        final counts = <int, int>{for (var s = 1; s <= 5; s++) s: 0};
        for (final r in reviews) {
          counts[r.rating] = (counts[r.rating] ?? 0) + 1;
        }
        final total = reviews.length;
        final sum = reviews.fold(0, (acc, r) => acc + r.rating);
        return RatingSummary(
          average: sum / total,
          bars: [for (var s = 5; s >= 1; s--) (stars: s, count: counts[s]!)],
        );
      });

  @override
  Future<void> addReview(NewReview draft) async {
    final all = {..._store.reviews.value};
    all[draft.productId] = [
      Review(
        authorId: _backend.uid,
        rating: draft.rating,
        createdAt: DateTime.now(),
        text: draft.text,
        tags: draft.tags,
      ),
      ...?all[draft.productId],
    ];
    _store.reviews.value = all;

    // Reviewing a purchase marks it reviewed, so the composer stops offering
    // it and the profile badge is data rather than grid position.
    if (draft.purchaseId != null) {
      _store.purchases.value = [
        for (final p in _store.purchases.value)
          if (p.id == draft.purchaseId)
            Purchase(
              id: p.id,
              orderId: p.orderId,
              productId: p.productId,
              title: p.title,
              purchasedAt: p.purchasedAt,
              sellerId: p.sellerId,
              imageUrl: p.imageUrl,
              delivered: p.delivered,
              reviewed: true,
            )
          else
            p,
      ];
    }
  }

  @override
  Future<List<TaggedReview>> reviewsTagged(String tag, {int limit = 20}) =>
      _backend._delayed([
        for (final entry in _store.reviews.value.entries)
          for (final review in entry.value)
            if (review.tags.contains(tag))
              TaggedReview(productId: entry.key, review: review),
      ]);

  @override
  Stream<List<Forum>> watchForums() => _store.forums.stream;

  @override
  Stream<Forum> watchForum(String id) => _store.forums.stream.map((forums) {
    for (final forum in forums) {
      if (forum.id == id) return forum;
    }
    throw NotFoundException('forum', id);
  });

  @override
  Future<String> createForum(NewForum draft) async {
    final title = draft.title.trim();
    if (title.isEmpty) {
      throw const ValidationException('Name your forum', field: 'title');
    }

    final id = _store.newId('forum_');
    _store.forums.value = [
      Forum(
        id: id,
        title: title,
        description: draft.description.trim(),
        // You are the first member of a forum you create.
        memberCount: 1,
        threadCount: 0,
        tint: 0xFF5C8FCB,
      ),
      ..._store.forums.value,
    ];
    _store.joinedForums.value = {..._store.joinedForums.value, id};
    return id;
  }

  @override
  Future<void> setForumMembership(String forumId, bool joined) async {
    final current = _store.joinedForums.value;
    if (current.contains(forumId) == joined) return;
    _store.joinedForums.value = joined
        ? {...current, forumId}
        : ({...current}..remove(forumId));

    _store.forums.value = [
      for (final forum in _store.forums.value)
        if (forum.id == forumId)
          Forum(
            id: forum.id,
            title: forum.title,
            description: forum.description,
            memberCount: (forum.memberCount + (joined ? 1 : -1)).clamp(
              0,
              1 << 30,
            ),
            threadCount: forum.threadCount,
            tint: forum.tint,
          )
        else
          forum,
    ];
  }

  @override
  Stream<bool> watchForumMembership(String forumId) =>
      _store.joinedForums.stream.map((joined) => joined.contains(forumId));

  @override
  Stream<List<ForumThread>> watchThreads(String forumId) => _store
      .threads
      .stream
      .map((threads) => threads.where((t) => t.forumId == forumId).toList());

  @override
  Stream<ForumThread> watchThread(String id) =>
      _store.threads.stream.map((threads) {
        for (final thread in threads) {
          if (thread.id == id) return thread;
        }
        throw NotFoundException('thread', id);
      });

  @override
  Future<String> createThread(NewThread draft) async {
    final title = draft.title.trim();
    if (title.isEmpty) {
      throw const ValidationException(
        'Give your thread a title',
        field: 'title',
      );
    }
    final id = _store.newId('thread_');
    _store.threads.value = [
      ForumThread(
        id: id,
        forumId: draft.forumId,
        authorId: _backend.uid,
        title: title,
        body: draft.body.trim(),
        commentCount: 0,
        createdAt: DateTime.now(),
      ),
      ..._store.threads.value,
    ];
    _store.forums.value = [
      for (final forum in _store.forums.value)
        if (forum.id == draft.forumId)
          Forum(
            id: forum.id,
            title: forum.title,
            description: forum.description,
            memberCount: forum.memberCount,
            threadCount: forum.threadCount + 1,
            tint: forum.tint,
          )
        else
          forum,
    ];
    return id;
  }

  @override
  Stream<List<ThreadComment>> watchThreadComments(String threadId) =>
      _store.threadComments.stream.map((all) => all[threadId] ?? const []);

  @override
  Future<void> addThreadComment({
    required String threadId,
    required String text,
    String? parentId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final all = {..._store.threadComments.value};
    all[threadId] = [
      ...?all[threadId],
      ThreadComment(
        authorId: _backend.uid,
        createdAt: DateTime.now(),
        text: trimmed,
        depth: parentId == null ? 0 : 1,
      ),
    ];
    _store.threadComments.value = all;

    _store.threads.value = [
      for (final thread in _store.threads.value)
        if (thread.id == threadId)
          ForumThread(
            id: thread.id,
            forumId: thread.forumId,
            authorId: thread.authorId,
            title: thread.title,
            body: thread.body,
            commentCount: thread.commentCount + 1,
            createdAt: thread.createdAt,
          )
        else
          thread,
    ];
  }
}

class FixtureMessagingRepository implements MessagingRepository {
  FixtureMessagingRepository(this._backend);

  final FixtureBackend _backend;

  FixtureStore get _store => _backend.store;

  @override
  Stream<List<Message>> watchChatroom({int limit = 100}) =>
      _store.chatroom.stream.map((messages) => messages.take(limit).toList());

  @override
  Future<void> sendToChatroom(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _store.chatroom.value = [
      ..._store.chatroom.value,
      Message(
        id: _store.newId('chat_'),
        conversationId: Message.chatroomId,
        authorId: _backend.uid,
        createdAt: DateTime.now(),
        text: trimmed,
      ),
    ];
  }

  @override
  Stream<List<Conversation>> watchInbox() => _store.inbox.stream;

  @override
  Future<String> conversationWith(String personId) async {
    if (!Fx.people.containsKey(personId)) {
      throw NotFoundException('person', personId);
    }
    final id = Conversation.idFor(_backend.uid, personId);
    final all = {..._store.conversations.value};
    if (!all.containsKey(id)) {
      all[id] = [];
      _store.conversations.value = all;
      _store.inbox.value = [
        Conversation(
          id: id,
          participantIds: [_backend.uid, personId],
          lastMessageAt: DateTime.now(),
          preview: '',
        ),
        ..._store.inbox.value,
      ];
    }
    return id;
  }

  @override
  Stream<List<Message>> watchConversation(String conversationId) =>
      _store.conversations.stream.map((all) => all[conversationId] ?? const []);

  @override
  Future<void> send({
    required String conversationId,
    required String text,
    String? attachedProductId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final all = {..._store.conversations.value};
    all[conversationId] = [
      ...?all[conversationId],
      Message(
        id: _store.newId('msg_'),
        conversationId: conversationId,
        authorId: _backend.uid,
        createdAt: DateTime.now(),
        text: trimmed,
        attachedProductId: attachedProductId,
      ),
    ];
    _store.conversations.value = all;

    _store.inbox.value = [
      for (final conversation in _store.inbox.value)
        if (conversation.id == conversationId)
          conversation.copyWith(lastMessageAt: DateTime.now(), preview: trimmed)
        else
          conversation,
    ];
  }

  @override
  Future<void> markRead(String conversationId) async {
    _store.inbox.value = [
      for (final conversation in _store.inbox.value)
        if (conversation.id == conversationId)
          conversation.copyWith(unread: 0)
        else
          conversation,
    ];
  }
}

class FixtureProfileRepository implements ProfileRepository {
  FixtureProfileRepository(this._backend);

  final FixtureBackend _backend;

  FixtureStore get _store => _backend.store;

  @override
  Stream<Person?> watchPerson(String id) =>
      _store.people.stream.map((people) => people[id]);

  @override
  Future<Person> person(String id) {
    final found = _store.people.value[id];
    if (found == null) throw NotFoundException('person', id);
    return _backend._delayed(found);
  }

  @override
  Future<List<Person>> people(List<String> ids) =>
      _backend._delayed([for (final id in ids) ?_store.people.value[id]]);

  @override
  Future<List<Person>> searchPeople(String query, {int limit = 10}) {
    final q = query.toLowerCase().replaceFirst('@', '');
    if (q.isEmpty) return _backend._delayed(const []);
    return _backend._delayed(
      _store.people.value.values
          .where(
            (p) =>
                p.handle.toLowerCase().contains(q) ||
                p.name.toLowerCase().contains(q),
          )
          .take(limit)
          .toList(),
    );
  }

  @override
  Future<void> updateProfile(ProfileEdit edit) async {
    final people = {..._store.people.value};
    final current = people[_backend.uid];
    if (current == null) throw const UnauthenticatedException();

    final handle = edit.handle;
    if (handle != null && !await handleAvailable(handle)) {
      throw const ValidationException('That handle is taken', field: 'handle');
    }

    people[_backend.uid] = current.copyWith(
      name: edit.name,
      handle: handle,
      bio: edit.bio,
      tags: edit.tags,
      avatarUrl: edit.avatarUrl,
    );
    _store.people.value = people;
  }

  @override
  Future<String> uploadAvatar(List<int> bytes, {required String contentType}) =>
      _backend._delayed('asset://assets/images/logo-cart.png');

  @override
  Future<bool> handleAvailable(String handle) async {
    final normalized = handle.toLowerCase();
    return !_store.people.value.values.any(
      (p) => p.id != _backend.uid && p.handle.toLowerCase() == normalized,
    );
  }

  @override
  Future<SellerGrant> requestSellerStatus(String claimCode) async {
    final code = claimCode.trim().toUpperCase();

    // One canned code per outcome, so every branch of the claim screen is
    // reachable on the fixtures backend and in tests. The real service
    // decides all of this in one server-side transaction.
    switch (code) {
      case 'USED-CODE':
        throw const ValidationException(
          'That code has already been used. If that was not you, ask for a new one.',
          field: 'claimCode',
        );
      case 'EXPIRED-CODE':
        throw const ValidationException(
          'That code has expired. Ask for a new one.',
          field: 'claimCode',
        );
      case 'TAKEN-CODE':
        throw const ValidationException(
          'Another account already claims that shop. Get in touch and we will sort it out.',
          field: 'claimCode',
        );
      case 'GWYNSTONE':
        break;
      default:
        throw const ValidationException(
          'That code is not recognised. Check for typos, or ask for a new one.',
          field: 'claimCode',
        );
    }

    final people = {..._store.people.value};
    final current = people[_backend.uid];
    if (current == null) throw const UnauthenticatedException();
    people[_backend.uid] = current.copyWith(isSeller: true);
    _store.people.value = people;
    // The real backend mints a `seller` claim; the demo one flips the same
    // flag on the identity, so the session sees the grant the same way.
    _backend.auth?.grantSeller(_backend.uid);
    return const SellerGrant(vendorName: 'Gwynstone');
  }

  @override
  Future<LinkResult> linkStoreAccounts() async {
    final people = {..._store.people.value};
    final current = people[_backend.uid];
    if (current == null) throw const UnauthenticatedException();
    final already = current.isLinked;
    people[_backend.uid] = current.copyWith(isLinked: true);
    _store.people.value = people;
    return LinkResult(
      linkedCustomer: true,
      linkedVendor: current.isSeller,
      backfilledOrders: already ? 0 : 2,
      backfilledItems: already ? 0 : 3,
      alreadyLinked: already,
    );
  }

  @override
  Future<List<Address>> addresses() =>
      _backend._delayed([..._store.addresses.value]);

  @override
  Future<void> saveAddress(Address address) async {
    final id = address.id ?? _store.newId('address_');
    final saved = address.copyWith(id: id);
    final existing = _store.addresses.value.any((a) => a.id == id);
    _store.addresses.value = existing
        ? [
            for (final a in _store.addresses.value)
              if (a.id == id) saved else a,
          ]
        : [..._store.addresses.value, saved];
  }

  @override
  Future<void> deleteAddress(String id) async {
    _store.addresses.value = _store.addresses.value
        .where((a) => a.id != id)
        .toList();
  }
}

class FixtureFulfillmentRepository implements FulfillmentRepository {
  FixtureFulfillmentRepository(this._backend);

  final FixtureBackend _backend;

  FixtureStore get _store => _backend.store;

  @override
  Stream<List<Shipment>> watchSending() => _store.sending.stream;

  @override
  Stream<List<Shipment>> watchReceiving() => _store.receiving.stream;

  @override
  Future<void> addTracking({
    required String orderId,
    required String trackingNumber,
    required String carrier,
  }) async {
    if (trackingNumber.trim().isEmpty) {
      throw const ValidationException(
        'Enter a tracking number',
        field: 'trackingNumber',
      );
    }
    // The demo has no orders to attach to, so this records the shipment on the
    // sending list to prove the write reached the repository.
    _store.sending.value = [
      Shipment(
        productId: orderId,
        counterpartyName: carrier,
        state: ShipmentState.labelCreated,
        tracking: trackingNumber.trim(),
        carrierNote: 'Added just now',
      ),
      ..._store.sending.value,
    ];
  }
}

/// Diagnostics on the demo backend: every check passes bar one, and the facts
/// come from the fixture identity, so the screen renders in tests and demos.
/// The demo seller path: draft → submitting → submitted, or failed with the
/// same messages the function would give, so the retry button and every
/// status chip are testable before a function exists.
class FixtureSellerRepository implements SellerRepository {
  FixtureSellerRepository(this._backend);

  final FixtureBackend _backend;
  int _next = 1;

  FixtureStore get _store => _backend.store;

  bool get _isSeller {
    final user = _backend.auth?.currentUser;
    if (user != null) return user.isSeller;
    return _store.people.value[_backend.uid]?.isSeller ?? false;
  }

  @override
  Stream<List<Listing>> watchListings() => _store.listings.stream.map(
    (all) => all.where((l) => l.sellerUid == _backend.uid).toList(),
  );

  @override
  Future<String> saveDraft(ListingDraft draft, {String? id}) async {
    if (!_isSeller) {
      throw const PermissionException('You are not set up to sell yet.');
    }
    final listings = [..._store.listings.value];
    final index = id == null ? -1 : listings.indexWhere((l) => l.id == id);
    final existing = index == -1 ? null : listings[index];
    // Content is editable at every status except mid-send, like the rules.
    if (existing != null && existing.status == ListingStatus.submitting) {
      throw const PermissionException(
        'That product is still being sent. Try again in a moment.',
      );
    }
    final listingId = id ?? 'L${_next++}';
    final saved = Listing(
      categoryId: draft.category?.id,
      categoryName: draft.category?.fullName,
      id: listingId,
      sellerUid: _backend.uid,
      status: existing?.status ?? ListingStatus.draft,
      title: draft.title.trim(),
      description: draft.description.trim(),
      priceCents: draft.priceCents,
      quantity: draft.quantity,
      sku: draft.sku,
      imageUrls: draft.imageUrls,
      collectionHandles: draft.collectionHandles,
      tags: draft.tags,
      error: existing?.error,
      shopifyProductId: existing?.shopifyProductId,
      updatedAt: DateTime.now(),
    );
    if (index == -1) {
      listings.insert(0, saved);
    } else {
      listings[index] = saved;
    }
    _store.listings.value = listings;
    return _backend._delayed(listingId);
  }

  @override
  Future<String> uploadListingPhoto(
    List<int> bytes, {
    required String contentType,
  }) => _backend._delayed('asset://assets/images/logo-cart.png');

  @override
  Future<PublishResult> publishListing(String listingId) async {
    if (!_isSeller) {
      throw const PermissionException('You are not set up to sell yet.');
    }
    final listings = [..._store.listings.value];
    final index = listings.indexWhere((l) => l.id == listingId);
    if (index == -1) throw NotFoundException('listing', listingId);
    final listing = listings[index];
    if (listing.sellerUid != _backend.uid) {
      throw const PermissionException('That draft is not yours.');
    }
    if (!listing.status.editable) {
      throw const ValidationException(
        'That product has already been sent for review.',
      );
    }

    // The same refusals the function gives, in the same words.
    final problem = listing.title.isEmpty
        ? 'Give it a title.'
        : listing.priceCents <= 0
        ? 'Set a price above \$0.'
        : listing.imageUrls.isEmpty
        ? 'Add at least one photo.'
        : null;
    if (problem != null) {
      listings[index] = listing.copyWith(
        status: ListingStatus.failed,
        error: problem,
        updatedAt: DateTime.now(),
      );
      _store.listings.value = listings;
      throw ValidationException(problem);
    }

    // A retry adopts the product the first attempt made.
    final productId = listing.shopifyProductId ?? 'fx-${listing.id}';
    listings[index] = listing.copyWith(
      status: ListingStatus.submitted,
      shopifyProductId: productId,
      clearError: true,
      updatedAt: DateTime.now(),
    );
    _store.listings.value = listings;
    return _backend._delayed(
      PublishResult(
        shopifyProductId: productId,
        adopted: listing.shopifyProductId != null,
      ),
    );
  }

  static const _categories = [
    ProductCategory(
      id: 'gid://shopify/TaxonomyCategory/aa-1-13',
      name: 'Sweatshirts',
      fullName: 'Apparel & Accessories > Clothing > Sweatshirts',
    ),
    ProductCategory(
      id: 'gid://shopify/TaxonomyCategory/hb-1-2',
      name: 'Lip Balms',
      fullName: 'Health & Beauty > Personal Care > Cosmetics > Lip Balms',
    ),
    ProductCategory(
      id: 'gid://shopify/TaxonomyCategory/ae-2-1',
      name: 'Stickers',
      fullName: 'Arts & Entertainment > Hobbies & Creative Arts > Stickers',
    ),
  ];

  @override
  Future<List<ProductCategory>> searchCategories(String query) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    return _backend._delayed(
      _categories.where((c) => c.fullName.toLowerCase().contains(q)).toList(),
    );
  }

  @override
  Future<PublishResult> updateListing(String listingId) async {
    if (!_isSeller) {
      throw const PermissionException('You are not set up to sell yet.');
    }
    final listings = [..._store.listings.value];
    final index = listings.indexWhere((l) => l.id == listingId);
    if (index == -1) throw NotFoundException('listing', listingId);
    final listing = listings[index];
    if (!listing.onStore) {
      throw const ValidationException(
        'That product has not been added to the store yet.',
      );
    }
    final problem = listing.title.isEmpty
        ? 'Give it a title.'
        : listing.priceCents <= 0
        ? 'Set a price above \$0.'
        : null;
    if (problem != null) {
      listings[index] = listing.copyWith(
        status: ListingStatus.failed,
        error: problem,
        updatedAt: DateTime.now(),
      );
      _store.listings.value = listings;
      throw ValidationException(problem);
    }
    // The product keeps its id and its status; only content moved.
    listings[index] = listing.copyWith(
      status: listing.status == ListingStatus.failed
          ? ListingStatus.live
          : listing.status,
      clearError: true,
      updatedAt: DateTime.now(),
    );
    _store.listings.value = listings;
    return _backend._delayed(
      PublishResult(shopifyProductId: listing.shopifyProductId!),
    );
  }

  @override
  Future<int> refreshListings() async {
    // The demo store approves everything on the first look.
    final listings = [..._store.listings.value];
    var changed = 0;
    for (var i = 0; i < listings.length; i++) {
      if (listings[i].status == ListingStatus.submitted &&
          listings[i].sellerUid == _backend.uid) {
        listings[i] = listings[i].copyWith(
          status: ListingStatus.live,
          updatedAt: DateTime.now(),
        );
        changed += 1;
      }
    }
    if (changed > 0) _store.listings.value = listings;
    return _backend._delayed(changed);
  }

  @override
  Future<void> deleteDraft(String id) async {
    _store.listings.value = _store.listings.value
        .where((l) => l.id != id || !l.status.editable)
        .toList();
  }
}

class FixtureDiagnosticsRepository implements DiagnosticsRepository {
  FixtureDiagnosticsRepository(this._auth, {required this.backend});

  final AuthService _auth;
  final String backend;

  /// Flipped by [claimAdmin], so the demo Diagnostics screen behaves.
  bool _admin = false;

  @override
  Future<HealthReport> healthCheck() async => HealthReport(
    project: 'fixtures',
    at: DateTime.now(),
    checks: const [
      HealthCheckItem(name: 'storeDomain', ok: true, summary: 'demo store'),
      HealthCheckItem(name: 'adminToken', ok: true, summary: 'demo token'),
      HealthCheckItem(name: 'webhooks', ok: true, summary: '6 of 6 registered'),
      HealthCheckItem(
        name: 'shipturtleProbe',
        ok: false,
        summary: 'not configured on the demo backend',
        fix: 'run against the live backend to check Shipturtle',
      ),
    ],
  );

  @override
  Future<AuthFacts> authFacts() async {
    final user = _auth.currentUser;
    return AuthFacts(
      backend: backend,
      uid: user?.uid,
      email: user?.email,
      isAnonymous: user?.isAnonymous ?? false,
      emailVerified: user?.emailVerified ?? false,
      isSeller: user != null && !user.isAnonymous && user.uid == 'maya',
      isAdmin: _admin,
      isLinked: user != null && !user.isAnonymous,
    );
  }

  @override
  Future<void> claimAdmin() async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw const PermissionException('Sign in first.');
    }
    _admin = true;
  }

  @override
  Future<int> syncCollections() async => Fx.collections.length;

  @override
  Future<String> setSellerVendor({
    required String uid,
    required String vendorName,
  }) async {
    if (!_admin) throw const PermissionException('Admins only.');
    return 'Demo Vendor';
  }

  @override
  Future<BackfillProgress> backfillCatalog({bool reset = false}) async =>
      BackfillProgress(
        processed: Fx.products.length,
        total: Fx.products.length,
        done: true,
      );
}
