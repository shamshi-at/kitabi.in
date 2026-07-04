import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitabi/features/home/presentation/home_screen.dart';
import 'package:kitabi/main.dart';

void main() {
  testWidgets('unauthenticated app boots to sign-in, not home', (WidgetTester tester) async {
    // No --dart-define credentials in the test run, so Supabase stays
    // unconfigured and the auth stream immediately resolves to "signed out" —
    // the router should redirect straight to sign-in.
    await tester.pumpWidget(const ProviderScope(child: KitabiApp()));
    await tester.pumpAndSettle();

    expect(find.text('Kitabi'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });
}
