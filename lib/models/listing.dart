import 'package:flutter/foundation.dart';

/// Where a seller's draft is in its life.
///
/// `submitted` is the honest word for what happens when a seller taps Add:
/// the product exists on the store as a DRAFT and is waiting for the
/// merchant's approval. It is not in their shop yet, and the chip says so.
enum ListingStatus {
  draft('Draft'),
  submitting('Sending…'),
  submitted('Under review'),
  live('Live'),
  rejected('Not approved'),
  failed('Needs attention');

  const ListingStatus(this.label);
  final String label;

  static ListingStatus parse(String? value) => ListingStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => ListingStatus.draft,
  );

  /// Whether the seller may edit or retry it.
  bool get editable =>
      this == ListingStatus.draft ||
      this == ListingStatus.failed ||
      this == ListingStatus.rejected;
}

/// A seller's own product draft, the write-ahead log of Journey B.
///
/// Money is `int` cents from the first keystroke; see [parseDollars].
@immutable
class Listing {
  const Listing({
    required this.id,
    required this.sellerUid,
    required this.status,
    required this.title,
    required this.priceCents,
    required this.updatedAt,
    this.description = '',
    this.quantity = 0,
    this.sku,
    this.imageUrls = const [],
    this.collectionHandles = const [],
    this.tags = const [],
    this.error,
    this.shopifyProductId,
  });

  final String id;
  final String sellerUid;
  final ListingStatus status;
  final String title;
  final String description;
  final int priceCents;
  final int quantity;
  final String? sku;
  final List<String> imageUrls;
  final List<String> collectionHandles;
  final List<String> tags;

  /// Human-readable, from the publish function, when [status] is failed.
  final String? error;
  final String? shopifyProductId;
  final DateTime updatedAt;

  Listing copyWith({
    ListingStatus? status,
    String? error,
    String? shopifyProductId,
    DateTime? updatedAt,
    bool clearError = false,
  }) => Listing(
    id: id,
    sellerUid: sellerUid,
    status: status ?? this.status,
    title: title,
    description: description,
    priceCents: priceCents,
    quantity: quantity,
    sku: sku,
    imageUrls: imageUrls,
    collectionHandles: collectionHandles,
    tags: tags,
    error: clearError ? null : (error ?? this.error),
    shopifyProductId: shopifyProductId ?? this.shopifyProductId,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// What the Add product form hands to the repository. Single variant for
/// now; variants arrive with the edit path.
@immutable
class ListingDraft {
  const ListingDraft({
    required this.title,
    required this.priceCents,
    this.description = '',
    this.quantity = 1,
    this.trackQuantity = true,
    this.sku,
    this.weightGrams,
    this.imageUrls = const [],
    this.collectionHandles = const [],
    this.tags = const [],
  });

  final String title;
  final String description;
  final int priceCents;
  final int quantity;
  final bool trackQuantity;
  final String? sku;
  final int? weightGrams;
  final List<String> imageUrls;
  final List<String> collectionHandles;
  final List<String> tags;

  /// The rules' and the function's field names, exactly.
  Map<String, Object?> toMap() => {
    'title': title.trim(),
    'description': description.trim(),
    'priceCents': priceCents,
    'quantity': quantity,
    'trackQuantity': trackQuantity,
    'continueSellingOOS': false,
    'productType': 'physical',
    if (sku != null && sku!.trim().isNotEmpty) 'sku': sku!.trim(),
    if (weightGrams != null && weightGrams! > 0) 'weightGrams': weightGrams,
    'imageUrls': imageUrls,
    'collectionHandles': collectionHandles,
    'tags': tags,
  };
}

/// What the publish function answered.
@immutable
class PublishResult {
  const PublishResult({
    required this.shopifyProductId,
    this.adopted = false,
    this.stockSet = true,
  });

  final String shopifyProductId;

  /// True when a retry found the product the first attempt had already made.
  final bool adopted;

  /// False when the store's location could not be read, so opening stock was
  /// not set. The product still exists.
  final bool stockSet;
}

/// "8" → 800, "8.5" → 850, "$1,200.00" → 120000. Null for anything that is
/// not a price, including negatives and a third decimal.
int? parseDollars(String input) {
  final cleaned = input.replaceAll(RegExp(r'[\s$,]'), '');
  if (cleaned.isEmpty) return null;
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(cleaned);
  if (match == null) return null;
  final dollars = int.parse(match.group(1)!);
  final centsText = (match.group(2) ?? '').padRight(2, '0');
  return dollars * 100 + int.parse(centsText);
}
