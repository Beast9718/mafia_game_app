import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class GameOverScreen extends StatelessWidget {
  final String winner;

  const GameOverScreen({super.key, required this.winner});

  @override
  Widget build(BuildContext context) {
    final isMafia = winner == 'MAFIA';
    final themeColor = isMafia ? Colors.red.shade900 : Colors.blue.shade700;
    final icon = isMafia ? Icons.bloodtype : Icons.local_police;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 120, color: themeColor),
            const SizedBox(height: 32),
            const Text(
              "GAME OVER",
              style: TextStyle(
                color: Colors.white38,
                fontSize: 20,
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "$winner WINS",
              style: TextStyle(
                color: themeColor,
                fontSize: 48,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 64),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade900,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.white12, width: 1),
                ),
              ),
              onPressed: () {
                // Return to the lobby for a new game
                context.go('/lobby');
              },
              child: const Text(
                "RETURN TO LOBBY",
                style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold),
              ),
            )
          ],
        ),
      ),
    );
  }
}