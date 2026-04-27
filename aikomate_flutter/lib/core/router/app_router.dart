import 'package:go_router/go_router.dart';
import 'package:aikomate_flutter/core/auth/auth_session_notifier.dart';
import 'package:aikomate_flutter/features/account/presentation/account_screen.dart';
import 'package:aikomate_flutter/features/auth/presentation/auth_login_screen.dart';
import 'package:aikomate_flutter/features/auth/presentation/auth_signup_screen.dart';
import 'package:aikomate_flutter/features/create/presentation/create_template_screen.dart';
import 'package:aikomate_flutter/features/discover/presentation/discover_screen.dart';
import 'package:aikomate_flutter/features/hub/presentation/hub_shell.dart';
import 'package:aikomate_flutter/features/recents/presentation/recents_screen.dart';
import 'package:aikomate_flutter/features/viewer/screens/viewer_screen.dart';
import 'package:aikomate_flutter/features/viewer/viewer_launch_args.dart';

GoRouter createAppRouter(AuthSessionNotifier session) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: session,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final loggedIn = session.isLoggedIn;

      if (!loggedIn) {
        if (loc == '/login' || loc == '/signup') return null;
        return '/login';
      }

      if (loc == '/viewer') return null;

      if (loc == '/login' || loc == '/signup' || loc == '/') {
        return '/hub/discover';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => AuthLoginScreen(session: session),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => AuthSignupScreen(session: session),
      ),
      GoRoute(
        path: '/hub',
        redirect: (context, state) {
          if (state.uri.path == '/hub') return '/hub/discover';
          return null;
        },
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) {
              return HubShell(navigationShell: navigationShell);
            },
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'discover',
                    builder: (context, state) => const DiscoverScreen(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'recents',
                    builder: (context, state) => const RecentsScreen(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'create',
                    builder: (context, state) => const CreateTemplateScreen(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'account',
                    builder:
                        (context, state) => AccountScreen(session: session),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/',
        redirect:
            (context, state) => session.isLoggedIn ? '/hub/discover' : '/login',
      ),
      GoRoute(
        path: '/viewer',
        builder: (context, state) {
          final extra = state.extra;
          final args = extra is ViewerLaunchArgs ? extra : null;
          return ViewerScreen(launchArgs: args);
        },
      ),
    ],
  );
}
