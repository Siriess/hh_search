import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const HhSearchApp());
}

class HhSearchApp extends StatelessWidget {
  const HhSearchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HH Vacancy Export',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080818),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8B5CF6),
          secondary: Color(0xFFEC4899),
          surface: Color(0xFF12122A),
        ),
        useMaterial3: true,
        fontFamily: 'Segoe UI',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1C1C3A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2D2D5E)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2D2D5E)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 1.5),
          ),
          labelStyle: const TextStyle(color: Color(0xFF9090C0)),
          hintStyle: const TextStyle(color: Color(0xFF555580)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Color(0xFFCCCCEE)),
          bodySmall: TextStyle(color: Color(0xFF8888AA)),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
