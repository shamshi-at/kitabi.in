import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitabi/main.dart';

void main() {
  testWidgets('app boots to the home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: KitabiApp()));
    await tester.pumpAndSettle();

    expect(find.text('Kitabi'), findsOneWidget);
    expect(find.text('Beyond the Bookshelf'), findsOneWidget);
  });
}
