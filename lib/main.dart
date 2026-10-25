import 'package:flutter/material.dart';

import 'services/api_service.dart';
import 'home_page/auth_page.dart';
import 'home_page/home_page.dart';
import 'theme.dart';

void main() => runApp(const KlasikGroundsApp());

class KlasikGroundsApp extends StatelessWidget {
  const KlasikGroundsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Klasik Grounds Cafe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: cream,
        colorScheme: ColorScheme.fromSeed(
          seedColor: forest,
          primary: forest,
          secondary: accent,
          surface: Colors.white,
        ),
        fontFamily: 'Roboto',
        textTheme: const TextTheme(
          headlineLarge: TextStyle(color: ink, fontWeight: FontWeight.w700),
          headlineMedium: TextStyle(color: ink, fontWeight: FontWeight.w700),
          titleLarge: TextStyle(color: ink, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(color: ink, fontWeight: FontWeight.w600),
          bodyMedium: TextStyle(color: mutedInk, height: 1.45),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7F7F3),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE8E9E2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: forest, width: 1.4),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: forest,
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  CafeSession? _session;
  bool _guest = false;

  void _enterGuestMode() => setState(() => _guest = true);

  void _onSignedIn(CafeSession session) => setState(() {
    _session = session;
    _guest = false;
  });

  Future<void> _exitHome() async {
    if (!mounted) return;
    setState(() {
      _session = null;
      _guest = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null && !_guest) {
      return AuthPage(
        onSignedIn: _onSignedIn,
        onContinueAsGuest: _enterGuestMode,
      );
    }
    return HomePage(
      key: ValueKey(_session?.userId ?? 'guest'),
      session: _session,
      onExit: _exitHome,
    );
  }
}
