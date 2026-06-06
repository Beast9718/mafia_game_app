import 'dart:async';
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

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  final List<String> _bootLogs = [];
  final List<String> _sourceLogs = [
    "INITIALIZING SECURITY PROTOCOLS...",
    "ESTABLISHING HOST CONNECTION...",
    "LOADING CLASSIFIED DOSSIERS...",
    "NIGHTMARE HANDSHAKE SUCCESSFUL.",
    "ENTER INGESTION SEQUENCE...",
  ];
  Timer? _logTimer;
  Timer? _navigateTimer;
  int _logIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic)
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn)
    );

    _controller.forward();

    // Sequentially print boot logs
    _logTimer = Timer.periodic(const Duration(milliseconds: 700), (timer) {
      if (_logIndex < _sourceLogs.length) {
        if (mounted) {
          setState(() {
            _bootLogs.add(_sourceLogs[_logIndex]);
            _logIndex++;
          });
        }
      } else {
        timer.cancel();
      }
    });

    _navigateTimer = Timer(const Duration(milliseconds: 4500), () {
      if (mounted) context.go('/profile');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _logTimer?.cancel();
    _navigateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF040405),
      body: Stack(
        children: [
          // Background ambient gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [
                    Color(0x1F7A0000), // Very faint dark red ambient
                    Color(0xFF040405),
                  ],
                ),
              ),
            ),
          ),
          
          // CCTV scanlines
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: CRTScanlinePainter(),
              ),
            ),
          ),

          Center(
            child: FadeTransition(
              opacity: _opacityAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'MAFIA',
                      style: TextStyle(
                        color: Colors.redAccent.shade400,
                        fontSize: 48,
                        letterSpacing: 12,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(
                            color: Colors.redAccent.withValues(alpha: 0.7),
                            blurRadius: 25,
                            offset: const Offset(0, 0),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'NIGHT HAS COME',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 14,
                        letterSpacing: 6,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Boot logs at the bottom
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "SYSTEM MONITOR",
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(
                    _bootLogs.length,
                    (index) => Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Text(
                        "> ${_bootLogs[index]}",
                        style: const TextStyle(
                          color: Colors.white30,
                          fontSize: 9,
                          fontFamily: 'monospace',
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CRTScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.015)
      ..strokeWidth = 1;

    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
            doctorSaved: extra['doctorSaved'] as bool? ?? false,
            murderVideoBase64: extra['videoBase64'] as String?,
            ritualStatus: extra['ritualStatus'] as String?,
            ritualFeedback: extra['ritualFeedback'] as String?,
            attemptedTarget: extra['attemptedTarget'] as String?,
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