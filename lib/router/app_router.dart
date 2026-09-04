import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/community/chatroom_screen.dart';
import '../screens/community/forum_screen.dart';
import '../screens/community/forums_screen.dart';
import '../screens/community/new_forum_screen.dart';
import '../screens/community/thread_screen.dart';
import '../screens/market/feed_screen.dart';
import '../screens/market/post_screen.dart';
import '../screens/market/product_screen.dart';
import '../screens/market/results_screen.dart';
import '../screens/market/reviews_screen.dart';
import '../screens/market/search_screen.dart';
import '../screens/market/seller_feed_screen.dart';
import '../screens/onboarding/auth_screens.dart';
import '../screens/onboarding/welcome_screen.dart';
import '../screens/you/dm_screen.dart';
import '../screens/you/edit_profile_screen.dart';
import '../screens/you/messages_screen.dart';
import '../screens/you/profile_screen.dart';
import '../screens/you/shipping_screen.dart';
import '../state/session.dart';
import '../widgets/app_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Screens that more than one tab leads to.
///
/// A post can be opened from the Market feed, from a thread's avatar, or from
/// your own profile grid, and each of those should push onto the back stack of
/// the tab you are already in. Registering the same screens under every branch
/// is what makes that work — see `branchPrefix`.
List<RouteBase> _sharedRoutes() => [
  GoRoute(
    path: 'post/:id',
    builder: (context, state) =>
        PostScreen(productId: state.pathParameters['id']!),
  ),
  GoRoute(
    path: 'product/:id',
    builder: (context, state) =>
        ProductScreen(productId: state.pathParameters['id']!),
  ),
  GoRoute(
    path: 'reviews/:id',
    builder: (context, state) =>
        ReviewsScreen(productId: state.pathParameters['id']!),
  ),
  GoRoute(
    path: 'seller/:id',
    builder: (context, state) =>
        SellerFeedScreen(personId: state.pathParameters['id']!),
  ),
  GoRoute(
    path: 'dm/:id',
    builder: (context, state) =>
        DmScreen(personId: state.pathParameters['id']!),
  ),
  GoRoute(
    path: 'results',
    builder: (context, state) => ResultsScreen(
      query: state.uri.queryParameters['q'] ?? '#PlasticFree',
    ),
  ),
  GoRoute(path: 'search', builder: (context, state) => const SearchScreen()),
];

GoRouter buildRouter(Ref ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    refreshListenable: _SessionListenable(ref),
    redirect: (context, state) {
      final isGuest = ref.read(sessionProvider).isGuest;
      final path = state.uri.path;
      // Community and You are not in a guest's tab bar at all; this is the
      // backstop for a deep link or a sign-out while inside one of them.
      if (isGuest &&
          (path.startsWith('/community') || path.startsWith('/you'))) {
        return '/market';
      }
      return null;
    },
    routes: [
      // The welcome handoff. Entering here plays the intro once.
      GoRoute(path: '/', builder: (context, state) => const WelcomeScreen()),

      // The resting frame on its own, for coming back without a replay.
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(playIntro: false),
      ),

      // Passwordless sign-in: email, then a code, then a profile the first
      // time. There is no password field anywhere in this flow.
      GoRoute(
        path: '/signin',
        builder: (context, state) => EmailScreen(
          creating: state.uri.queryParameters['create'] == '1',
        ),
      ),
      GoRoute(
        path: '/verify',
        builder: (context, state) => VerifyScreen(
          email: state.uri.queryParameters['email'] ?? '',
          creating: state.uri.queryParameters['create'] == '1',
        ),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const ProfileSetupScreen(),
      ),

      // The three tabs. Each branch keeps its own navigator, and therefore its
      // own history.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/market',
                builder: (context, state) => const FeedScreen(),
                routes: _sharedRoutes(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/community',
                builder: (context, state) => const ChatroomScreen(),
                routes: [
                  GoRoute(
                    path: 'forums',
                    builder: (context, state) => const ForumsScreen(),
                    routes: [
                      GoRoute(
                        path: ':fid',
                        builder: (context, state) =>
                            ForumScreen(forumId: state.pathParameters['fid']!),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'thread/:tid',
                    builder: (context, state) =>
                        ThreadScreen(threadId: state.pathParameters['tid']!),
                  ),
                  GoRoute(
                    path: 'new-forum',
                    builder: (context, state) => const NewForumScreen(),
                  ),
                  ..._sharedRoutes(),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/you',
                builder: (context, state) => const ProfileScreen(),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => const EditProfileScreen(),
                  ),
                  GoRoute(
                    path: 'shipping',
                    builder: (context, state) => const ShippingScreen(),
                  ),
                  GoRoute(
                    path: 'messages',
                    builder: (context, state) => const MessagesScreen(),
                  ),
                  ..._sharedRoutes(),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// Re-runs the redirect when the session changes, so signing out of a gated tab
/// bounces back to the market.
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(Ref ref) {
    ref.listen(sessionProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) => buildRouter(ref));
