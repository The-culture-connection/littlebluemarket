/// The seam.
///
/// Everything above this line — screens, widgets, providers — talks to these
/// interfaces and to the app's own models. Everything below is a detail that
/// can be replaced: fixtures today, Firestore and a Shopify proxy next, and
/// something else after that.
///
/// Two rules keep the seam real, and both are worth more than they look:
///
///  1. **Nothing in this directory may import Firebase, Shopify, or Flutter.**
///     It is plain Dart over plain models. If a backend type ever appears in a
///     signature here, the swap has already failed.
///  2. **Screens never import an implementation.** They resolve a repository
///     through a provider, so one flag moves the whole app between backends.
///
/// Interfaces are split by what changes together, not by what reads together.
/// [SearchRepository] is separate from [CatalogRepository] because search is
/// the piece most likely to move to a dedicated index while the catalog stays
/// put. [CommerceRepository] is separate from everything because it is the
/// piece that is meant to be thrown away.
library;

import '../../models/models.dart';

export 'exceptions.dart';

/// Listings, as the app reads them.
///
/// Backed by a Firestore mirror of the storefront rather than by live provider
/// calls: the feed, the grids and search are then one cheap query that works
/// offline, and the mirror is already the catalog on the day the provider goes
/// away. Only [liveVariants] asks the provider anything.
abstract interface class CatalogRepository {
  /// Throws [NotFoundException] rather than substituting another product.
  Future<Product> product(String id);

  Future<ProductSpec> spec(String id);

  /// Ordered to match [ids]; ids that no longer exist are skipped rather than
  /// throwing, because a stale feed reference should not blank a whole screen.
  Future<List<Product>> productsByIds(List<String> ids);

  Future<Page<Product>> productsBySeller(String sellerId, {String? cursor});

  /// Authoritative price and stock, straight from the provider. The only read
  /// that must not be served from the mirror, because overselling is worse
  /// than a spinner.
  Future<List<Variant>> liveVariants(String productId);

  Future<List<TagCount>> popularTags({int limit = 8});
}

/// Query, facets, and the radius filter.
abstract interface class SearchRepository {
  Future<SearchResults> search(SearchFilters filters, {String? cursor});

  Future<List<String>> recentSearches();
  Future<void> recordSearch(String query);
  Future<void> removeRecentSearch(String query);
  Future<void> clearRecentSearches();
}

/// Cart, checkout handoff, and order history.
///
/// The interface the whole Shopify-is-removable requirement rests on. Note what
/// is absent: no method reports that a purchase succeeded. The app cannot
/// observe a hosted checkout completing, so success arrives asynchronously
/// through the order pipeline instead.
abstract interface class CommerceRepository {
  Stream<Cart> watchCart();

  /// [variantId] null means the default (first) variant, which is what the
  /// feed's add-to-cart has: a product, and no variant picker in sight.
  Future<Cart> addLine({
    required String productId,
    String? variantId,
    int quantity = 1,
  });

  Future<Cart> updateLine({required String lineId, required int quantity});
  Future<Cart> removeLine(String lineId);
  Future<Cart> clearCart();

  /// Hands the cart to whoever takes the money, tagged so the resulting order
  /// can be attributed back to this account.
  Future<CheckoutHandoff> beginCheckout();

  Future<Page<Order>> orders({String? cursor});
  Future<Order> order(String id);

  /// What this account has bought — the profile grid, and the list the review
  /// composer picks from.
  Stream<List<Purchase>> watchPurchases(String uid);
}

/// Posts, likes, comments, reviews, forums, threads. Everything social.
abstract interface class SocialRepository {
  Stream<List<Post>> watchFeed({List<String> tags = const [], int limit = 20});
  Future<Page<Post>> feedPage({String? cursor, int limit = 20});
  Future<Post> post(String id);
  Future<List<Post>> postsBy(String personId, {PostKind? kind});
  Future<String> createPost(NewPost draft);
  Future<void> deletePost(String id);

  /// Idempotent by design: called with the state the person wants, not a
  /// toggle, so a double tap cannot leave the count off by one.
  Future<void> setLike(String postId, bool liked);

  Stream<List<Comment>> watchComments(String postId);
  Future<void> addComment({
    required String postId,
    required String text,
    String? parentId,
  });
  Future<void> setCommentLike(String commentId, bool liked);

  Stream<List<Review>> watchReviews(String productId);
  Stream<RatingSummary> watchRating(String productId);
  Future<void> addReview(NewReview draft);
  Future<List<TaggedReview>> reviewsTagged(String tag, {int limit = 20});

  Stream<List<Forum>> watchForums();
  Stream<Forum> watchForum(String id);
  Future<String> createForum(NewForum draft);
  Future<void> setForumMembership(String forumId, bool joined);
  Stream<bool> watchForumMembership(String forumId);

  Stream<List<ForumThread>> watchThreads(String forumId);
  Stream<ForumThread> watchThread(String id);
  Future<String> createThread(NewThread draft);
  Stream<List<ThreadComment>> watchThreadComments(String threadId);
  Future<void> addThreadComment({
    required String threadId,
    required String text,
    String? parentId,
  });
}

/// The open chatroom and one-to-one threads.
abstract interface class MessagingRepository {
  Stream<List<Message>> watchChatroom({int limit = 100});
  Future<void> sendToChatroom(String text);

  Stream<List<Conversation>> watchInbox();

  /// Find-or-create. Resolve it at the inbox row rather than on the message
  /// screen, so opening a thread is not gated on a round trip.
  Future<String> conversationWith(String personId);

  Stream<List<Message>> watchConversation(String conversationId);
  Future<void> send({
    required String conversationId,
    required String text,
    String? attachedProductId,
  });
  Future<void> markRead(String conversationId);
}

/// Profiles, avatars, addresses.
abstract interface class ProfileRepository {
  /// Emits null when no profile exists yet — the state between authenticating
  /// and finishing setup.
  Stream<Person?> watchPerson(String id);

  Future<Person> person(String id);
  Future<List<Person>> people(List<String> ids);

  /// Seller lookup for @-mentions in a shoutout.
  Future<List<Person>> searchPeople(String query, {int limit = 10});

  Future<void> updateProfile(ProfileEdit edit);
  Future<String> uploadAvatar(List<int> bytes, {required String contentType});
  Future<bool> handleAvailable(String handle);

  /// Claims a vendor record with a merchant-issued code.
  ///
  /// The **only** way to become a seller. It replaced `becomeSeller()`,
  /// which wrote `isSeller: true` straight from the client — and since the
  /// order pipeline credits a sale to whichever account claims a vendor
  /// name, that was two writes away from inheriting a stranger's catalogue
  /// and their revenue.
  ///
  /// Everything is decided server-side. Throws [ValidationException] with
  /// copy specific to the failure — an unknown code, a used one, an expired
  /// one, a vendor already claimed, or an unverified email — because those
  /// mean genuinely different things and three of them are actionable.
  Future<SellerGrant> requestSellerStatus(String claimCode);

  /// Matches this account to the store by its **verified** email: the
  /// existing customer record and past orders, and the vendor record if the
  /// email belongs to one. The session calls it once per account; it is
  /// idempotent on the backend, so a retry costs nothing.
  Future<LinkResult> linkStoreAccounts();

  Future<List<Address>> addresses();
  Future<void> saveAddress(Address address);
  Future<void> deleteAddress(String id);
}

/// Shipments, in both directions.
abstract interface class FulfillmentRepository {
  Stream<List<Shipment>> watchSending();
  Stream<List<Shipment>> watchReceiving();

  /// A seller marking an order shipped. The write that reaches the fulfilment
  /// provider.
  Future<void> addTracking({
    required String orderId,
    required String trackingNumber,
    required String carrier,
  });
}

/// The dev Diagnostics screen: who the phone thinks it is, and whether the
/// backend can reach what it needs. Debug builds only; nothing a screen
/// depends on.
abstract interface class DiagnosticsRepository {
  Future<HealthReport> healthCheck();
  Future<AuthFacts> authFacts();
}

/// A profile edit. Only the fields a person may change themselves — notably
/// not revenue or purchase counts, which only the order pipeline may write.
class ProfileEdit {
  const ProfileEdit({
    this.name,
    this.handle,
    this.bio,
    this.tags,
    this.avatarUrl,
  });

  final String? name;
  final String? handle;
  final String? bio;
  final List<String>? tags;
  final String? avatarUrl;
}

class NewForum {
  const NewForum({
    required this.title,
    required this.description,
    this.tags = const [],
  });

  final String title;
  final String description;
  final List<String> tags;
}

class NewThread {
  const NewThread({
    required this.forumId,
    required this.title,
    required this.body,
  });

  final String forumId;
  final String title;
  final String body;
}
