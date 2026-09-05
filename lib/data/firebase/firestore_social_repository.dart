import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/models.dart';
import '../repositories/repositories.dart';
import 'firestore_errors.dart';
import 'mappers.dart';

/// Posts, likes, comments, reviews, forums and threads.
///
/// One rule runs through all of it: **counters move by increment, never by
/// writing a total.** Two people liking the same post in the same second must
/// produce two likes, and a read-modify-write loses one of them. The same goes
/// for member counts and comment counts.
///
/// The second rule: **a vote or a like is stated, not toggled.** The caller
/// says what it wants to be true; the repository works out the delta from what
/// is already stored. That is what makes a double tap idempotent.
class FirestoreSocialRepository implements SocialRepository {
  FirestoreSocialRepository({
    required FirebaseFirestore firestore,
    required this.uid,
  }) : _db = firestore;

  final FirebaseFirestore _db;
  final String? uid;

  String get _requireUid {
    final id = uid;
    if (id == null) throw const UnauthenticatedException();
    return id;
  }

  CollectionReference<Map<String, dynamic>> get _posts =>
      _db.collection('posts');
  CollectionReference<Map<String, dynamic>> get _catalog =>
      _db.collection('catalog');
  CollectionReference<Map<String, dynamic>> get _forums =>
      _db.collection('forums');
  CollectionReference<Map<String, dynamic>> get _threads =>
      _db.collection('threads');

  // --------------------------------------------------------------- the feed

  @override
  Stream<List<Post>> watchFeed({List<String> tags = const [], int limit = 20}) {
    Query<Map<String, dynamic>> query = _posts;
    if (tags.isNotEmpty) {
      // arrayContainsAny caps at 30 values.
      query = query.where('tags', arrayContainsAny: tags.take(30).toList());
    }
    return query
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .asyncMap(_hydrate)
        .guarded();
  }

  @override
  Future<Page<Post>> feedPage({String? cursor, int limit = 20}) =>
      guardFirestore(() async {
        var query = _posts.orderBy('createdAt', descending: true).limit(limit);
        if (cursor != null) {
          final anchor = await _posts.doc(cursor).get();
          if (anchor.exists) query = query.startAfterDocument(anchor);
        }
        final snapshot = await query.get();
        return Page(
          items: await _hydrate(snapshot),
          cursor: snapshot.docs.isEmpty ? null : snapshot.docs.last.id,
        );
      });

  /// Fills in the two things a post document does not carry: the listing a
  /// listing-post is about, and whether *this* viewer has liked it.
  ///
  /// Both are batched across the page rather than fetched per card, so a
  /// twenty-post feed is three round trips instead of forty-one.
  Future<List<Post>> _hydrate(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (snapshot.docs.isEmpty) return const [];

    final productIds = <String>{
      for (final doc in snapshot.docs)
        if (doc.data()['productId'] case final String id) id,
    };
    final products = await _productsByIds(productIds.toList());
    // There is no like on Little Blue Market (the cart is the like), so
    // nothing per viewer is looked up. The old collection-group query over
    // every likes subcollection was also one the rules never allowed.
    const liked = <String>{};

    return [
      for (final doc in snapshot.docs)
        ?FirestoreMappers.post(
          doc.id,
          doc.data(),
          likedByMe: liked.contains(doc.id),
          product: products[doc.data()['productId']],
        ),
    ];
  }

  Future<Map<String, Product>> _productsByIds(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final products = <String, Product>{};
    const chunkSize = 30;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(
        i,
        i + chunkSize > ids.length ? ids.length : i + chunkSize,
      );
      final snapshot = await _catalog
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        products[doc.id] = FirestoreMappers.product(doc.id, doc.data());
      }
    }
    return products;
  }

  @override
  Future<Post> post(String id) => guardFirestore(() async {
    final doc = await _posts.doc(id).get();
    final data = doc.data();
    if (data == null) throw NotFoundException('post', id);

    final productId = data['productId'];
    final product = productId is String
        ? (await _productsByIds([productId]))[productId]
        : null;
    const liked = false;

    final post = FirestoreMappers.post(
      doc.id,
      data,
      likedByMe: liked,
      product: product,
    );
    if (post == null) throw NotFoundException('post', id);
    return post;
  });

  @override
  Future<List<Post>> postsBy(String personId, {PostKind? kind}) =>
      guardFirestore(() async {
        var query = _posts.where('authorId', isEqualTo: personId);
        if (kind != null) query = query.where('kind', isEqualTo: kind.name);
        final snapshot = await query
            .orderBy('createdAt', descending: true)
            .limit(60)
            .get();
        return _hydrate(snapshot);
      });

  @override
  Future<String> createPost(NewPost draft) => guardFirestore(() async {
    final me = _requireUid;
    final doc = _posts.doc();

    await doc.set({
      'kind': draft.kind.name,
      'authorId': me,
      'tags': draft.tags,
      'likeCount': 0,
      'commentCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      if (draft.productId != null) 'productId': draft.productId,
      if (draft.caption != null) 'caption': draft.caption,
      if (draft.text != null) 'text': draft.text,
      if (draft.rating != null) 'rating': draft.rating,
      if (draft.purchaseId != null) 'purchaseId': draft.purchaseId,
      if (draft.aboutSellerId != null) 'aboutSellerId': draft.aboutSellerId,
      if (draft.imageUrls.isNotEmpty) 'imageUrls': draft.imageUrls,
      // A cart post: the items frozen now, and the count the rules check.
      if (draft.kind == PostKind.cart) ...{
        'items': [
          for (final item in draft.items.take(CartPost.maxItems))
            {
              'productId': item.productId,
              'title': item.title,
              'imageUrl': item.imageUrl,
              'sellerId': item.sellerId,
              'priceCents': item.priceCents,
            },
        ],
        'itemCount': draft.items.take(CartPost.maxItems).length,
      },
    });
    return doc.id;
  });

  @override
  Future<void> deletePost(String id) =>
      guardFirestore(() => _posts.doc(id).delete());

  @override
  Future<void> setLike(String postId, bool liked) => guardFirestore(() async {
    final me = _requireUid;
    // The like document is keyed by uid, so it exists at most once per person
    // however many times the button is tapped.
    final like = _posts.doc(postId).collection('likes').doc(me);
    final post = _posts.doc(postId);

    await _db.runTransaction((tx) async {
      final existing = await tx.get(like);
      if (existing.exists == liked) return; // already in the wanted state

      if (liked) {
        tx.set(like, {
          'uid': me,
          'postId': postId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        tx.delete(like);
      }
      tx.update(post, {'likeCount': FieldValue.increment(liked ? 1 : -1)});
    });
  });

  // -------------------------------------------------------------- comments

  @override
  Stream<List<Comment>> watchComments(String postId) => _posts
      .doc(postId)
      .collection('comments')
      .orderBy('createdAt')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => FirestoreMappers.comment(doc.id, doc.data()))
            .toList(),
      )
      .guarded();

  @override
  Future<void> addComment({
    required String postId,
    required String text,
    String? parentId,
  }) => guardFirestore(() async {
    final me = _requireUid;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final batch = _db.batch();
    batch.set(_posts.doc(postId).collection('comments').doc(), {
      'postId': postId,
      'authorId': me,
      'text': trimmed,
      'parentId': ?parentId,
      'likeCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_posts.doc(postId), {'commentCount': FieldValue.increment(1)});
    await batch.commit();
  });

  @override
  Future<void> setCommentLike(String commentId, bool liked) => guardFirestore(
    () async {
      final me = _requireUid;
      // Comment ids are unique across posts, so a collection-group lookup
      // finds the one document without needing its parent post id.
      final found = await _db
          .collectionGroup('comments')
          .where(FieldPath.documentId, isEqualTo: commentId)
          .limit(1)
          .get();
      if (found.docs.isEmpty) throw NotFoundException('comment', commentId);

      final comment = found.docs.first.reference;
      final like = comment.collection('likes').doc(me);

      await _db.runTransaction((tx) async {
        final existing = await tx.get(like);
        if (existing.exists == liked) return;
        liked ? tx.set(like, {'uid': me}) : tx.delete(like);
        tx.update(comment, {'likeCount': FieldValue.increment(liked ? 1 : -1)});
      });
    },
  );

  // --------------------------------------------------------------- reviews

  @override
  Stream<List<Review>> watchReviews(String productId) => _catalog
      .doc(productId)
      .collection('reviews')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => FirestoreMappers.review(doc.data()))
            .toList(),
      )
      .guarded();

  @override
  Stream<RatingSummary> watchRating(String productId) => _catalog
      .doc(productId)
      .collection('rating')
      .doc('summary')
      .snapshots()
      .map((doc) => FirestoreMappers.rating(doc.data() ?? const {}))
      .guarded();

  @override
  Future<void> addReview(NewReview draft) => guardFirestore(() async {
    final me = _requireUid;
    final product = _catalog.doc(draft.productId);
    final rating = draft.rating.clamp(1, 5);

    final batch = _db.batch();
    batch.set(product.collection('reviews').doc(), {
      'authorId': me,
      'rating': rating,
      'text': draft.text.trim(),
      'tags': draft.tags,
      if (draft.purchaseId != null) 'purchaseId': draft.purchaseId,
      if (draft.imageUrls.isNotEmpty) 'imageUrls': draft.imageUrls,
      'createdAt': FieldValue.serverTimestamp(),
    });
    // The histogram is a set of counters, so a new review nudges one bar
    // rather than recomputing the distribution.
    batch.set(product.collection('rating').doc('summary'), {
      'stars$rating': FieldValue.increment(1),
    }, SetOptions(merge: true));

    if (draft.purchaseId != null) {
      // Marks the purchase reviewed, so the composer stops offering it and the
      // profile badge is data rather than grid position.
      batch.set(
        _db
            .collection('users')
            .doc(me)
            .collection('purchases')
            .doc(draft.purchaseId),
        {'reviewed': true},
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  });

  @override
  Future<List<TaggedReview>> reviewsTagged(String tag, {int limit = 20}) =>
      guardFirestore(() async {
        final snapshot = await _db
            .collectionGroup('reviews')
            .where('tags', arrayContains: tag)
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .get();
        return [
          for (final doc in snapshot.docs)
            TaggedReview(
              // The parent of a review's collection is its product.
              productId: doc.reference.parent.parent?.id ?? '',
              review: FirestoreMappers.review(doc.data()),
            ),
        ];
      });

  // ---------------------------------------------------------------- forums

  @override
  Stream<List<Forum>> watchForums() => _forums
      .orderBy('memberCount', descending: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => FirestoreMappers.forum(doc.id, doc.data()))
            .toList(),
      )
      .guarded();

  @override
  Stream<Forum> watchForum(String id) => _forums.doc(id).snapshots().map((doc) {
    final data = doc.data();
    if (data == null) throw NotFoundException('forum', id);
    return FirestoreMappers.forum(doc.id, data);
  }).guarded();

  @override
  Future<String> createForum(NewForum draft) => guardFirestore(() async {
    final me = _requireUid;
    final title = draft.title.trim();
    if (title.isEmpty) {
      throw const ValidationException('Name your forum', field: 'title');
    }

    final doc = _forums.doc();
    final batch = _db.batch();
    batch.set(doc, {
      'title': title,
      'description': draft.description.trim(),
      'tags': draft.tags,
      'createdBy': me,
      // You are the first member of a forum you create.
      'memberCount': 1,
      'threadCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(doc.collection('members').doc(me), {
      'joinedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return doc.id;
  });

  @override
  Future<void> setForumMembership(String forumId, bool joined) =>
      guardFirestore(() async {
        final me = _requireUid;
        final forum = _forums.doc(forumId);
        final membership = forum.collection('members').doc(me);

        await _db.runTransaction((tx) async {
          final existing = await tx.get(membership);
          if (existing.exists == joined) return;

          joined
              ? tx.set(membership, {'joinedAt': FieldValue.serverTimestamp()})
              : tx.delete(membership);
          tx.update(forum, {
            'memberCount': FieldValue.increment(joined ? 1 : -1),
          });
        });
      });

  @override
  Stream<bool> watchForumMembership(String forumId) {
    final me = uid;
    if (me == null) return Stream.value(false);
    return _forums
        .doc(forumId)
        .collection('members')
        .doc(me)
        .snapshots()
        .map((doc) => doc.exists)
        .guarded();
  }

  // --------------------------------------------------------------- threads

  @override
  Stream<List<ForumThread>> watchThreads(String forumId) => _threads
      .where('forumId', isEqualTo: forumId)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => FirestoreMappers.thread(doc.id, doc.data()))
            .toList(),
      )
      .guarded();

  @override
  Stream<ForumThread> watchThread(String id) =>
      _threads.doc(id).snapshots().map((doc) {
        final data = doc.data();
        if (data == null) throw NotFoundException('thread', id);
        return FirestoreMappers.thread(doc.id, data);
      }).guarded();

  @override
  Future<String> createThread(NewThread draft) => guardFirestore(() async {
    final me = _requireUid;
    final title = draft.title.trim();
    if (title.isEmpty) {
      throw const ValidationException(
        'Give your thread a title',
        field: 'title',
      );
    }

    final doc = _threads.doc();
    final batch = _db.batch();
    batch.set(doc, {
      'forumId': draft.forumId,
      'authorId': me,
      'title': title,
      'body': draft.body.trim(),
      'commentCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_forums.doc(draft.forumId), {
      'threadCount': FieldValue.increment(1),
    });
    await batch.commit();
    return doc.id;
  });

  @override
  Stream<List<ThreadComment>> watchThreadComments(String threadId) => _threads
      .doc(threadId)
      .collection('comments')
      .orderBy('createdAt')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => FirestoreMappers.threadComment(doc.data()))
            .toList(),
      )
      .guarded();

  @override
  Future<void> addThreadComment({
    required String threadId,
    required String text,
    String? parentId,
  }) => guardFirestore(() async {
    final me = _requireUid;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final batch = _db.batch();
    batch.set(_threads.doc(threadId).collection('comments').doc(), {
      'threadId': threadId,
      'authorId': me,
      'text': trimmed,
      'parentId': ?parentId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_threads.doc(threadId), {
      'commentCount': FieldValue.increment(1),
    });
    await batch.commit();
  });
}
