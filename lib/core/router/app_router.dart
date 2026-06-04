import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/screens/lobby/profile_setup_screen.dart';
import '../../presentation/screens/lobby/lobby_screen.dart';
import '../../presentation/screens/game/role_reveal_screen.dart';
import '../../presentation/screens/game/day_phase_screen.dart';
import '../../presentation/screens/game/night_phase_screen.dart';

import '../../presentation/screens/game/game_over_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) context.go('/profile');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          'MAFIA\nNIGHT HAS COME',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 24,
            letterSpacing: 4,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: '/lobby',
        builder: (context, state) => const LobbyScreen(),
      ),
      GoRoute(
        path: '/role-reveal',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return RoleRevealScreen(
            assignedRole: extra['assignedRole'] as String? ?? 'STUDENT',
            // 🔥 BULLETPROOF CASTING 🔥
            players: List<Map<String, dynamic>>.from(extra['players'] ?? []),
          );
        },
      ),
      GoRoute(
        path: '/game/day',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return DayPhaseScreen(
            victimName: extra['victim'] as String?,
            // 🔥 BULLETPROOF CASTING 🔥
            players: List<Map<String, dynamic>>.from(extra['players'] ?? []),
          );
        },
      ),
      GoRoute(
        path: '/game/night',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return NightPhaseScreen(
            // 🔥 BULLETPROOF CASTING 🔥
            players: List<Map<String, dynamic>>.from(extra['players'] ?? []),
          );
        },
      ),
      GoRoute(
        path: '/game-over',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return GameOverScreen(
            winner: extra['winner'] as String? ?? 'UNKNOWN',
          );
        },
      ),
    ],
  );
}