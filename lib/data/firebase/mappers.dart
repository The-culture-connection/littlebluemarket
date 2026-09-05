import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/models.dart';

/// Firestore documents in, app models out.
///
/// Deliberately outside `models/`. Keeping the wire format apart from the
/// domain is what mechanically stops a backend type reaching a widget, and one
/// model can need two wire formats — a product read from the catalog mirror
/// and the same product read live from the commerce proxy do not look alike.
///
/// Every mapper is defensive. A document written by an older build, a
/// half-migrated field, a null where a number was expected: none of those
/// should crash a screen, so each field has a fallback and the shape of the
/// document is never assumed.
abstract final class FirestoreMappers {
  // ------------------------------------------------------------ primitives

  static String str(Object? value, [String fallback = '']) =>
      value is String ? value : fallback;

  static int integer(Object? value, [int fallback = 0]) => switch (value) {
    final int v => v,
    final double v => v.round(),
    final String v => int.tryParse(v) ?? fallback,
    _ => fallback,
  };

  static double decimal(Object? value, [double fallback = 0]) =>
      switch (value) {
        final num v => v.toDouble(),
        final String v => double.tryParse(v) ?? fallback,
        _ => fallback,
      };

  static bool boolean(Object? value, [bool fallback = false]) =>
      value is bool ? value : fallback;

  static List<String> strings(Object? value) => switch (value) {
    final List<dynamic> list => [
      for (final item in list)
        if (item is String) item,
    ],
    _ => const [],
  };

  /// A server timestamp, or the epoch.
  ///
  /// Firestore returns null for a `serverTimestamp()` that has not resolved
  /// yet — the local echo of a write you just made — so this cannot throw.
  static DateTime time(Object? value) => switch (value) {
    final Timestamp v => v.toDate(),
    final DateTime v => v,
    final int v => DateTime.fromMillisecondsSinceEpoch(v),
    _ => DateTime.fromMillisecondsSinceEpoch(0),
  };

  static DateTime? timeOrNull(Object? value) =>
      value == null ? null : time(value);

  // --------------------------------------------------------------- person

  static Person person(String id, Map<String, dynamic> data) => Person(
    id: id,
    name: str(data['name'], 'Someone'),
    handle: str(data['handle'], '@$id'),
    // Derived rather than stored, so a profile written by any client has a
    // stable, distinct avatar colour without anyone choosing one.
    tint: integer(data['tint'], tintFor(id)),
    bio: str(data['bio']),
    tags: strings(data['tags']),
    // The old field name is read until every profile has the new one.
    grossSalesCents: integer(data['grossSalesCents'] ?? data['revenueCents']),
    purchases: integer(data['purchaseCount']),
    posts: integer(data['postCount']),
    isSeller: boolean(data['isSeller']),
    avatarUrl: data['avatarUrl'] as String?,
    isLinked: data['linkedAt'] != null,
  );

  /// A deterministic avatar colour from a uid.
  ///
  /// Hue only: saturation and lightness are fixed so every generated tint sits
  /// in the same family as the hand-picked ones and stays readable under white
  /// initials.
  static int tintFor(String id) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    const palette = [
      0xFF5C8FCB,
      0xFFA78BC9,
      0xFFDB93A8,
      0xFFD96E9B,
      0xFF6FB5A6,
      0xFFD69B62,
      0xFF86B98C,
      0xFF93A9C4,
    ];
    return palette[hash % palette.length];
  }

  // -------------------------------------------------------------- catalog

  /// The catalog mirror: app-owned field names, maintained by the sync
  /// function. This is what makes the storefront replaceable — the schema is
  /// ours, not the provider's.
  static Product product(String id, Map<String, dynamic> data) => Product(
    id: id,
    title: str(data['title'], 'Untitled'),
    priceCents: integer(data['priceCents']),
    sellerId: str(data['sellerId']),
    tags: strings(data['tags']),
    rating: decimal(data['rating']),
    ratingCount: integer(data['ratingCount']),
    type: str(data['type']),
    description: str(data['description']),
    cityState: str(data['cityState']),
    lat: data['lat'] == null ? null : decimal(data['lat']),
    lng: data['lng'] == null ? null : decimal(data['lng']),
    freeShipping: boolean(data['freeShipping']),
    // The old field name is read until every product has been re-mirrored.
    saveCount: integer(data['saveCount'] ?? data['likeCount']),
    inCartsCount: integer(data['inCartsCount']),
    commentCount: integer(data['commentCount']),
    imageUrls: strings(data['imageUrls']),
    collectionHandles: strings(data['collectionHandles']),
  );

  static Collection collection(String handle, Map<String, dynamic> data) =>
      Collection(
        handle: handle,
        title: str(data['title'], handle),
        productCount: integer(data['productCount']),
        imageUrl: data['imageUrl'] is String
            ? data['imageUrl'] as String
            : null,
      );

  static Variant variant(Map<String, dynamic> data) => Variant(
    str(data['name'], 'Default'),
    integer(data['priceCents']),
    availableForSale: boolean(data['availableForSale'], true),
    quantityAvailable: data['quantityAvailable'] == null
        ? null
        : integer(data['quantityAvailable']),
    availabilityNote: data['availabilityNote'] as String?,
    variantId:
        data['variantId'] is String && (data['variantId'] as String).isNotEmpty
        ? data['variantId'] as String
        : null,
    sku: data['sku'] is String ? data['sku'] as String : null,
  );

  static SpecRow specRow(Map<String, dynamic> data) =>
      SpecRow(str(data['label']), str(data['value']));

  static ProductSpec spec(Map<String, dynamic> data) => ProductSpec(
    subtitle: str(data['subtitle']),
    lead: str(data['lead']),
    rows: _mapList(data['rows'], specRow),
    variants: _mapList(data['variants'], variant),
    shipping: _mapList(data['shipping'], specRow),
    returns: str(data['returns']),
  );

  // --------------------------------------------------------------- social

  static Review review(Map<String, dynamic> data) => Review(
    authorId: str(data['authorId']),
    rating: integer(data['rating'], 5).clamp(1, 5),
    createdAt: time(data['createdAt']),
    text: str(data['text']),
    tags: strings(data['tags']),
  );

  static RatingSummary rating(Map<String, dynamic> data) {
    final bars = <({int stars, int count})>[
      for (var stars = 5; stars >= 1; stars--)
        (stars: stars, count: integer(data['stars$stars'])),
    ];
    final total = bars.fold(0, (acc, bar) => acc + bar.count);
    final weighted = bars.fold(0, (acc, bar) => acc + bar.stars * bar.count);
    return RatingSummary(
      // Recomputed rather than read, so it can never disagree with the bars
      // underneath it.
      average: total == 0 ? 0 : weighted / total,
      bars: bars,
    );
  }

  /// A feed entry. The `kind` field decides which of the three it is; an
  /// unrecognised kind is skipped by the caller rather than guessed at.
  static Post? post(
    String id,
    Map<String, dynamic> data, {
    required bool likedByMe,
    Product? product,
  }) {
    final authorId = str(data['authorId']);
    final createdAt = time(data['createdAt']);
    final tags = strings(data['tags']);
    final likeCount = integer(data['likeCount']);
    final commentCount = integer(data['commentCount']);

    switch (str(data['kind'])) {
      case 'listing':
        if (product == null) return null;
        return ListingPost(
          id: id,
          authorId: authorId,
          createdAt: createdAt,
          tags: tags,
          likeCount: likeCount,
          commentCount: commentCount,
          likedByMe: likedByMe,
          product: product,
          caption: data['caption'] as String?,
        );
      case 'review':
        return ReviewPost(
          id: id,
          authorId: authorId,
          createdAt: createdAt,
          tags: tags,
          likeCount: likeCount,
          commentCount: commentCount,
          likedByMe: likedByMe,
          productId: str(data['productId']),
          rating: integer(data['rating'], 5).clamp(1, 5),
          text: str(data['text']),
          purchaseId: data['purchaseId'] as String?,
          imageUrls: strings(data['imageUrls']),
        );
      case 'cart':
        return CartPost(
          id: id,
          authorId: authorId,
          createdAt: createdAt,
          tags: tags,
          likeCount: likeCount,
          commentCount: commentCount,
          likedByMe: likedByMe,
          caption: data['caption'] as String?,
          items: [
            if (data['items'] is List)
              for (final row in data['items'] as List)
                if (row is Map)
                  CartPostItem(
                    productId: str(row['productId']),
                    title: str(row['title'], 'Untitled'),
                    sellerId: str(row['sellerId']),
                    priceCents: integer(row['priceCents']),
                    imageUrl: row['imageUrl'] is String
                        ? row['imageUrl'] as String
                        : null,
                  ),
          ],
        );
      case 'shoutout':
        return ShoutoutPost(
          id: id,
          authorId: authorId,
          createdAt: createdAt,
          tags: tags,
          likeCount: likeCount,
          commentCount: commentCount,
          likedByMe: likedByMe,
          text: str(data['text']),
          aboutSellerId: data['aboutSellerId'] as String?,
          imageUrls: strings(data['imageUrls']),
        );
      default:
        return null;
    }
  }

  static Comment comment(String id, Map<String, dynamic> data) => Comment(
    id: id,
    postId: str(data['postId']),
    authorId: str(data['authorId']),
    createdAt: time(data['createdAt']),
    text: str(data['text']),
    parentId: data['parentId'] as String?,
    likeCount: integer(data['likeCount']),
    likedByMe: boolean(data['likedByMe']),
  );

  static Forum forum(String id, Map<String, dynamic> data) => Forum(
    id: id,
    title: str(data['title'], 'Forum'),
    description: str(data['description']),
    memberCount: integer(data['memberCount']),
    threadCount: integer(data['threadCount']),
    tint: integer(data['tint'], tintFor(id)),
  );

  static ForumThread thread(String id, Map<String, dynamic> data) =>
      ForumThread(
        id: id,
        forumId: str(data['forumId']),
        authorId: str(data['authorId']),
        title: str(data['title']),
        body: str(data['body']),
        commentCount: integer(data['commentCount']),
        createdAt: time(data['createdAt']),
      );

  static ThreadComment threadComment(Map<String, dynamic> data) =>
      ThreadComment(
        authorId: str(data['authorId']),
        createdAt: time(data['createdAt']),
        text: str(data['text']),
        depth: data['parentId'] == null ? 0 : 1,
      );

  // ------------------------------------------------------------ messaging

  static Message message(String id, Map<String, dynamic> data) => Message(
    id: id,
    conversationId: str(data['conversationId']),
    authorId: str(data['authorId']),
    createdAt: time(data['createdAt']),
    text: str(data['text']),
    attachedProductId: data['attachedProductId'] as String?,
  );

  static Conversation conversation(
    String id,
    Map<String, dynamic> data, {
    required String uid,
  }) {
    final unreadByUser = data['unread'];
    return Conversation(
      id: id,
      participantIds: strings(data['participantIds']),
      lastMessageAt: time(data['lastMessageAt']),
      preview: str(data['preview']),
      // Unread is per participant, so it is a map keyed by uid rather than a
      // single number both sides would share.
      unread: unreadByUser is Map
          ? integer(unreadByUser[uid])
          : integer(unreadByUser),
    );
  }

  // -------------------------------------------------------- commerce ish

  static Address address(String id, Map<String, dynamic> data) => Address(
    id: id,
    name: str(data['name']),
    line1: str(data['line1']),
    line2: data['line2'] as String?,
    city: str(data['city']),
    region: str(data['region']),
    postalCode: str(data['postalCode']),
    countryCode: str(data['countryCode'], 'US'),
    phone: data['phone'] as String?,
    isDefault: boolean(data['isDefault']),
    lat: data['lat'] == null ? null : decimal(data['lat']),
    lng: data['lng'] == null ? null : decimal(data['lng']),
  );

  static Map<String, dynamic> addressToJson(Address address) => {
    'name': address.name,
    'line1': address.line1,
    if (address.line2 != null) 'line2': address.line2,
    'city': address.city,
    'region': address.region,
    'postalCode': address.postalCode,
    'countryCode': address.countryCode,
    if (address.phone != null) 'phone': address.phone,
    'isDefault': address.isDefault,
    if (address.lat != null) 'lat': address.lat,
    if (address.lng != null) 'lng': address.lng,
  };

  static Purchase purchase(String id, Map<String, dynamic> data) => Purchase(
    id: id,
    orderId: str(data['orderId']),
    productId: str(data['productId']),
    title: str(data['title']),
    purchasedAt: time(data['purchasedAt']),
    sellerId: str(data['sellerId']),
    imageUrl: data['imageUrl'] as String?,
    delivered: boolean(data['delivered']),
    reviewed: boolean(data['reviewed']),
  );

  static Shipment shipment(Map<String, dynamic> data) => Shipment(
    productId: str(data['productId']),
    counterpartyName: str(data['counterpartyName']),
    state: shipmentState(data['state']),
    tracking: str(data['tracking']),
    carrierNote: str(data['carrierNote']),
  );

  static ShipmentState shipmentState(Object? value) => switch (str(value)) {
    'inTransit' => ShipmentState.inTransit,
    'outForDelivery' => ShipmentState.outForDelivery,
    'delivered' => ShipmentState.delivered,
    _ => ShipmentState.labelCreated,
  };

  static List<T> _mapList<T>(
    Object? value,
    T Function(Map<String, dynamic>) convert,
  ) => switch (value) {
    final List<dynamic> list => [
      for (final item in list)
        if (item is Map) convert(Map<String, dynamic>.from(item)),
    ],
    _ => const [],
  };
}
