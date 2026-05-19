import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Added for terms check
import 'package:arribo/core/theme/app_theme.dart';
import 'package:arribo/features/transit/presentation/pages/map_screen.dart';
import 'package:arribo/features/terms/terms_screen.dart'; // Import TermsScreen

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('Dotenv load failed: $e');
  }

  // Initialize Firebase
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase initialization failed: $e. Make sure google-services.json is present.');
  }

  // Check if terms were accepted
  final prefs = await SharedPreferences.getInstance();
  final bool termsAccepted = prefs.getBool('terms_accepted') ?? false;

  runApp(ArriboApp(termsAccepted: termsAccepted));
}

class ArriboApp extends StatelessWidget {
  final bool termsAccepted;
  const ArriboApp({Key? key, required this.termsAccepted}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arribo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      // Decide initial screen based on terms acceptance
      home: termsAccepted ? const MapScreen() : const TermsScreen(),
      // Define routes for navigation after acceptance
      routes: {
        '/home': (context) => const MapScreen(),
        '/terms': (context) => const TermsScreen(),
      },
    );
  }
}
