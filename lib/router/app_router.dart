import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/community/chatroom_screen.dart';
import '../screens/community/forum_screen.dart';
import '../screens/community/forums_screen.dart';
import '../screens/community/new_forum_screen.dart';
import '../screens/community/thread_screen.dart';
import '../screens/market/cart_screen.dart';
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
import '../screens/you/claim_shop_screen.dart';
import '../screens/you/diagnostics_screen.dart';
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
        PostScreen(postId: state.pathParameters['id']!),
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
    builder: (context, state) => DmScreen(
      // From the inbox the id is a conversation; from a storefront it is a
      // person and the thread may not exist yet.
      conversationId: state.uri.queryParameters['to'] == null
          ? state.pathParameters['id']
          : null,
      personId: state.uri.queryParameters['to'] == null
          ? null
          : state.pathParameters['id'],
    ),
  ),
  GoRoute(
    path: 'results',
    builder: (context, state) => ResultsScreen(
      query: state.uri.queryParameters['q'] ?? '#PlasticFree',
    ),
  ),
  GoRoute(path: 'search', builder: (context, state) => const SearchScreen()),
  GoRoute(path: 'cart', builder: (context, state) => const CartScreen()),
];

GoRouter buildRouter(Ref ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    refreshListenable: _SessionListenable(ref),
    redirect: (context, state) {
      final async = ref.read(sessionProvider);
      // Do not bounce anyone while the session is still resolving, or a cold
      // start flashes guest before it settles on member.
      if (!async.hasValue) return null;

      final session = async.value!;
      final path = state.uri.path;

      // The onboarding routes decide their own next step.
      if (path == '/' ||
          path.startsWith('/welcome') ||
          path.startsWith('/signin') ||
          path.startsWith('/verify') ||
          path.startsWith('/setup')) {
        return null;
      }

      // Authenticated with no profile yet: setup is the only way forward.
      if (session is OnboardingSession) return '/setup';

      // Community and You are not in a guest's tab bar at all; this is the
      // backstop for a deep link or a sign-out while inside one of them.
      if (session is! MemberSession &&
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

      // Email and password, then a profile the first time. `/verify` is no
      // longer a gate — it tells a new account to confirm its address, which
      // only matters when linking a shop record later.
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
                    path: 'claim-shop',
                    builder: (context, state) => const ClaimShopScreen(),
                  ),
                  // Debug builds only. Tests run in debug, so the smoke suite
                  // still renders it.
                  if (kDebugMode)
                    GoRoute(
                      path: 'diagnostics',
                      builder: (context, state) => const DiagnosticsScreen(),
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

/// Re-runs the redirect when the session changes *kind*, so signing out of a
/// gated tab bounces back to the market.
///
/// Deliberately not on every session emission. The session carries the current
/// profile, and the order pipeline increments counters on that document — so
/// listening to every change would re-run the router's redirect each time
/// someone likes a post or a sale lands.
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(Ref ref) {
    ref.listen(sessionProvider, (previous, next) {
      if (previous?.value.runtimeType != next.value.runtimeType) {
        notifyListeners();
      }
    });
  }
}

final routerProvider = Provider<GoRouter>((ref) => buildRouter(ref));
