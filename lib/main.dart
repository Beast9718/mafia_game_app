import 'package:flutter/material.dart';
import 'core/router/app_router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MafiaGameApp());
}

class MafiaGameApp extends StatelessWidget {
  const MafiaGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Mafia: Night Has Come',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF070708),
        cardColor: const Color(0xFF121215),
        colorScheme: const ColorScheme.dark(
          primary: Colors.redAccent, 
          secondary: Colors.red,
          surface: Color(0xFF121215),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF121215),
          hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 1.5, fontSize: 13),
          labelStyle: const TextStyle(color: Colors.white54, letterSpacing: 1.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade900,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5), width: 1),
            ),
            elevation: 8,
          ),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white70, letterSpacing: 0.5),
          bodyMedium: TextStyle(color: Colors.white70, letterSpacing: 0.5),
        ),
      ),
      routerConfig: AppRouter.router,
    );
  }
}