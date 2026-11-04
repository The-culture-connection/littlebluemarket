import '../analytics/analytics.dart';
import '../models/models.dart';
import 'auth/auth_service.dart';
import 'firebase/firebase_auth_service.dart';
import 'firebase/firestore_account_repository.dart';
import 'firebase/firestore_directory_repository.dart';
import 'firebase/firestore_messaging_repository.dart';
import 'firebase/firestore_profile_repository.dart';
import 'firebase/firestore_promo_repository.dart';
import 'firebase/firestore_report_repository.dart';
import 'firebase/firestore_search_repository.dart';
import 'firebase/firestore_social_repository.dart';
import 'repositories/repositories.dart';
import 'shopify/commerce_proxy_repository.dart';

/// The live repositories, each recording its actions for [Analytics] once
/// they have succeeded (Grace, 2026-11-04: "record all user events").
///
/// Recorded here, at the one place each action happens, rather than at
/// every button that leads to it: a product can be added to the cart from
/// the feed, its page, a shared cart and a post, and every one of those is
/// counted without remembering to. Only what succeeded is recorded; a
/// refused or failed action is not something the person did.
///
/// What is recorded is ids and counts, never message text, a review's
/// words or an address.
Future<T> _tracked<T>(
  String name,
  Map<String, Object?> props,
  Future<T> action,
) async {
  final result = await action;
  Analytics.track(name, props);
  return result;
}

class TrackedCommerceRepository extends CommerceProxyRepository {
  TrackedCommerceRepository({
    required super.functions,
    required super.firestore,
    required super.uid,
  });

  @override
  Future<Cart> addLine({
    required String productId,
    String? variantId,
    int quantity = 1,
  }) => _tracked(
    'add_to_cart',
    {'productId': productId, 'variantId': variantId, 'quantity': quantity},
    super.addLine(
      productId: productId,
      variantId: variantId,
      quantity: quantity,
    ),
  );

  @override
  Future<AddManyResult> addManyLines(List<String> productIds) => _tracked(
    'add_many_to_cart',
    {'productIds': productIds.join(','), 'count': productIds.length},
    super.addManyLines(productIds),
  );

  @override
  Future<Cart> removeLine(String lineId) => _tracked('remove_from_cart', {
    'lineId': lineId,
  }, super.removeLine(lineId));

  @override
  Future<Cart> saveForLater(String lineId) => _tracked('save_for_later', {
    'lineId': lineId,
  }, super.saveForLater(lineId));

  @override
  Future<CheckoutHandoff> beginCheckout({int? roundUpCents}) => _tracked(
    'checkout_start',
    {'roundUpCents': roundUpCents},
    super.beginCheckout(roundUpCents: roundUpCents),
  );

  @override
  Future<CheckoutHandoff> chipIn({required int amountCents}) => _tracked(
    'chip_in_start',
    {'amountCents': amountCents},
    super.chipIn(amountCents: amountCents),
  );

  @override
  Future<CheckoutHandoff> buyNow({
    required String productId,
    String? variantId,
    int quantity = 1,
  }) => _tracked(
    'buy_now',
    {'productId': productId, 'variantId': variantId, 'quantity': quantity},
    super.buyNow(
      productId: productId,
      variantId: variantId,
      quantity: quantity,
    ),
  );

  @override
  Future<Membership> verifyMembership({
    required String store,
    required String receipt,
  }) => _tracked('membership_purchase', {
    'store': store,
  }, super.verifyMembership(store: store, receipt: receipt));
}

class TrackedSocialRepository extends FirestoreSocialRepository {
  TrackedSocialRepository({
    required super.firestore,
    required super.storage,
    required super.uid,
  });

  @override
  Future<String> createPost(NewPost draft) async {
    final id = await super.createPost(draft);
    Analytics.track('post_create', {
      'postId': id,
      'kind': draft.kind.name,
      'productId': draft.productId,
    });
    return id;
  }

  @override
  Future<void> deletePost(String id) =>
      _tracked('post_delete', {'postId': id}, super.deletePost(id));

  @override
  Future<void> setLike(String postId, bool liked) => _tracked(
    liked ? 'post_like' : 'post_unlike',
    {'postId': postId},
    super.setLike(postId, liked),
  );

  @override
  Future<void> addComment({
    required String postId,
    required String text,
    String? parentId,
  }) => _tracked('comment_create', {
    'postId': postId,
    'reply': parentId != null,
  }, super.addComment(postId: postId, text: text, parentId: parentId));

  @override
  Future<void> setCommentLike(String postId, String commentId, bool liked) =>
      _tracked(
        liked ? 'comment_like' : 'comment_unlike',
        {'postId': postId, 'commentId': commentId},
        super.setCommentLike(postId, commentId, liked),
      );

  @override
  Future<void> setFollowing(String personId, bool on) => _tracked(
    on ? 'follow' : 'unfollow',
    {'personId': personId},
    super.setFollowing(personId, on),
  );

  @override
  Future<void> setFollowingTag(
    String tag, {
    required bool on,
    bool notify = false,
  }) => _tracked(
    on ? 'follow_tag' : 'unfollow_tag',
    {'tag': tag, 'notify': notify},
    super.setFollowingTag(tag, on: on, notify: notify),
  );

  @override
  Future<void> addReview(NewReview draft) => _tracked('review_create', {
    'productId': draft.productId,
  }, super.addReview(draft));

  @override
  Future<String> createForum(NewForum draft) async {
    final id = await super.createForum(draft);
    Analytics.track('forum_create', {'forumId': id});
    return id;
  }

  @override
  Future<void> setForumMembership(String forumId, bool joined) => _tracked(
    joined ? 'forum_join' : 'forum_leave',
    {'forumId': forumId},
    super.setForumMembership(forumId, joined),
  );

  @override
  Future<String> createThread(NewThread draft) async {
    final id = await super.createThread(draft);
    Analytics.track('thread_create', {
      'threadId': id,
      'forumId': draft.forumId,
      'products': draft.productIds.length,
      'mentions': draft.mentionedUids.length,
    });
    return id;
  }

  @override
  Future<void> addThreadComment({
    required String threadId,
    required String text,
    String? parentId,
    List<String> productIds = const [],
    List<String> mentionedUids = const [],
  }) => _tracked(
    'thread_reply',
    {
      'threadId': threadId,
      'reply': parentId != null,
      'products': productIds.length,
      'mentions': mentionedUids.length,
    },
    super.addThreadComment(
      threadId: threadId,
      text: text,
      parentId: parentId,
      productIds: productIds,
      mentionedUids: mentionedUids,
    ),
  );
}

class TrackedMessagingRepository extends FirestoreMessagingRepository {
  TrackedMessagingRepository({required super.firestore, required super.uid});

  @override
  Future<void> sendToChatroom(String text, {String? attachedProductId}) =>
      _tracked(
        'chat_message_send',
        {'productId': attachedProductId},
        super.sendToChatroom(text, attachedProductId: attachedProductId),
      );

  @override
  Future<void> send({
    required String conversationId,
    required String text,
    String? attachedProductId,
  }) => _tracked(
    'dm_send',
    {'conversationId': conversationId, 'productId': attachedProductId},
    super.send(
      conversationId: conversationId,
      text: text,
      attachedProductId: attachedProductId,
    ),
  );

  @override
  Future<void> setReaction(ReactionTarget target, String? emoji) => _tracked(
    emoji == null ? 'reaction_remove' : 'reaction_add',
    {'on': target.kind, 'emoji': emoji},
    super.setReaction(target, emoji),
  );
}

class TrackedProfileRepository extends FirestoreProfileRepository {
  TrackedProfileRepository({
    required super.firestore,
    required super.storage,
    required super.functions,
    required super.auth,
    required super.uid,
  });

  @override
  Future<void> updateProfile(ProfileEdit edit) =>
      _tracked('profile_update', const {}, super.updateProfile(edit));

  @override
  Future<SellerGrant> requestSellerStatus(String claimCode) =>
      _tracked('seller_claim', const {}, super.requestSellerStatus(claimCode));

  @override
  Future<LinkResult> linkStoreAccounts() =>
      _tracked('market_account_connect', const {}, super.linkStoreAccounts());
}

class TrackedReportRepository extends FirestoreReportRepository {
  TrackedReportRepository({
    required super.firestore,
    required super.functions,
    required super.uid,
  });

  @override
  Future<void> submit(NewReport draft) => _tracked('report_submit', {
    'kind': draft.kind.name,
    'reason': draft.reason.name,
    'subjectUid': draft.subjectUid,
    'postId': draft.postId,
  }, super.submit(draft));

  @override
  Future<void> blockUser(String uid) =>
      _tracked('block', {'personId': uid}, super.blockUser(uid));
}

class TrackedSearchRepository extends FirestoreSearchRepository {
  TrackedSearchRepository({required super.firestore, required super.uid});

  @override
  Future<void> recordSearch(String query) =>
      _tracked('search', {'q': query}, super.recordSearch(query));
}

class TrackedDirectoryRepository extends FirestoreDirectoryRepository {
  TrackedDirectoryRepository({
    required super.firestore,
    required super.functions,
    required super.uid,
  });

  @override
  Future<DirectoryLinkResult> link({bool auto = false}) => _tracked(
    'directory_account_link',
    {'auto': auto},
    super.link(auto: auto),
  );

  @override
  Future<void> reportPurchase(String productId) => _tracked(
    'directory_purchase_report',
    {'productId': productId},
    super.reportPurchase(productId),
  );

  @override
  Future<String> saveProduct(NewDirectoryProduct draft, {String? id}) async {
    final saved = await super.saveProduct(draft, id: id);
    Analytics.track('directory_product_save', {
      'productId': saved,
      'edit': id != null,
    });
    return saved;
  }
}

class TrackedPromoRepository extends FirestorePromoRepository {
  TrackedPromoRepository({required super.firestore, required super.functions});

  @override
  Future<void> recordSeen(String id) {
    Analytics.track('promo_seen', {'promoId': id});
    return super.recordSeen(id);
  }

  @override
  Future<void> recordTap(String id) {
    Analytics.track('promo_tap', {'promoId': id});
    return super.recordTap(id);
  }
}

class TrackedAccountRepository extends FirestoreAccountRepository {
  TrackedAccountRepository({
    required super.firestore,
    required super.functions,
  });

  @override
  Future<void> requestDeletion(NewDeletionRequest draft) => _tracked(
    'account_delete_request',
    const {},
    super.requestDeletion(draft),
  );
}

class TrackedAuthService extends FirebaseAuthService {
  TrackedAuthService(super.auth, {super.functions});

  @override
  Future<AuthUser> signUpWithPassword({
    required String email,
    required String password,
  }) => _tracked(
    'sign_up',
    const {},
    super.signUpWithPassword(email: email, password: password),
  );

  @override
  Future<AuthUser> signInWithPassword({
    required String email,
    required String password,
  }) => _tracked(
    'sign_in',
    const {},
    super.signInWithPassword(email: email, password: password),
  );

  @override
  Future<void> continueAsGuest() =>
      _tracked('continue_as_guest', const {}, super.continueAsGuest());

  @override
  Future<void> signOut() async {
    // Before, so it goes out under the account it belongs to.
    Analytics.track('sign_out');
    await Analytics.flush();
    await super.signOut();
  }
}
