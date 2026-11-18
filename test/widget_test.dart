import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SuperIA muestra la pantalla principal', (tester) async {
    await tester.pumpWidget(const SuperIAApp());
    await tester.pumpAndSettle();

    expect(find.text('¿En qué puedo ayudarte hoy?'), findsOneWidget);
  });
}
