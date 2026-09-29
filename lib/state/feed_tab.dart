import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'providers.dart';
import 'session.dart';
import 'tags.dart';

/// Which way into the feed is showing.
///
/// Following comes first now (Grace, 2026-09-29). It was removed in the
/// redesign because tags were not followable yet, so it could only ever
/// filter by people and on a young market that is an empty screen most of
/// the time. Tags are followable, so it has something to show.
enum FeedTab { following, forYou, nearMe }

/// Where a person lands, given whether they follow anything. Pure.
///
/// Following first, but never as an empty room: somebody who follows nobody
/// and no tags opens on For you, which is the difference between "your feed"
/// and "a blank screen with tabs above it".
FeedTab initialFeedTab({required bool followsAnything}) =>
    followsAnything ? FeedTab.following : FeedTab.forYou;

/// Whether a post belongs in Following. Pure.
///
/// A post you follow the author of, or one carrying a tag you follow. The
/// tag half is matched by key, so `#WomanOwned` and `#womanowned` are one
/// tag here as everywhere else.
bool isFollowedPost(
  Post post, {
  required Set<String> people,
  required Set<String> tagKeys,
}) {
  if (people.contains(post.authorId)) return true;
  return post.tags.any((tag) => tagKeys.contains(tagKey(tag)));
}

/// The tab showing, remembered for as long as the app is open.
///
/// Not written to disk: a tab is where you are, not a setting, and one
/// restored from last week is disorienting. It starts from
/// [initialFeedTab] the first time it is read.
class FeedTabChoice extends Notifier<FeedTab?> {
  @override
  FeedTab? build() => null;

  void select(FeedTab tab) => state = tab;
}

final feedTabChoiceProvider =
    NotifierProvider<FeedTabChoice, FeedTab?>(FeedTabChoice.new);

/// Whether this person follows anybody or any tag.
final followsAnythingProvider = Provider<bool>((ref) {
  if (ref.watch(isGuestProvider)) return false;
  final people = ref.watch(followedPeopleProvider).value ?? const <String>{};
  final tags = ref.watch(followedTagsProvider).value ?? const <String>{};
  return people.isNotEmpty || tags.isNotEmpty;
});

/// The tab to draw: what was chosen, or where this person lands.
final feedTabProvider = Provider<FeedTab>((ref) {
  // Near me is a flag the search screen and the results screen share, so it
  // wins whenever it is on: the app must not say Near me is on in one place
  // and show For you in another.
  if (ref.watch(searchFiltersProvider).nearMe) return FeedTab.nearMe;
  return ref.watch(feedTabChoiceProvider) ??
      initialFeedTab(followsAnything: ref.watch(followsAnythingProvider));
});

/// The posts from the people and tags this person follows.
final followingFeedProvider = Provider<List<Post>>((ref) {
  final posts = ref.watch(feedProvider).value ?? const <Post>[];
  final people = ref.watch(followedPeopleProvider).value ?? const <String>{};
  final tags = {
    for (final tag in ref.watch(followedTagsProvider).value ?? const <String>{})
      tagKey(tag),
  };
  if (people.isEmpty && tags.isEmpty) return const [];
  return [
    for (final post in posts)
      if (isFollowedPost(post, people: people, tagKeys: tags)) post,
  ];
});

/// Everyone this person follows. Empty for a guest, who follows nobody.
final followedPeopleProvider = StreamProvider<Set<String>>((ref) {
  if (ref.watch(isGuestProvider)) return Stream.value(const {});
  return ref.watch(socialRepositoryProvider).watchFollowedPeople();
});
