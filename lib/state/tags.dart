import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'providers.dart';
import 'session.dart';

/// Everything posted under one hashtag, by key.
final tagFeedProvider = StreamProvider.family<List<Post>, String>((ref, key) {
  return ref.watch(socialRepositoryProvider).watchTagFeed(key);
});

/// The things for sale under one hashtag, by key.
///
/// A tag page used to ask only the post stream, and on the real market that
/// is the wrong question: nothing in production had ever tagged a *post*,
/// because a product's hashtags live on the product. So a page for
/// #Handmade, with hundreds of handmade things on the market behind it,
/// showed nothing at all (Grace, 2026-09-28).
///
/// Asked through the search repository rather than with a new query,
/// because search already solved the half of this that is hard: a product
/// stores its tags as typed, and `_canonicalTag` looks the real spelling up
/// in `hashtags/{key}` before asking. One place that knows how a hashtag is
/// spelled is enough.
final tagProductsProvider = FutureProvider.family<List<Product>, String>((
  ref,
  key,
) async {
  if (key.isEmpty) return const [];
  final results = await ref
      .watch(searchRepositoryProvider)
      .search(SearchFilters(query: '#$key', scope: SearchScope.hashtags));
  return results.products;
});

/// The hashtags this person follows.
///
/// Empty for a guest: following is a thing you do with an account, and the
/// rules refuse the write anyway.
final followedTagsProvider = StreamProvider<Set<String>>((ref) {
  if (ref.watch(isGuestProvider)) return Stream.value(const {});
  return ref.watch(socialRepositoryProvider).watchFollowedTags();
});

/// The ones they also want told about.
final notifiedTagsProvider = StreamProvider<Set<String>>((ref) {
  if (ref.watch(isGuestProvider)) return Stream.value(const {});
  return ref.watch(socialRepositoryProvider).watchNotifiedTags();
});

/// How this hashtag is spelled, for showing. Falls back to the key.
///
/// Matching is case agnostic — `#This` and `#this` are one tag, keyed by
/// the lower-case form — but a page headed "#cantedithistory" is that key
/// leaking into the design. This is the spelling somebody actually wrote.
final tagSpellingProvider = FutureProvider.family<String, String>((
  ref,
  key,
) async {
  final stored = await ref.watch(catalogRepositoryProvider).tagSpelling(key);
  return stored ?? tagLabel(key);
});
