import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pettime_app/models/expense.dart';
import 'package:pettime_app/models/pet.dart';
import 'package:pettime_app/screens/lost_pets_screen.dart';
import 'package:pettime_app/services/lost_pets_service.dart';
import 'package:pettime_app/services/pettime_api.dart';
import 'package:pettime_app/widgets/expense_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's phone has a big font (130 %) and display zoom: words must not
/// break in two ("Peluquerí-a", "Encontra-das").
Widget bigFont(Widget child) => MediaQuery(
      data: const MediaQueryData(
        size: Size(320, 900),
        textScaler: TextScaler.linear(1.6),
      ),
      child: MaterialApp(home: child),
    );

/// Whether [text] is drawn on a single line.
bool oneLine(WidgetTester tester, String text) {
  final finder = find.text(text);
  final style = tester.widget<Text>(finder.first).style ??
      DefaultTextStyle.of(tester.element(finder.first)).style;
  final lineHeight = (style.fontSize ?? 14) * 1.6 * (style.height ?? 1.5);
  return tester.getSize(finder.first).height < lineHeight * 1.5;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets('gastos: la categoría no se corta', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final pet = Pet(id: 'p', name: 'Pancho', expenses: [
      Expense(id: 'a', date: now, category: ExpenseCategory.grooming, amount: 3000),
      Expense(id: 'b', date: now, category: ExpenseCategory.accessories, amount: 125000),
    ]);
    await tester.pumpWidget(bigFont(Scaffold(
      body: ListView(children: [ExpenseSection(pet: pet)]),
    )));
    expect(tester.takeException(), isNull);
    expect(oneLine(tester, 'Peluquería'), isTrue);
    expect(oneLine(tester, 'Accesorios'), isTrue);
  });

  testWidgets('perdidas: los filtros no se cortan', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = MockClient((_) async =>
        http.Response(jsonEncode({'ok': true, 'reports': []}), 200));
    final service = LostPetsService(api: PetTimeApi(client: client, base: 'https://x'));
    await tester.pumpWidget(bigFont(LostPetsScreen(service: service)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final label in ['Todas', 'Perdidas', 'Encontradas']) {
      expect(oneLine(tester, label), isTrue, reason: label);
    }
  });
}
