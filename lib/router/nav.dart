import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Screens that can be reached from more than one tab — a post, a product, a
/// seller's feed, a DM — are registered under every branch that leads to them.
/// Pushing the copy that belongs to the current branch is what keeps each tab's
/// back stack its own: opening a seller from the Market feed must not throw you
/// into the You tab.
String branchPrefix(BuildContext context) {
  final path = GoRouterState.of(context).uri.path;
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

  /// A one-to-one thread.
  void goToDm(String personId) => _pushInBranch('/dm/$personId');

  /// Search results for a query, usually a hashtag.
  void goToResults(String query) =>
      _pushInBranch('/results?q=${Uri.encodeComponent(query)}');
}
