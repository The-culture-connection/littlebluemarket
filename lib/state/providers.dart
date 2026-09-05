import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../data/repositories/repositories.dart';
import '../models/models.dart';
import 'session.dart';

export '../data/providers.dart';

/// Keeps a provider's value for as long as the app is running.
///
/// Riverpod 3 auto-disposes, which is right for a search but wrong for a
/// product: opening a post, going back, and opening another re-fetches and
/// re-decodes every image, so the grid visibly flickers on every
/// back-navigation.
///
/// Deliberately not a timed eviction. A timer left pending is a failure in
/// `flutter_test`, and the only way to avoid that was to have app code detect
/// whether it was under test — which is worse than the problem. These are
/// small, bounded caches (products, specs, people), and anything that needs to
/// be fresh is invalidated explicitly on refresh.
extension KeepCached on Ref {
  void keepCached() => keepAlive();
}

// ------------------------------------------------------------------ catalog

/// A product, live and kept: the rating, the "added" count and the price
/// follow the backend on every card that shows them. A one-shot read kept
/// showing the numbers from first open until the app restarted.
final productProvider = StreamProvider.family<Product, String>((ref, id) {
  ref.keepCached();
  return ref.watch(catalogRepositoryProvider).watchProduct(id);
});

/// Same stream as [productProvider]; kept as a name for the count line.
final liveProductProvider = productProvider;

final productSpecProvider = FutureProvider.family<ProductSpec, String>((
  ref,
  id,
) {
  ref.keepCached();
  return ref.watch(catalogRepositoryProvider).spec(id);
});

final productsByIdsProvider =
    FutureProvider.family<List<Product>, List<String>>((ref, ids) {
      ref.keepCached();
      return ref.watch(catalogRepositoryProvider).productsByIds(ids);
    });

final sellerProductsProvider = FutureProvider.family<List<Product>, String>((
  ref,
  sellerId,
) async {
  ref.keepCached();
  final page = await ref
      .watch(catalogRepositoryProvider)
      .productsBySeller(sellerId);
  return page.items;
});

// -------------------------------------------------------------- collections

/// Every non-empty collection on the store, for the feed rail.
final collectionsProvider = FutureProvider<List<Collection>>((ref) {
  ref.keepCached();
  return ref.watch(collectionRepositoryProvider).collections();
});

final collectionProvider = FutureProvider.family<Collection, String>((
  ref,
  handle,
) {
  ref.keepCached();
  return ref.watch(collectionRepositoryProvider).collection(handle);
});

/// The first page of a collection, newest first.
final collectionProductsProvider = FutureProvider.family<List<Product>, String>(
  (ref, handle) async {
    ref.keepCached();
    final page = await ref
        .watch(collectionRepositoryProvider)
        .productsInCollection(handle);
    return page.items;
  },
);

/// The signed-in seller's drafts and submissions, live.
final listingsProvider = StreamProvider<List<Listing>>((ref) {
  return ref.watch(sellerRepositoryProvider).watchListings();
});

/// What to try when a search found nothing.
final suggestionsProvider =
    FutureProvider.family<List<SearchSuggestion>, String>(
      (ref, query) => ref.watch(searchRepositoryProvider).suggestions(query),
    );

/// The bell.
final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  return ref.watch(socialRepositoryProvider).watchNotifications();
});

final unreadNotificationsProvider = Provider<int>((ref) {
  return ref.watch(notificationsProvider).value?.where((n) => !n.read).length ??
      0;
});

/// Links that differ between the dev store and the real one. Kept for the
/// life of the app: they do not change while it runs.
final appConfigProvider = FutureProvider<AppConfig>((ref) {
  ref.keepCached();
  return ref.watch(profileRepositoryProvider).appConfig();
});

final popularTagsProvider = FutureProvider<List<TagCount>>((ref) {
  ref.keepCached();
  return ref.watch(catalogRepositoryProvider).popularTags();
});

/// Everything the product screen needs, resolved together.
///
/// One provider rather than four, so the screen shows one skeleton instead of
/// four spinners arriving at four different moments.
typedef ProductDetail = ({
  Product product,
  ProductSpec spec,

  /// Null when the shop behind this product has not joined the app yet —
  /// the normal state for a mirrored catalog until its vendors claim their
  /// shops. A product page must still open.
  Person? seller,
  RatingSummary rating,
});

final productDetailProvider = FutureProvider.family<ProductDetail, String>((
  ref,
  id,
) async {
  ref.keepCached();
  final catalog = ref.watch(catalogRepositoryProvider);
  final profiles = ref.watch(profileRepositoryProvider);
  final social = ref.watch(socialRepositoryProvider);

  final product = await catalog.product(id);
  final results = await (
    catalog.spec(id),
    _sellerOrNull(profiles, product.sellerId),
    social.watchRating(id).first,
  ).wait;

  return (
    product: product,
    spec: results.$1,
    seller: results.$2,
    rating: results.$3,
  );
});

/// The seller behind a product, or null when there is none to show: an empty
/// id (unclaimed vendor) or a profile that no longer exists.
Future<Person?> _sellerOrNull(
  ProfileRepository profiles,
  String sellerId,
) async {
  if (sellerId.isEmpty) return null;
  try {
    return await profiles.person(sellerId);
  } on NotFoundException {
    return null;
  }
}

/// The variant someone has picked, per product.
///
/// UI state, so it lives here rather than on the model — and it lives outside
/// the screen because the buy sheet needs it too. The prototype kept it in the
/// screen's setState and the buy sheet never saw it, which is why the sheet
/// priced the product instead of the variant.
class SelectedVariantsNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => const {};

  void select(String productId, int index) =>
      state = {...state, productId: index};
}

final selectedVariantsProvider =
    NotifierProvider<SelectedVariantsNotifier, Map<String, int>>(
      SelectedVariantsNotifier.new,
    );

/// The chosen variant index for one product. Defaults to the first.
final selectedVariantProvider = Provider.family<int, String>(
  (ref, productId) => ref.watch(selectedVariantsProvider)[productId] ?? 0,
);

// ------------------------------------------------------------------- social

final feedProvider = StreamProvider<List<Post>>((ref) {
  return ref.watch(socialRepositoryProvider).watchFeed();
});

final postProvider = FutureProvider.family<Post, String>((ref, id) {
  ref.keepCached();
  return ref.watch(socialRepositoryProvider).post(id);
});

final postsByProvider = FutureProvider.family<List<Post>, String>((ref, id) {
  ref.keepCached();
  return ref.watch(socialRepositoryProvider).postsBy(id);
});

final commentsProvider = StreamProvider.family<List<Comment>, String>((
  ref,
  postId,
) {
  return ref.watch(socialRepositoryProvider).watchComments(postId);
});

final reviewsProvider = StreamProvider.family<List<Review>, String>((
  ref,
  productId,
) {
  return ref.watch(socialRepositoryProvider).watchReviews(productId);
});

final ratingProvider = StreamProvider.family<RatingSummary, String>((
  ref,
  productId,
) {
  return ref.watch(socialRepositoryProvider).watchRating(productId);
});

// ------------------------------------------------------------------ profile

final personProvider = FutureProvider.family<Person, String>((ref, id) {
  ref.keepCached();
  return ref.watch(profileRepositoryProvider).person(id);
});

final watchPersonProvider = StreamProvider.family<Person?, String>((ref, id) {
  return ref.watch(profileRepositoryProvider).watchPerson(id);
});

final purchasesProvider = StreamProvider<List<Purchase>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const <Purchase>[]);
  return ref.watch(commerceRepositoryProvider).watchPurchases(uid);
});

// ------------------------------------------------------------------- search

/// The live search, as one value.
///
/// Held above the screens because the feed's "near me" toggle and the results
/// screen's scope chips are the same search seen from two places, and the
/// prototype let them drift apart into two cosmetic chip rows that filtered
/// nothing.
class SearchFiltersNotifier extends Notifier<SearchFilters> {
  @override
  SearchFilters build() => const SearchFilters();

  void setQuery(String query) => state = state.copyWith(query: query);
  void setScope(SearchScope scope) => state = state.copyWith(scope: scope);
  void setSort(SortOrder sort) => state = state.copyWith(sort: sort);
  void setRadius(double miles) => state = state.copyWith(radiusMiles: miles);
  void setOrigin(SearchOrigin? origin) => origin == null
      ? state = state.copyWith(clearOrigin: true, nearMe: false)
      : state = state.copyWith(origin: origin);

  void toggleNearMe() => state = state.copyWith(nearMe: !state.nearMe);
}

final searchFiltersProvider =
    NotifierProvider<SearchFiltersNotifier, SearchFilters>(
      SearchFiltersNotifier.new,
    );

final searchResultsProvider =
    FutureProvider.family<SearchResults, SearchFilters>((ref, filters) {
      return ref.watch(searchRepositoryProvider).search(filters);
    });

final recentSearchesProvider = FutureProvider<List<String>>((ref) {
  return ref.watch(searchRepositoryProvider).recentSearches();
});

// ------------------------------------------------------------------ commerce

final cartProvider = StreamProvider<Cart>((ref) {
  return ref.watch(commerceRepositoryProvider).watchCart();
});

/// Just the badge number, so the tab bar does not rebuild on every cart detail.
final cartCountProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).value?.itemCount ?? 0;
});

// --------------------------------------------------------------- fulfillment

final sendingProvider = StreamProvider<List<Shipment>>((ref) {
  return ref.watch(fulfillmentRepositoryProvider).watchSending();
});

final receivingProvider = StreamProvider<List<Shipment>>((ref) {
  return ref.watch(fulfillmentRepositoryProvider).watchReceiving();
});

// ---------------------------------------------------------------- messaging

final chatroomProvider = StreamProvider<List<Message>>((ref) {
  return ref.watch(messagingRepositoryProvider).watchChatroom();
});

final inboxProvider = StreamProvider<List<Conversation>>((ref) {
  return ref.watch(messagingRepositoryProvider).watchInbox();
});

final conversationProvider = StreamProvider.family<List<Message>, String>((
  ref,
  conversationId,
) {
  return ref
      .watch(messagingRepositoryProvider)
      .watchConversation(conversationId);
});

final conversationIdProvider = FutureProvider.family<String, String>((
  ref,
  personId,
) {
  ref.keepCached();
  return ref.watch(messagingRepositoryProvider).conversationWith(personId);
});

// ---------------------------------------------------------------- community

final forumsProvider = StreamProvider<List<Forum>>((ref) {
  return ref.watch(socialRepositoryProvider).watchForums();
});

final forumProvider = StreamProvider.family<Forum, String>((ref, id) {
  return ref.watch(socialRepositoryProvider).watchForum(id);
});

final forumMembershipProvider = StreamProvider.family<bool, String>((ref, id) {
  return ref.watch(socialRepositoryProvider).watchForumMembership(id);
});

final threadsProvider = StreamProvider.family<List<ForumThread>, String>((
  ref,
  forumId,
) {
  return ref.watch(socialRepositoryProvider).watchThreads(forumId);
});

final threadProvider = StreamProvider.family<ForumThread, String>((ref, id) {
  return ref.watch(socialRepositoryProvider).watchThread(id);
});

final threadCommentsProvider =
    StreamProvider.family<List<ThreadComment>, String>((ref, threadId) {
      return ref.watch(socialRepositoryProvider).watchThreadComments(threadId);
    });

/// When a failed provider should try again.
///
/// Riverpod retries every failure by default with a backoff. That is right for
/// a dropped connection and wrong for a 404: a product that does not exist will
/// not start existing, so retrying it forever burns battery and leaves a timer
/// pending in every widget test that renders a missing record.
///
/// Returning null means "do not retry".
Duration? lbmRetry(int retryCount, Object error) {
  switch (error) {
    // These are answers, not failures.
    case NotFoundException():
    case ValidationException():
    case PermissionException():
    case UnauthenticatedException():
      return null;
    default:
      if (retryCount >= 3) return null;
      return Duration(milliseconds: 400 * (retryCount + 1));
  }
}

final addressesProvider = FutureProvider<List<Address>>((ref) {
  return ref.watch(profileRepositoryProvider).addresses();
});
