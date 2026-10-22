import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pettime_app/screens/cart_screen.dart';
import 'package:pettime_app/services/pettime_api.dart';
import 'package:pettime_app/services/shop_orders.dart';
import 'package:pettime_app/services/shop_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

ShopProduct product(int id, {double price = 8000, bool byWeight = false}) => ShopProduct(
      id: id,
      name: 'Producto $id',
      price: price,
      inStock: true,
      byWeight: byWeight,
      category: '',
      brand: '',
      description: '',
    );

Map<String, dynamic> orderJson({String status = 'new'}) => {
      'id': 34,
      'number': 7,
      'total': 20000,
      'status': status,
      'statusLabel': 'Recibido',
      'rejectReason': null,
      'createdAt': '2026-10-22 14:06:36',
      'items': [
        {'productId': 1, 'name': 'Producto 1', 'quantity': 2, 'unitPrice': 8000, 'subtotal': 16000},
        {'productId': 2, 'name': 'Producto 2', 'quantity': 0.5, 'unitPrice': 8000, 'subtotal': 4000},
      ],
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('cantidades: por unidad de a 1, por peso de a medio kilo', () {
    expect(formatCartQuantity(2, byWeight: false), '2');
    expect(formatCartQuantity(1.5, byWeight: true), '1,5 kg');
    expect(CartLine.fromProduct(product(1), 1).step, 1);
    expect(CartLine.fromProduct(product(2, byWeight: true), 1).step, 0.5);
  });

  test('agregar, cambiar y quitar productos; se guarda el carrito', () async {
    final cart = ShopCart(api: PetTimeApi(client: MockClient((_) async => http.Response('{}', 200)), base: 'https://x'));
    await cart.load();
    await cart.add(product(1), 1);
    await cart.add(product(1), 1);
    await cart.add(product(2, price: 4500, byWeight: true), 1.5);
    expect(cart.count, 2);
    expect(cart.lineFor(1)!.quantity, 2);
    expect(cart.total, 8000 * 2 + 4500 * 1.5);

    await cart.add(product(1), 5, replace: true);
    expect(cart.lineFor(1)!.quantity, 5);
    await cart.setQuantity(2, 0);
    expect(cart.lineFor(2), isNull);

    final again = ShopCart(api: PetTimeApi(client: MockClient((_) async => http.Response('{}', 200)), base: 'https://x'));
    await again.load();
    expect(again.lineFor(1)!.quantity, 5);
  });

  test('al cargar la tienda se actualizan precios y se quitan productos que ya no están', () async {
    final cart = ShopCart(api: PetTimeApi(client: MockClient((_) async => http.Response('{}', 200)), base: 'https://x'));
    await cart.load();
    await cart.add(product(1), 1);
    await cart.add(product(9), 1);
    final dropped = await cart.syncWith(ShopCatalog(
      ShopInfo(name: 'Lo De Lalo', whatsapp: '', address: '', catalogUrl: '', lostPetsUrl: ''),
      [product(1, price: 9000)],
    ));
    expect(dropped, 1);
    expect(cart.lines.single.price, 9000);
  });

  test('hacer el pedido vacía el carrito y lo guarda en Mis pedidos', () async {
    final sent = <String, Map<String, dynamic>>{};
    final client = MockClient((req) async {
      sent[req.url.path] = jsonDecode(req.body) as Map<String, dynamic>;
      if (req.url.path.endsWith('order.php')) {
        return http.Response(
          jsonEncode({
            'ok': true,
            'order': orderJson(),
            'orderKey': 'clave',
            'whatsapp': '5491164722908',
            'whatsappText': 'Hola! Te hice el pedido #7 desde PetTime',
          }),
          201,
        );
      }
      return http.Response(jsonEncode({'ok': true, 'orders': [orderJson(status: 'accepted')]}), 200);
    });
    final cart = ShopCart(api: PetTimeApi(client: client, base: 'https://x'));
    await cart.load();
    await cart.add(product(1), 2);
    await cart.add(product(2, byWeight: true), 0.5);

    final result = await cart.placeOrder(
      const OrderContact(name: 'Lalo', phone: '11 6472-2908', address: 'Quirno Costa 1164'),
      note: 'Timbre 2B',
    );
    final body = sent['/shop/order.php']!;
    expect(body['name'], 'Lalo');
    expect(body['note'], 'Timbre 2B');
    expect(body['items'], [
      {'productId': 1, 'quantity': 2.0},
      {'productId': 2, 'quantity': 0.5},
    ]);
    expect(result.order.number, 7);
    expect(result.whatsapp, '5491164722908');
    expect(cart.isEmpty, isTrue);
    expect(cart.contact.address, 'Quirno Costa 1164');
    expect(cart.orders.single.statusText, 'Recibido');

    await cart.refreshOrders();
    expect(sent['/shop/orders.php']!['orders'], [
      {'id': 34, 'key': 'clave'},
    ]);
    expect(cart.orders.single.statusText, 'Aceptado');
  });

  test('si el servidor rechaza el pedido, el carrito queda como estaba', () async {
    final client = MockClient((_) async => http.Response.bytes(
          utf8.encode(jsonEncode({'ok': false, 'error': '"Producto 1" se quedó sin stock.'})),
          422,
        ));
    final cart = ShopCart(api: PetTimeApi(client: client, base: 'https://x'));
    await cart.load();
    await cart.add(product(1), 1);
    await expectLater(
      cart.placeOrder(const OrderContact(name: 'Lalo', phone: '1164722908', address: 'Quirno Costa 1164')),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('sin stock'))),
    );
    expect(cart.count, 1);
    expect(cart.hasOrders, isFalse);
  });

  testWidgets('el carrito pide nombre, WhatsApp y dirección antes de enviar', (tester) async {
    final cart = ShopCart(api: PetTimeApi(client: MockClient((_) async => http.Response('{}', 200)), base: 'https://x'));
    await cart.load();
    await cart.add(product(1), 1);
    await tester.pumpWidget(MaterialApp(home: CartScreen(cart: cart)));
    await tester.pumpAndSettle();
    expect(find.text('Producto 1'), findsOneWidget);

    await tester.scrollUntilVisible(find.textContaining('Hacer pedido'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.textContaining('Hacer pedido'));
    await tester.pumpAndSettle();
    expect(find.text('Escribí tu nombre', skipOffstage: false), findsOneWidget);
    expect(find.text('Escribí la dirección de entrega', skipOffstage: false), findsOneWidget);
    expect(cart.hasOrders, isFalse);
  });

  ShopCatalog catalogWith(List<ShopProduct> products) => ShopCatalog(
        ShopInfo(name: 'Lo De Lalo', whatsapp: '', address: '', catalogUrl: '', lostPetsUrl: ''),
        products,
      );

  PlacedOrder placed({bool canEdit = true}) => PlacedOrder.fromJson({
        ...orderJson(),
        'address': 'Quirno Costa 1164',
        'note': 'Timbre 2B',
        'canEdit': canEdit,
        'items': [
          {'productId': 1, 'name': 'Producto 1', 'quantity': 2, 'unitPrice': 8000, 'subtotal': 16000},
          {'productId': 7, 'name': 'Ya no se vende', 'quantity': 1, 'unitPrice': 500, 'subtotal': 500},
          {'productId': null, 'name': 'Agregado a mano', 'quantity': 1, 'unitPrice': 100, 'subtotal': 100},
        ],
      });

  test('repetir pedido: suma lo que se sigue vendiendo, al precio de hoy', () async {
    final cart = ShopCart(api: PetTimeApi(client: MockClient((_) async => http.Response('{}', 200)), base: 'https://x'));
    await cart.load();
    final missing = await cart.repeat(placed(), catalogWith([product(1, price: 9000)]));
    expect(missing, ['Ya no se vende', 'Agregado a mano']);
    expect(cart.lineFor(1)!.quantity, 2);
    expect(cart.lineFor(1)!.price, 9000);
    expect(cart.editing, isNull);
  });

  test('modificar pedido: lo carga en el carrito y guarda los cambios en el mismo pedido', () async {
    final sent = <String, Map<String, dynamic>>{};
    final client = MockClient((req) async {
      sent[req.url.path] = jsonDecode(req.body) as Map<String, dynamic>;
      if (req.url.path.endsWith('order_update.php')) {
        return http.Response(
          jsonEncode({'ok': true, 'order': {...orderJson(), 'total': 27000, 'canEdit': true}, 'whatsapp': '', 'whatsappText': ''}),
          200,
        );
      }
      return http.Response(
        jsonEncode({'ok': true, 'order': {...orderJson(), 'canEdit': true}, 'orderKey': 'clave', 'whatsapp': '', 'whatsappText': ''}),
        201,
      );
    });
    final cart = ShopCart(api: PetTimeApi(client: client, base: 'https://x'));
    await cart.load();
    await cart.add(product(1), 2);
    await cart.placeOrder(const OrderContact(name: 'Lalo', phone: '1164722908', address: 'Quirno Costa 1164'));

    await cart.startEditing(cart.orders.single, catalogWith([product(1), product(2)]));
    expect(cart.editing!.id, 34);
    expect(cart.lineFor(1)!.quantity, 2);
    await cart.add(product(2), 1);

    final result = await cart.placeOrder(
      const OrderContact(name: 'Lalo', phone: '1164722908', address: 'Otra calle 456'),
    );
    final body = sent['/shop/order_update.php']!;
    expect(body['id'], 34);
    expect(body['key'], 'clave');
    expect(body['address'], 'Otra calle 456');
    expect((body['items'] as List).length, 2);
    expect(result.order.total, 27000);
    expect(cart.orders.length, 1, reason: 'no crea un pedido nuevo');
    expect(cart.orders.single.total, 27000);
    expect(cart.isEmpty, isTrue);
    expect(cart.editing, isNull);
  });

  test('descartar la edición vacía el carrito y deja de modificar', () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({'ok': true, 'order': orderJson(), 'orderKey': 'clave', 'whatsapp': '', 'whatsappText': ''}),
          201,
        ));
    final cart = ShopCart(api: PetTimeApi(client: client, base: 'https://x'));
    await cart.load();
    await cart.add(product(1), 1);
    await cart.placeOrder(const OrderContact(name: 'Lalo', phone: '1164722908', address: 'Quirno Costa 1164'));
    await cart.startEditing(cart.orders.single, catalogWith([product(1)]));
    expect(cart.editing, isNotNull);
    await cart.clear();
    expect(cart.editing, isNull);
    expect(cart.isEmpty, isTrue);
  });
}
