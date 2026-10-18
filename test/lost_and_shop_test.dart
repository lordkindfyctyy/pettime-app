import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pettime_app/models/lost_report.dart';
import 'package:pettime_app/screens/lost_pets_screen.dart';
import 'package:pettime_app/services/lost_pets_service.dart';
import 'package:pettime_app/services/pettime_api.dart';
import 'package:pettime_app/services/shop_service.dart';
import 'package:pettime_app/services/shop_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> reportJson(int id, {String kind = 'lost', String status = 'active'}) => {
      'id': id,
      'kind': kind,
      'petName': kind == 'lost' ? 'Pancho' : '',
      'species': 'Perro',
      'breed': 'Labrador',
      'description': 'Collar rojo',
      'eventAt': '2026-10-17T18:30',
      'zone': 'Villa Ballester',
      'contactName': 'Lalo',
      'contactPhone': '5491164722908',
      'status': status,
      'photos': <String>[],
      'webUrl': 'https://sixsevenweb.com/pettime/perdidas.php#aviso-$id',
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() => initializeDateFormatting('es'));

  test('aviso: textos y WhatsApp', () {
    final lost = LostReport.fromJson(reportJson(1));
    expect(lost.title, 'Pancho');
    expect(lost.details, 'Perro · Labrador');
    expect(lost.whenLabel(), 'Se perdió el 17 oct, 18:30');
    expect(lost.whatsAppUri().path, '/5491164722908');
    expect(lost.shareText(), contains('¡Se perdió Pancho!'));

    final found = LostReport.fromJson(reportJson(2, kind: 'found'));
    expect(found.title, 'Mascota encontrada');
    expect(found.whenLabel(), startsWith('Vista el'));
    expect(found.whatsAppUri().queryParameters['text'], contains('Villa Ballester'));

    final draft = ReportDraft(
      kind: ReportKind.lost,
      petName: 'Pancho',
      species: '',
      breed: '',
      description: '',
      eventAt: DateTime(2026, 10, 17, 18, 30),
      zone: 'Villa Ballester',
      contactName: '',
      contactPhone: '11 6472-2908',
    );
    expect(draft.toFields()['eventAt'], '2026-10-17T18:30');
    expect(draft.toFields()['kind'], 'lost');
  });

  test('mis avisos: guarda la clave, olvida los borrados', () async {
    final posted = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('action.php')) {
        posted.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{"ok":true}', 200);
      }
      // list.php?ids=...: el 2 ya no existe en el servidor.
      return http.Response(jsonEncode({'ok': true, 'reports': [reportJson(1)]}), 200);
    });
    SharedPreferences.setMockInitialValues({
      'lost_reports_mine': jsonEncode({'1': 'key1', '2': 'key2'}),
    });
    final service = LostPetsService(api: PetTimeApi(client: client, base: 'https://x'));
    await service.load();
    expect(service.isMine(1), isTrue);

    final mine = await service.mine();
    expect(mine.single.id, 1);
    expect(service.isMine(2), isFalse);

    await service.act(1, 'resolve');
    expect(posted.single, {'id': 1, 'action': 'resolve', 'editKey': 'key1'});
  });

  testWidgets('la pestaña muestra los avisos y el botón de WhatsApp', (tester) async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'ok': true,
            'reports': [reportJson(1), reportJson(2, kind: 'found')],
          }),
          200,
        ));
    final service = LostPetsService(api: PetTimeApi(client: client, base: 'https://x'));
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: LostPetsScreen(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('Pancho'), findsOneWidget);
    expect(find.text('Mascota encontrada'), findsOneWidget);
    expect(find.text('WhatsApp a Lalo'), findsNWidgets(2));
    expect(find.text('Se perdió'), findsWidgets);
  });

  testWidgets('sin internet muestra el error y reintentar', (tester) async {
    final client = MockClient((_) async => throw http.ClientException('offline'));
    final service = LostPetsService(api: PetTimeApi(client: client, base: 'https://x'));
    await tester.pumpWidget(MaterialApp(home: LostPetsScreen(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('No hay conexión a internet.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  test('tienda: productos, categorías y WhatsApp del local', () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'ok': true,
            'shop': {
              'name': 'Lo De Lalo Pet Shop',
              'whatsapp': '5491164722908',
              'address': 'Quirno Costa 1164',
              'catalogUrl': 'https://sixsevenweb.com/catalogo.php?t=x',
              'lostPetsUrl': 'https://sixsevenweb.com/pettime/perdidas.php',
            },
            'products': [
              {'id': 1, 'name': 'Absorsol 3,6 kg', 'price': 8000, 'inStock': true, 'saleUnit': 'unit', 'category': 'PIEDRAS'},
              {'id': 2, 'name': 'Balanceado suelto', 'price': 4500, 'inStock': false, 'saleUnit': 'weight', 'category': 'ALIMENTO', 'promo': true, 'promoText': ''},
              {'id': 3, 'name': 'Pipeta', 'price': 12000.5, 'category': 'PIEDRAS'},
            ],
          }),
          200,
        ));
    await ShopSettings.instance.load();
    final catalog = await ShopService(api: PetTimeApi(client: client, base: 'https://x')).fetch();
    expect(catalog.categories, ['PIEDRAS', 'ALIMENTO']);
    expect(catalog.products[0].priceLabel, r'$ 8.000');
    expect(catalog.products[1].priceLabel, r'$ 4.500 el kg');
    expect(catalog.products[1].promoText, 'Promo');
    expect(catalog.products[2].priceLabel, r'$ 12.000,50');
    // Los pedidos de reposición van al WhatsApp del local si no había otro.
    expect(ShopSettings.instance.phone, '+5491164722908');
    expect(await ShopService(api: PetTimeApi(client: client, base: 'https://x')).cached(), isNotNull);
  });
}
