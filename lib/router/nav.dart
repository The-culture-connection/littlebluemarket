import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Screens that can be reached from more than one tab — a post, a product, a
/// seller's feed, a DM — are registered under every branch that leads to them.
/// Pushing the copy that belongs to the current branch is what keeps each tab's
/// back stack its own: opening a seller from the Market feed must not throw you
/// into the You tab.
String branchPrefix(BuildContext context) =>
    branchPrefixOf(GoRouterState.of(context).uri.path);

/// The same rule, from a path alone.
///
/// The floating cart is mounted above the router, in the `MaterialApp`
/// builder, so there is no `GoRouterState` over its context to read — it
/// knows the current address from the router's own delegate instead.
String branchPrefixOf(String path) {
  if (path.startsWith('/community')) return '/community';
  if (path.startsWith('/you')) return '/you';
  return '/market';
}

extension LbmNavigation on BuildContext {
  void _pushInBranch(String suffix) => push('${branchPrefix(this)}$suffix');

  /// A post's own screen — the avatar row, the media, and its reviews.
  void goToPost(String productId) => _pushInBranch('/post/$productId');

  /// The full record behind a post.
  void goToProduct(String productId) => _pushInBranch('/product/$productId');

  /// Every review for one product.
  void goToReviews(String productId) => _pushInBranch('/reviews/$productId');

  /// Someone's public feed. Every avatar in the app leads here.
  void goToSeller(String personId) => _pushInBranch('/seller/$personId');

  /// From a storefront: the conversation may not exist yet, so the screen
  /// resolves it. The inbox pushes a conversation id directly.
  void goToDm(String personId) => _pushInBranch('/dm/$personId?to=1');

  void goToCart() => _pushInBranch('/cart');

  /// Everything filed under one store collection, by handle.
  void goToCollection(String handle) => _pushInBranch('/collection/$handle');

  /// Every published business in one littlebluecart.com category, by slug.
  void goToDirectoryCategory(String slug) =>
      _pushInBranch('/directory-category/$slug');

  /// Search results for a query — typed, or a tapped hashtag.
  ///
  /// **There is only ever one search in the back stack.** Searching is a
  /// round trip (the field, then the results), and every hashtag chip is
  /// another search: the popular-tag tiles on the search screen, the chips
  /// on a product card, the "did you mean" suggestions. Pushing each one
  /// buried the Market under a pile of old searches, which a tester hit
  /// twice — once before the first fix and again after it, because the fix
  /// only covered the typed path (Grace, 2026-09-23). A search opened from
  /// a screen that is itself a search **replaces** it; from anywhere else it
  /// is pushed, once.
  void goToResults(String query) =>
      _searchNav('/results?q=${Uri.encodeComponent(query)}');

  /// The same results, always in place of whatever is on top: the search
  /// field replacing itself with what it found.
  void replaceWithResults(String query) => pushReplacement(
    '${branchPrefix(this)}/results?q=${Uri.encodeComponent(query)}',
  );

  /// The search field, in place of whatever is on top. Used by the pill on
  /// the results screen, so searching again does not deepen the stack.
  void replaceWithSearch(String query) => pushReplacement(
    '${branchPrefix(this)}/search?q=${Uri.encodeComponent(query)}',
  );

  /// Push, unless we are already standing on a search.
  void _searchNav(String suffix) {
    final target = '${branchPrefix(this)}$suffix';
    isOnSearch(this) ? pushReplacement(target) : push(target);
  }

  /// Back out of a search to the tab's own root — the Market feed, or the
  /// Community root when the search was run from there.
  ///
  /// Grace, 2026-09-23: "the back button should go back to the market feed".
  /// Popping usually does it now that searches replace each other, but not
  /// when the search was opened from a listing three screens deep, and
  /// "Back from a search goes to the Market" is a rule worth being able to
  /// state without a footnote.
  void leaveSearch() => go(branchPrefix(this));
}

/// Whether [context] is standing on the search field or on search results.
bool isOnSearch(BuildContext context) {
  final path = GoRouterState.of(context).uri.path;
  return path.endsWith('/search') || path.endsWith('/results');
}
