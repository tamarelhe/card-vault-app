import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/home/home_screen.dart';

/// Root application widget — configures the theme and router.
class CardVaultApp extends ConsumerWidget {
  const CardVaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = _buildRouter(ref);

    return MaterialApp.router(
      title: 'Card Vault',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      routerConfig: router,
    );
  }

  /// Dark theme matching the MTG aesthetic.
  ThemeData _buildTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );
  }

  /// go_router config with an auth redirect guard.
  GoRouter _buildRouter(WidgetRef ref) {
    return GoRouter(
      initialLocation: '/',
      // Redirect unauthenticated users to /login.
      redirect: (context, state) async {
        final authenticated =
            await ref.read(isAuthenticatedProvider.future);
        final onAuthPage = state.matchedLocation == '/login' ||
            state.matchedLocation == '/register';

        if (!authenticated && !onAuthPage) return '/login';
        if (authenticated && onAuthPage) return '/';
        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (ctx, _) => const HomeScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (ctx, _) => const LoginScreen(),
        ),
        GoRoute(
          path: '/register',
          builder: (ctx, _) => const RegisterScreen(),
        ),
      ],
    );
  }
}
