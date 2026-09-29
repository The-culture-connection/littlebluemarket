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

/// Every tag a post carries, its product included.
///
/// A listing post written by the catalogue mirror carries **no tags of
/// its own**: the hashtags are on the product. The tag pages have always
/// read both sources for this reason, and Following did not, which is why
/// following a tag showed nothing on the live market while the same tag
/// had a full page of its own (Grace, 2026-09-29).
Iterable<String> tagsOn(Post post) sync* {
  yield* post.tags;
  if (post is ListingPost) yield* post.product.tags;
}

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
  return tagsOn(post).any((tag) => tagKeys.contains(tagKey(tag)));
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

/// How many of each we will ask about.
///
/// One query per followed person and per followed tag, so this is a cap on
/// round trips rather than on taste. Twenty makers and ten tags is more
/// than anybody follows today and still a bounded number of reads.
const kFollowedPeopleQueried = 20;
const kFollowedTagsQueried = 10;

/// What the people you follow have posted.
///
/// **Asked for, not sifted out.** This used to filter the main feed, which
/// is the newest twenty posts on the whole market: on a market this size a
/// maker you follow is almost never in that twenty, so Following was empty
/// no matter how many people you followed (Grace, 2026-09-29). It asks for
/// their posts now, the way a profile does.
final followedPeoplePostsProvider = Provider<List<Post>>((ref) {
  final people = ref.watch(followedPeopleProvider).value ?? const <String>{};
  if (people.isEmpty) return const [];
  final blocked =
      ref.watch(blockedUidsProvider).value ?? const <String>{};
  final out = <String, Post>{};
  for (final uid in people.take(kFollowedPeopleQueried)) {
    if (blocked.contains(uid)) continue;
    for (final post in ref.watch(postsByProvider(uid)).value ?? const []) {
      out[post.id] = post;
    }
  }
  final posts = out.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return posts;
});

/// What is on the market under the tags you follow.
///
/// Products rather than posts, and that is not a shortcut: a hashtag on
/// this market lives on the **product**, not on the post about it. It is
/// the same question a tag page asks, through the same provider, so a tag
/// in Following shows exactly what its own page shows.
final followedTagProductsProvider = Provider<List<Product>>((ref) {
  final tags = ref.watch(followedTagsProvider).value ?? const <String>{};
  if (tags.isEmpty) return const [];
  final out = <String, Product>{};
  for (final tag in tags.take(kFollowedTagsQueried)) {
    final key = tagKey(tag);
    if (key.isEmpty) continue;
    for (final product in ref.watch(tagProductsProvider(key)).value ??
        const <Product>[]) {
      out[product.id] = product;
    }
  }
  return out.values.toList();
});

/// Whether anything is still on its way, so the tab can say so rather
/// than showing the empty state at somebody who follows plenty.
final followingLoadingProvider = Provider<bool>((ref) {
  final people = ref.watch(followedPeopleProvider).value ?? const <String>{};
  final tags = ref.watch(followedTagsProvider).value ?? const <String>{};
  for (final uid in people.take(kFollowedPeopleQueried)) {
    if (ref.watch(postsByProvider(uid)).isLoading) return true;
  }
  for (final tag in tags.take(kFollowedTagsQueried)) {
    final key = tagKey(tag);
    if (key.isNotEmpty && ref.watch(tagProductsProvider(key)).isLoading) {
      return true;
    }
  }
  return false;
});

/// The posts from the people this person follows. Kept for the tests and
/// for anything that wants only the post half.
final followingFeedProvider = Provider<List<Post>>((ref) {
  return ref.watch(followedPeoplePostsProvider);
});

/// Everyone this person follows. Empty for a guest, who follows nobody.
final followedPeopleProvider = StreamProvider<Set<String>>((ref) {
  if (ref.watch(isGuestProvider)) return Stream.value(const {});
  return ref.watch(socialRepositoryProvider).watchFollowedPeople();
});
