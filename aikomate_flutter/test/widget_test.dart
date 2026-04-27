import 'package:flutter_test/flutter_test.dart';
import 'package:aikomate_flutter/app/aikomate_app.dart';
import 'package:aikomate_flutter/core/auth/auth_session_notifier.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    final session = AuthSessionNotifier.test();
    await tester.pumpWidget(AikoMateApp(session: session));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  });
}
