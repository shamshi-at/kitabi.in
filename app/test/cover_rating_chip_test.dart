import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitabi/core/widgets/shelf_cover.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// The community rating worn on shelf covers ("plan the next read" — owner
/// request, 9 Aug 2026). Absent is not zero: no rating, no chip.
Widget _host(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SizedBox(width: 120, height: 180, child: child)),
  );
}

void main() {
  testWidgets('a rated cover wears the star chip', (tester) async {
    await tester.pumpWidget(_host(const ShelfCover(title: 'Chemmeen', rating: 4.4)));
    expect(find.text('★ 4.4'), findsOneWidget);
  });

  testWidgets('no rating, no chip — absent is not zero', (tester) async {
    await tester.pumpWidget(_host(const ShelfCover(title: 'Chemmeen')));
    expect(find.textContaining('★'), findsNothing);
  });

  testWidgets('the RETURNED stamp owns the top-left corner over the chip', (tester) async {
    await tester.pumpWidget(
      _host(const ShelfCover(title: 'Chemmeen', rating: 4.4, returned: true)),
    );
    expect(find.text('★ 4.4'), findsNothing);
    expect(find.text('RETURNED'), findsOneWidget);
  });
}
