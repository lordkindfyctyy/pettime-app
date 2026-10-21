import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pettime_app/l10n/app_lang.dart';
import 'package:pettime_app/l10n/en.dart';
import 'package:pettime_app/main.dart';
import 'package:pettime_app/state/language_state.dart';
import 'package:pettime_app/state/pets_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Spanish texts of every tr('...') call in lib/ (adjacent literals are
/// joined).
Set<String> _keysInSource() {
  final keys = <String>{};
  final call = RegExp(r'\btr\(\s*');
  final literal = RegExp(
    r'''\s*('((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)")''',
  );
  String unescape(String s) => s.replaceAllMapped(RegExp(r'\\(.)'), (m) {
        final c = m[1]!;
        return c == 'n' ? '\n' : (c == 't' ? '\t' : c);
      });
  for (final file in Directory('lib').listSync(recursive: true)) {
    if (file is! File || !file.path.endsWith('.dart')) continue;
    if (file.path.contains('l10n')) continue;
    final src = file.readAsStringSync();
    for (final m in call.allMatches(src)) {
      var at = m.end;
      final key = StringBuffer();
      var found = false;
      while (true) {
        final l = literal.matchAsPrefix(src, at);
        if (l == null) break;
        key.write(unescape(l.group(2) ?? l.group(3)!));
        found = true;
        at = l.end;
      }
      if (found) keys.add(key.toString());
    }
  }
  // Enum values keep their label in Spanish and the getter does tr(_label).
  final enumValue = RegExp(
    r"""^\s+[a-z]\w*\(('(?:[^'\\\n]|\\.)*')(?:, ('(?:[^'\\\n]|\\.)*'))?\)[,;]\s*$""",
    multiLine: true,
  );
  for (final file in Directory('lib/models').listSync()) {
    if (file is! File || !file.path.endsWith('.dart')) continue;
    for (final m in enumValue.allMatches(file.readAsStringSync())) {
      for (final g in [m.group(1), m.group(2)]) {
        if (g != null) keys.add(unescape(g.substring(1, g.length - 1)));
      }
    }
  }
  return keys;
}

Set<String> _marks(String s) =>
    RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m[1]!).toSet();

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLang.code = 'es';
  });
  tearDown(() => AppLang.code = 'es');

  test('every tr() text of the app has an English translation', () {
    final missing = [
      for (final k in _keysInSource())
        if (!enStrings.containsKey(k)) k,
    ];
    expect(missing, isEmpty, reason: 'Add these to lib/l10n/en.dart');
  });

  test('translations keep the {marks} of the Spanish text', () {
    final wrong = [
      for (final e in enStrings.entries)
        if (_marks(e.key).difference(_marks(e.value)).isNotEmpty ||
            _marks(e.value).difference(_marks(e.key)).isNotEmpty)
          e.key,
    ];
    expect(wrong, isEmpty);
  });

  test('no English text is left over without a tr() using it', () {
    final used = _keysInSource();
    final unused = enStrings.keys.where((k) => !used.contains(k)).toList();
    expect(unused, isEmpty, reason: 'Remove these from lib/l10n/en.dart');
  });

  test('tr() translates, fills the marks and falls back to Spanish', () {
    expect(tr('Cancelar'), 'Cancelar');
    AppLang.code = 'en';
    expect(tr('Cancelar'), 'Cancel');
    expect(
      tr('Toma de {name} registrada', {'name': 'Amoxi'}),
      'Dose of Amoxi logged',
    );
    expect(tr('Un texto sin traducir'), 'Un texto sin traducir');
  });

  test('the phone language: Spanish stays Spanish, anything else is English', () {
    expect(AppLang.fromSystem('es'), 'es');
    expect(AppLang.fromSystem('en'), 'en');
    expect(AppLang.fromSystem('pt'), 'en');
  });

  test('LanguageState remembers the choice and can go back to the phone', () async {
    final state = LanguageState();
    await state.load();
    await state.setChoice('en');
    expect(AppLang.code, 'en');

    AppLang.code = 'es';
    final again = LanguageState();
    await again.load();
    expect(again.choice, 'en');
    expect(AppLang.code, 'en');

    await again.setChoice(null);
    expect(again.choice, isNull);
    final third = LanguageState();
    await third.load();
    expect(third.choice, isNull);
  });

  testWidgets('changing the language redraws the app in English', (tester) async {
    await initializeDateFormatting();
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final language = LanguageState();
    await language.load();
    await language.setChoice('es');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => PetsState()),
          ChangeNotifierProvider.value(value: language),
        ],
        child: const PetTimeApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mascotas'));
    await tester.pumpAndSettle();
    expect(find.text('Todavía no agregaste ninguna mascota'), findsOneWidget);

    await language.setChoice('en');
    await tester.pumpAndSettle();
    expect(find.text("You haven't added any pet yet"), findsOneWidget);
    expect(find.text('Mascotas'), findsNothing);
  });
}
