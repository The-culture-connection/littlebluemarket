import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'providers.dart';
import 'session.dart';

/// Everything posted under one hashtag, by key.
final tagFeedProvider = StreamProvider.family<List<Post>, String>((ref, key) {
  return ref.watch(socialRepositoryProvider).watchTagFeed(key);
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
