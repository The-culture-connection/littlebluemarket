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

/// Live, not a cached one-shot: a product the store mirrored after the
/// profile was first opened used to stay hidden until a pull-to-refresh.
final sellerProductsProvider = StreamProvider.family<List<Product>, String>((
  ref,
  sellerId,
) {
  return ref.watch(catalogRepositoryProvider).watchProductsBySeller(sellerId);
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
///
/// The whole page, cursor included: a category was showing its first thirty
/// listings and nothing else, with no sign there were more (Grace's testers,
/// 2026-09-23). The screen keeps the pages after this one and asks the
/// repository for them itself.
final collectionProductsProvider =
    FutureProvider.family<Page<Product>, String>((ref, handle) {
      ref.keepCached();
      return ref
          .watch(collectionRepositoryProvider)
          .productsInCollection(handle);
    });

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

/// Whether you follow this person for post notifications. False for guests.
final followingProvider = StreamProvider.family<bool, String>((ref, personId) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || uid == personId) return Stream.value(false);
  return ref.watch(socialRepositoryProvider).watchFollowing(personId);
});

/// The notification switches. Defaults until saved once.
final notificationPrefsProvider = StreamProvider<NotificationPrefs>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const NotificationPrefs());
  return ref.watch(socialRepositoryProvider).watchNotificationPrefs();
});

/// News from Little Blue Market, every audience.
/// Notes from the floating bug button, newest first. Admins only: for
/// anyone else the stream is empty rather than a permission error.
final feedbackListProvider = StreamProvider<List<FeedbackItem>>((ref) {
  if (!ref.watch(isAdminProvider)) return Stream.value(const []);
  return ref.watch(feedbackRepositoryProvider).watchAll();
});

/// People asking for their account or data to go. Admins only.
final deletionRequestsProvider = StreamProvider<List<DeletionRequest>>((ref) {
  if (!ref.watch(isAdminProvider)) return Stream.value(const []);
  return ref.watch(accountRepositoryProvider).watchDeletionRequests();
});

/// Reports about members, newest first. Admins only; empty for anyone else.
final reportsProvider = StreamProvider<List<Report>>((ref) {
  if (!ref.watch(isAdminProvider)) return Stream.value(const []);
  return ref.watch(reportRepositoryProvider).watchAll();
});

final announcementsProvider = StreamProvider<List<Announcement>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const <Announcement>[]);
  return ref.watch(socialRepositoryProvider).watchAnnouncements();
});

/// What the bell shows: personal notifications and the announcements meant
/// for this viewer, newest first. The personal stream decides loading and
/// error; announcements join when they arrive.
final bellProvider = Provider<AsyncValue<List<AppNotification>>>((ref) {
  final personal = ref.watch(notificationsProvider);
  final announcements = ref.watch(announcementsProvider).value ?? const [];
  final prefs = ref.watch(notificationPrefsProvider).value;
  final isSeller = ref.watch(isSellerProvider);
  final linked = ref.watch(directoryLinkProvider).value?.linked ?? false;
  return personal.whenData((list) {
    final merged = [
      ...list,
      for (final a in announcements)
        if (a.audience.includes(isSeller: isSeller, directoryLinked: linked))
          a.asNotification(seenAt: prefs?.announcementsSeenAt),
    ]..sort((x, y) => y.createdAt.compareTo(x.createdAt));
    return merged;
  });
});

final unreadNotificationsProvider = Provider<int>((ref) {
  return ref.watch(bellProvider).value?.where((n) => !n.read).length ?? 0;
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

// ----------------------------------------------------------------- blocking
//
// "Everything except these people" is not a query Firestore can serve, so a
// blocked person is filtered out on the phone, in each provider that carries
// something they might have written. Doing it here rather than in the
// screens means a new screen gets it for free, and no screen can forget.

/// Who this account has blocked, live. Empty for a guest, and empty while
/// the list is still loading, which is the right way round: a post shown for
/// a moment and then removed is better than an empty feed that fills in.
final blockedUidsProvider = StreamProvider<Set<String>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const <String>{});
  return ref.watch(reportRepositoryProvider).watchBlocked();
});

/// The blocked set, ready to filter with.
Set<String> _blocked(Ref ref) =>
    ref.watch(blockedUidsProvider).value ?? const <String>{};

final feedProvider = StreamProvider<List<Post>>((ref) {
  final blocked = _blocked(ref);
  return ref.watch(socialRepositoryProvider).watchFeed().map(
    (posts) => [
      for (final post in posts)
        if (!blocked.contains(post.authorId)) post,
    ],
  );
});

final postProvider = FutureProvider.family<Post, String>((ref, id) {
  ref.keepCached();
  return ref.watch(socialRepositoryProvider).post(id);
});

/// Live for the same reason as [sellerProductsProvider]: the feed is a
/// stream, and a profile grid that lagged behind it read as a lost post.
final postsByProvider = StreamProvider.family<List<Post>, String>((ref, id) {
  return ref.watch(socialRepositoryProvider).watchPostsBy(id);
});

final commentsProvider = StreamProvider.family<List<Comment>, String>((
  ref,
  postId,
) {
  final blocked = _blocked(ref);
  return ref.watch(socialRepositoryProvider).watchComments(postId).map(
    (comments) => [
      for (final comment in comments)
        if (!blocked.contains(comment.authorId)) comment,
    ],
  );
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

/// Someone, live.
///
/// Live rather than fetched once, because this is the provider every avatar,
/// every post header and every comment resolves its author through. Cached
/// one-shot, a name or a photograph changed in Edit profile stayed wrong on
/// your own comments until the app was restarted (Grace's testers,
/// 2026-09-23). A profile document is small and the same listener is shared
/// by every widget showing that person.
final personProvider = StreamProvider.family<Person, String>((ref, id) {
  ref.keepCached();
  return ref
      .watch(profileRepositoryProvider)
      .watchPerson(id)
      .map((person) => person ?? (throw NotFoundException('person', id)));
});

final watchPersonProvider = StreamProvider.family<Person?, String>((ref, id) {
  return ref.watch(profileRepositoryProvider).watchPerson(id);
});

final purchasesProvider = StreamProvider<List<Purchase>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const <Purchase>[]);
  return ref.watch(commerceRepositoryProvider).watchPurchases(uid);
});

// ---------------------------------------------------------------- directory

/// littlebluecart.com: whether this account is joined to the directory, live.
final directoryLinkProvider = StreamProvider<DirectoryLink?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(directoryRepositoryProvider).watchLink();
});


/// littlebluecart.com's own categories, biggest first. Empty until the
/// public sync has run against this project, which is what hides the
/// "Browse the directory" rail rather than showing an empty one.
final directoryCategoriesProvider = StreamProvider<List<DirectoryCategory>>((
  ref,
) {
  return ref.watch(directoryRepositoryProvider).watchDirectoryCategories();
});

/// One category by slug, for a screen's title. Read off the rail's own list
/// rather than fetched again.
final directoryCategoryProvider = Provider.family<DirectoryCategory?, String>((
  ref,
  slug,
) {
  final all = ref.watch(directoryCategoriesProvider).value ?? const [];
  for (final category in all) {
    if (category.slug == slug) return category;
  }
  return null;
});

/// The first page of published listings in one category. Later pages are
/// asked for by the screen, which keeps what it has already shown.
final directoryCategoryPageProvider =
    FutureProvider.family<Page<DirectoryListing>, String>((ref, slug) {
      ref.keepCached();
      return ref.watch(directoryRepositoryProvider).listingsInCategory(slug);
    });

/// Directory businesses matching what was typed in the search screen.
final directorySearchProvider =
    FutureProvider.family<List<DirectoryListing>, String>((ref, query) {
      return ref.watch(directoryRepositoryProvider).searchDirectory(query);
    });
/// Orders from littlebluecart.com, newest first.
final directoryOrdersProvider = StreamProvider<List<DirectoryOrder>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const <DirectoryOrder>[]);
  return ref.watch(directoryRepositoryProvider).watchOrders();
});

/// This account's own directory listings, every status.
final myDirectoryListingsProvider = StreamProvider<List<DirectoryListing>>((
  ref,
) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const <DirectoryListing>[]);
  return ref.watch(directoryRepositoryProvider).watchMyListings();
});

/// The signed-in directory business's website-link products.
final myDirectoryProductsProvider = StreamProvider<List<Product>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const <Product>[]);
  return ref.watch(directoryRepositoryProvider).watchMyProducts();
});

/// Someone's website-link products, for their storefront.
final directoryProductsOfProvider =
    StreamProvider.family<List<Product>, String>((ref, ownerUid) {
      return ref.watch(directoryRepositoryProvider).watchProductsOf(ownerUid);
    });

/// One listing from the public mirror, live: the feed card reads it.
final directoryListingProvider =
    StreamProvider.family<DirectoryListing?, String>((ref, id) {
      return ref.watch(directoryRepositoryProvider).watchListing(id);
    });

/// Someone's published listings, for their public profile.
final directoryListingsOfProvider =
    StreamProvider.family<List<DirectoryListing>, String>((ref, ownerUid) {
      return ref
          .watch(directoryRepositoryProvider)
          .watchPublishedListingsOf(ownerUid);
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

  /// A query arriving from somewhere else: a tapped hashtag chip, a recent
  /// search, a suggestion.
  ///
  /// The scope comes with it. These filters are shared and sticky by design,
  /// so someone who had last set the chips to "Sellers" or "Type" then
  /// tapped a hashtag on a profile searched *that* scope and found nothing —
  /// which is exactly what a tester reported about profile hashtags
  /// (Grace, 2026-09-23). A query the person did not type carries its own
  /// scope; the chips are still theirs to change afterwards.
  void openQuery(String query) =>
      state = state.copyWith(query: query, scope: scopeFor(query));
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

/// Listings near the person, nearest first, for the feed's Near me view.
///
/// A family over the whole [SearchFilters] rather than over a point, so the
/// radius chips re-run it and the value equality on SearchFilters stops every
/// rebuild looking like a new search.
final nearbyProductsProvider =
    FutureProvider.family<List<Product>, SearchFilters>((ref, filters) {
      final origin = filters.origin;
      if (!filters.isGeoConstrained || origin == null) {
        return Future.value(const <Product>[]);
      }
      return ref
          .watch(catalogRepositoryProvider)
          .nearby(
            lat: origin.lat,
            lng: origin.lng,
            radiusMiles: filters.radiusMiles,
          );
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

// ---------------------------------------------------------------- messaging

final chatroomProvider = StreamProvider<List<Message>>((ref) {
  final blocked = _blocked(ref);
  return ref.watch(messagingRepositoryProvider).watchChatroom().map(
    (messages) => [
      for (final message in messages)
        if (!blocked.contains(message.authorId)) message,
    ],
  );
});

final inboxProvider = StreamProvider<List<Conversation>>((ref) {
  final blocked = _blocked(ref);
  // A one-to-one thread with somebody blocked leaves the inbox whole.
  return ref.watch(messagingRepositoryProvider).watchInbox().map(
    (conversations) => [
      for (final conversation in conversations)
        if (!conversation.participantIds.any(blocked.contains)) conversation,
    ],
  );
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
  final blocked = _blocked(ref);
  return ref.watch(socialRepositoryProvider).watchThreads(forumId).map(
    (threads) => [
      for (final thread in threads)
        if (!blocked.contains(thread.authorId)) thread,
    ],
  );
});

final threadProvider = StreamProvider.family<ForumThread, String>((ref, id) {
  return ref.watch(socialRepositoryProvider).watchThread(id);
});

final threadCommentsProvider =
    StreamProvider.family<List<ThreadComment>, String>((ref, threadId) {
      final blocked = _blocked(ref);
      return ref
          .watch(socialRepositoryProvider)
          .watchThreadComments(threadId)
          .map(
            (comments) => [
              for (final comment in comments)
                if (!blocked.contains(comment.authorId)) comment,
            ],
          );
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
