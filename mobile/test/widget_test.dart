/// Test dymny UI: aplikacja startuje i pokazuje ekran debug telemetrii.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gt7_engineer_mobile/main.dart';

void main() {
  testWidgets('apka startuje na Inzynierze z bocznym menu', (tester) async {
    await tester.pumpWidget(const Gt7App());
    // Start na Inzynierze: przyciski sterujace.
    expect(find.text('Start (PS5)'), findsOneWidget);
    expect(find.text('Demo'), findsOneWidget);
    // Hamburger otwierajacy boczne menu (Drawer).
    expect(find.byIcon(Icons.menu), findsOneWidget);

    // Otworz menu i przejdz do Podgladu.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Podglad'), findsWidgets);
    await tester.tap(find.text('Podglad').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Brak danych'), findsOneWidget);
  });
}
