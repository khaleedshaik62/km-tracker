import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'constants.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (Assuming google-services.json is present)
  await Firebase.initializeApp();

  // Required for background ↔ foreground communication
  FlutterForegroundTask.initCommunicationPort();

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFFF1F5F9), // bg-dark
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  runApp(const KMTrackerApp());
}

// Check if user is logged in
Future<bool> _isUserLoggedIn() async {
  return FirebaseAuth.instance.currentUser != null;
}

// ── Design tokens (Matching web app index.css) ──────────────────────────────

class KMTrackerApp extends StatelessWidget {
  const KMTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'AURA km tracker',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.light,
          scaffoldBackgroundColor: kBg,
          colorScheme: const ColorScheme.light(
            primary: kPrimary,
            secondary: kSecondary,
            surface: kPanelBg,
            error: kDanger,
            onPrimary: Colors.white,
            onSurface: kTextMain,
          ),
          fontFamily: 'Outfit', // We'll assume default or user can add font
          useMaterial3: true,
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white.withOpacity(0.5),
            labelStyle: const TextStyle(color: kTextMuted),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kPrimary),
            ),
          ),
        ),
        home: FirebaseAuth.instance.currentUser != null
            ? const DashboardScreen()
            : const LoginScreen());
  }
}


// flutter run -d e7f008f6