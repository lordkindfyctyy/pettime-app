import 'dart:convert';
import 'dart:io';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pettime_app/models/pet.dart';
import 'package:pettime_app/screens/pet_tag_screen.dart';
import 'package:pettime_app/services/file_names.dart';
import 'package:pettime_app/services/pettime_api.dart';
import 'package:pettime_app/services/tag_pdf.dart';
import 'package:pettime_app/services/tag_service.dart';
import 'package:pettime_app/services/vet_report.dart';
import 'package:pettime_app/state/pets_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A fake tags API like public/pettime/api/tags: keeps one tag.
class FakeTagServer {
  Map<String, String>? fields;
  final requests = <String>[];
  bool deleted = false;

  /// The server cannot be reached.
  bool offline = false;

  /// The server forgets to send the key of a new tag.
  bool omitKey = false;

  late final client = MockClient((request) async {
    if (offline) throw const SocketException('offline');
    requests.add(request.url.path);
    if (request.url.path.endsWith('tags/save.php')) {
      final body = utf8.decode(request.bodyBytes);
      String field(String name) =>
          RegExp('name="$name"\r\n\r\n([^\r]*)').firstMatch(body)?[1] ?? '';
      final creating = field('code').isEmpty;
      if (!creating && field('ownerKey') != 'k3y') {
        return http.Response(jsonEncode({'ok': false, 'error': 'No se encontró la chapita.'}), 404);
      }
      fields = {
        for (final n in ['petName', 'contactName', 'contactPhone', 'message', 'lost', 'code'])
          n: field(n),
      };
      return http.Response(
        jsonEncode({
          'ok': true,
          'tag': {
            'code': 'K7Q2M9XP',
            'petName': field('petName'),
            'contactName': field('contactName'),
            'contactPhone': '5491164722908',
            'message': field('message'),
            'lost': field('lost') == '1',
            'url': 'https://sixsevenweb.com/pettime/chapita.php?c=K7Q2M9XP',
          },
          if (creating && !omitKey) 'ownerKey': 'k3y',
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (request.url.path.endsWith('tags/delete.php')) {
      deleted = true;
      return http.Response(jsonEncode({'ok': true}), 200);
    }
    return http.Response('', 404);
  });
}

Pet pancho() => Pet(id: 'p1', name: 'Pancho', species: 'Perro');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('creates the tag, marks it lost and deletes it', () async {
    final server = FakeTagServer();
    final tags = TagService(api: PetTimeApi(client: server.client, base: 'https://x'));
    await tags.load();
    expect(tags.of('p1'), isNull);

    final tag = await tags.save(
      pancho(),
      contactName: 'Lalo',
      contactPhone: '11 6472-2908',
      message: 'Es mansa',
    );
    expect(tag.code, 'K7Q2M9XP');
    expect(tag.ownerKey, 'k3y');
    expect(tag.url, endsWith('chapita.php?c=K7Q2M9XP'));
    expect(server.fields!['petName'], 'Pancho');
    expect(server.fields!['lost'], '0');
    expect(server.fields!['code'], '');

    // It stays on the phone.
    final again = TagService(api: PetTimeApi(client: server.client, base: 'https://x'));
    await again.load();
    expect(again.of('p1')!.ownerKey, 'k3y');
    expect(again.of('p1')!.message, 'Es mansa');

    final lost = await again.setLost(pancho(), true);
    expect(lost.lost, isTrue);
    expect(server.fields!['code'], 'K7Q2M9XP');
    expect(server.fields!['contactName'], 'Lalo');

    await again.delete('p1');
    expect(server.deleted, isTrue);
    expect(again.of('p1'), isNull);
  });

  test('deleting a pet turns its tag off on the server', () async {
    final server = FakeTagServer();
    final tags = TagService(api: PetTimeApi(client: server.client, base: 'https://x'));
    final state = PetsState(tags: tags);
    await state.savePet(pancho());
    await tags.save(pancho(), contactName: 'Lalo', contactPhone: '11 6472-2908');
    expect(tags.of('p1'), isNotNull);

    await state.deletePet('p1');
    for (var i = 0; i < 100 && !server.deleted; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(server.deleted, isTrue);
    expect(tags.of('p1'), isNull);
  });

  test('a tag that could not be turned off is retried on the next start', () async {
    final server = FakeTagServer();
    final tags = TagService(api: PetTimeApi(client: server.client, base: 'https://x'));
    await tags.save(pancho(), contactName: 'Lalo', contactPhone: '11 6472-2908');

    server.offline = true;
    await tags.removeForPet('p1');
    expect(server.deleted, isFalse);
    expect(tags.of('p1'), isNull);

    // The app starts again, with the server reachable.
    server.offline = false;
    final next = TagService(api: PetTimeApi(client: server.client, base: 'https://x'));
    await next.load();
    await next.retryPending();
    expect(server.deleted, isTrue);

    // Done: a later start has nothing left to turn off.
    final calls = server.requests.length;
    final last = TagService(api: PetTimeApi(client: server.client, base: 'https://x'));
    await last.load();
    await last.retryPending();
    expect(server.requests.length, calls);
  });

  test('a new tag without a key is refused, not stored', () async {
    final server = FakeTagServer()..omitKey = true;
    final tags = TagService(api: PetTimeApi(client: server.client, base: 'https://x'));
    await expectLater(
      tags.save(pancho(), contactName: 'Lalo', contactPhone: '11 6472-2908'),
      throwsA(isA<ApiException>()),
    );
    expect(tags.of('p1'), isNull);
  });

  test('file names do not break on / : or similar characters', () {
    expect(safeFileName('Rocky/Max'), 'Rocky_Max');
    expect(safeFileName(r'a\b:c*d?e"f<g>h|i'), 'a_b_c_d_e_f_g_h_i');
    expect(safeFileName('  Luna  '), 'Luna');
    expect(safeFileName('///'), '___');
    expect(safeFileName(''), '_');
    expect(TagPdf.fileName('Rocky/Max'), 'Chapita de Rocky_Max.pdf');
  });

  test('the printable sheet is a PDF', () async {
    await initializeDateFormatting('es');
    final bytes = await TagPdf.build(
      petName: 'Pancho',
      url: 'https://sixsevenweb.com/pettime/chapita.php?c=K7Q2M9XP',
      assets: await VetReportAssets.load(),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(TagPdf.fileName('Pancho'), 'Chapita de Pancho.pdf');
  });

  for (final width in [320.0, 411.0]) {
    testWidgets('the tag screen fits in $width px with a big font', (tester) async {
      tester.view.physicalSize = Size(width * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final server = FakeTagServer();
      final tags = TagService(api: PetTimeApi(client: server.client, base: 'https://x'));
      final state = PetsState();
      await tester.runAsync(() async {
        await state.savePet(pancho());
        await tags.save(pancho(), contactName: 'Lalo', contactPhone: '1164722908');
      });

      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: const TextScaler.linear(1.6),
        ),
        child: ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(home: PetTagScreen(petId: 'p1', tags: tags)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(BarcodeWidget), findsOneWidget);
      expect(find.text('Pancho'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Imprimir o guardar en PDF'), 200);
      await tester.scrollUntilVisible(find.text('Borrar chapita'), 200);
      expect(tester.takeException(), isNull);
    });
  }
}
