// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:arribo/main.dart';

void main() {
  // Ensure widget bindings are initialized
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');

  setUpAll(() async {
    // Initialize mock environment variables directly
    dotenv.testLoad(fileInput: '''
      TRANSIT_CLIENT_ID=mock
      TRANSIT_SECRET=mock
      USE_MOCK=true
    ''');

    // Mock Geolocator method channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(geolocatorChannel, (MethodCall methodCall) async {
      if (methodCall.method == 'isLocationServiceEnabled') {
        return true;
      }
      if (methodCall.method == 'checkPermission') {
        return 3; // LocationPermission.always (represented by index 3)
      }
      if (methodCall.method == 'requestPermission') {
        return 3; // LocationPermission.always (represented by index 3)
      }
      if (methodCall.method == 'getCurrentPosition') {
        return {
          'latitude': -34.7611,
          'longitude': -58.2115,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'accuracy': 1.0,
          'altitude': 0.0,
          'heading': 0.0,
          'speed': 0.0,
          'speed_accuracy': 0.0,
          'is_mocked': false,
        };
      }
      return null;
    });

    // Mock SharedPreferences
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App loads smoke test - complete terms acceptance and map load flow', (WidgetTester tester) async {
    // 1. Build our app starting with terms not accepted
    await tester.pumpWidget(const ArriboApp(termsAccepted: false));

    // Verify we are on the Terms screen first
    expect(find.text('ACEPTAR Y ENTRAR'), findsOneWidget);
    expect(find.text('NO ACEPTO'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);

    // Verify the "ACEPTAR Y ENTRAR" button is initially disabled (onPressed is null)
    final ElevatedButton acceptButton = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('ACEPTAR Y ENTRAR'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(acceptButton.enabled, isFalse);

    // 2. Accept terms by checking the checkbox
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    // Verify button is now enabled
    final ElevatedButton acceptButtonEnabled = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('ACEPTAR Y ENTRAR'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(acceptButtonEnabled.enabled, isTrue);

    // 3. Tap the "ACEPTAR Y ENTRAR" button and transition to MapScreen
    await tester.tap(find.text('ACEPTAR Y ENTRAR'));
    
    // We pump and settle to let SharedPreferences complete and navigation to occur
    await tester.pump();
    await tester.pumpAndSettle();

    // 4. Verify we transition to MapScreen (it shows the loading screen first if position is being determined)
    // Let's settle all microtasks and animations
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 5. Verify the search bar with its correct hint text is displayed
    expect(find.text('Buscar línea en Buenos Aires...'), findsOneWidget);
  });
}
