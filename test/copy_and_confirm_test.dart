import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettime_app/widgets/confirm_delete.dart';
import 'package:pettime_app/widgets/copyable_code.dart';
import 'package:pettime_app/widgets/family_share.dart';

void main() {
  group('findShareCode', () {
    test('finds the code in the whole invite message', () {
      const message = 'Sumate a Pancho en PetTime: así los dos vemos y '
          'marcamos sus remedios.\n\n'
          '1. Instalá PetTime: https://sixsevenweb.com/pettime/\n'
          '2. En "Mascotas" tocá ⋮ → "Unirme con un código"\n'
          '3. Copiá este mensaje y tocá "Pegar", o escribí el código: K7Q2-M9XP';
      expect(findShareCode(message), 'K7Q2M9XP');
    });

    test('finds a caregiver code of 12', () {
      expect(findShareCode('el código: abcd-efgh-jkmn\n\nCuando termine…'),
          'ABCDEFGHJKMN');
    });

    test('accepts the code alone, with or without the dash', () {
      expect(findShareCode(' k7q2m9xp '), 'K7Q2M9XP');
      expect(findShareCode('K7Q2-M9XP'), 'K7Q2M9XP');
    });

    test('null when there is no code', () {
      expect(findShareCode(''), isNull);
      expect(findShareCode('hola, ¿cómo estás?'), isNull);
    });
  });

  testWidgets('a trash button asks first, naming what it deletes',
      (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () async =>
              result = await confirmDelete(context, 'el paseo del 18 oct'),
        ),
      ),
    ));

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar el paseo del 18 oct?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('one tap copies the code', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: CopyableCode(code: 'K7Q2-M9XP'))),
    ));
    expect(find.text('Tocá para copiar'), findsOneWidget);

    await tester.tap(find.text('K7Q2-M9XP'));
    await tester.pump();
    expect(copied, 'K7Q2-M9XP');
    expect(find.text('¡Copiado! Ya lo podés pegar'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Tocá para copiar'), findsOneWidget);
  });
}
