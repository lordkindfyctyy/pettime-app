import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_lang.dart';
import 'pettime_api.dart';
import 'shop_service.dart';

/// A product in the cart, with what is needed to show it without internet.
class CartLine {
  CartLine({
    required this.productId,
    required this.name,
    required this.price,
    required this.byWeight,
    required this.quantity,
    this.imageUrl,
  });

  final int productId;
  final String name;
  final double price;
  final bool byWeight;
  final String? imageUrl;

  /// Units, or kilos when [byWeight].
  final double quantity;

  double get subtotal => price * quantity;

  /// Each tap on + or −: one unit, or half a kilo.
  double get step => byWeight ? 0.5 : 1;

  String get quantityLabel => formatCartQuantity(quantity, byWeight: byWeight);

  CartLine copyWith({
    double? quantity,
    String? name,
    double? price,
    String? imageUrl,
  }) => CartLine(
    productId: productId,
    name: name ?? this.name,
    price: price ?? this.price,
    byWeight: byWeight,
    quantity: quantity ?? this.quantity,
    imageUrl: imageUrl ?? this.imageUrl,
  );

  factory CartLine.fromProduct(ShopProduct p, double quantity) => CartLine(
    productId: p.id,
    name: p.name,
    price: p.price,
    byWeight: p.byWeight,
    quantity: quantity,
    imageUrl: p.imageUrl,
  );

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'name': name,
    'price': price,
    'byWeight': byWeight,
    'quantity': quantity,
    'imageUrl': imageUrl,
  };

  factory CartLine.fromJson(Map<String, dynamic> j) => CartLine(
    productId: j['productId'] as int,
    name: j['name'] as String,
    price: (j['price'] as num).toDouble(),
    byWeight: j['byWeight'] as bool? ?? false,
    quantity: (j['quantity'] as num).toDouble(),
    imageUrl: j['imageUrl'] as String?,
  );
}

/// "2", or "1,5 kg" for products sold by the kilo.
String formatCartQuantity(double quantity, {required bool byWeight}) {
  final n = quantity == quantity.roundToDouble()
      ? quantity.toStringAsFixed(0)
      : localizedDecimal(quantity.toStringAsFixed(1));
  return byWeight ? '$n kg' : n;
}

/// Who receives the order; remembered for the next one.
class OrderContact {
  const OrderContact({this.name = '', this.phone = '', this.address = ''});

  final String name;
  final String phone;
  final String address;

  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    'address': address,
  };

  factory OrderContact.fromJson(Map<String, dynamic> j) => OrderContact(
    name: j['name'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    address: j['address'] as String? ?? '',
  );
}

/// An order made from the app, as the shop sees it in SixSeven.
class PlacedOrder {
  PlacedOrder({
    required this.id,
    required this.number,
    required this.total,
    required this.status,
    required this.statusLabel,
    required this.createdAt,
    required this.items,
    this.rejectReason,
    this.address = '',
    this.note = '',
    this.canEdit = false,
  });

  final int id;
  final int number;
  final double total;

  /// new, accepted, converted or rejected.
  final String status;
  final String statusLabel;
  final String createdAt;
  final String? rejectReason;
  final String address;

  /// What the customer wrote, without the server's "from PetTime" mark.
  final String note;

  /// The customer can still change it: the shop has not accepted it yet.
  final bool canEdit;

  /// productId is null when the shop added a free-text item.
  final List<({int? productId, String name, double quantity, double subtotal})>
  items;

  /// The shop's label is in Spanish; translated here.
  String get statusText => switch (status) {
    'new' => tr('Recibido'),
    'accepted' => tr('Aceptado'),
    'converted' => tr('Confirmado'),
    'rejected' => tr('Rechazado'),
    _ => statusLabel,
  };

  factory PlacedOrder.fromJson(Map<String, dynamic> j) => PlacedOrder(
    id: j['id'] as int,
    number: j['number'] as int? ?? j['id'] as int,
    total: (j['total'] as num).toDouble(),
    status: j['status'] as String,
    statusLabel: j['statusLabel'] as String? ?? '',
    createdAt: j['createdAt'] as String? ?? '',
    rejectReason: j['rejectReason'] as String?,
    address: j['address'] as String? ?? '',
    note: j['note'] as String? ?? '',
    canEdit: j['canEdit'] as bool? ?? false,
    items: [
      for (final i in j['items'] as List? ?? const [])
        (
          productId: (i as Map)['productId'] as int?,
          name: i['name'] as String,
          quantity: (i['quantity'] as num).toDouble(),
          subtotal: (i['subtotal'] as num).toDouble(),
        ),
    ],
  );
}

/// What the server answers when an order is placed.
class OrderResult {
  OrderResult(this.order, this.whatsapp, this.whatsappText);

  final PlacedOrder order;

  /// The shop's WhatsApp digits for wa.me; empty when it has none.
  final String whatsapp;
  final String whatsappText;
}

/// The shop cart and the orders made from the app. Orders become web orders
/// of Lo De Lalo in SixSeven (Encargos → Pedidos web); each one comes with a
/// key, kept here, to see how it is going.
class ShopCart extends ChangeNotifier {
  ShopCart({PetTimeApi? api}) : _api = api ?? PetTimeApi.instance;

  static final instance = ShopCart();

  static const _cartKey = 'shop_cart_v1';
  static const _contactKey = 'shop_order_contact';
  static const _ordersKey = 'shop_orders_v1';
  static const _editingKey = 'shop_cart_editing';

  final PetTimeApi _api;
  final List<CartLine> _lines = [];
  OrderContact _contact = const OrderContact();

  /// {id, key, order} of each order made, newest first.
  List<Map<String, dynamic>> _orders = [];
  bool _loaded = false;

  /// The order being changed in the cart ("Modificar"); null for a new one.
  int? _editingId;

  List<CartLine> get lines => List.unmodifiable(_lines);
  OrderContact get contact => _contact;
  bool get isEmpty => _lines.isEmpty;
  bool get hasOrders => _orders.isNotEmpty;

  PlacedOrder? get editing {
    for (final o in orders) {
      if (o.id == _editingId) return o;
    }
    return null;
  }

  /// How many products (not units) are in the cart, for the badge.
  int get count => _lines.length;
  double get total => _lines.fold(0, (sum, l) => sum + l.subtotal);

  List<PlacedOrder> get orders => [
    for (final o in _orders)
      if (o['order'] is Map)
        PlacedOrder.fromJson((o['order'] as Map).cast<String, dynamic>()),
  ];

  CartLine? lineFor(int productId) {
    for (final l in _lines) {
      if (l.productId == productId) return l;
    }
    return null;
  }

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    try {
      _lines
        ..clear()
        ..addAll([
          for (final j in jsonDecode(prefs.getString(_cartKey) ?? '[]') as List)
            CartLine.fromJson((j as Map).cast<String, dynamic>()),
        ]);
      _contact = OrderContact.fromJson(
        (jsonDecode(prefs.getString(_contactKey) ?? '{}') as Map)
            .cast<String, dynamic>(),
      );
      _orders = [
        for (final o in jsonDecode(prefs.getString(_ordersKey) ?? '[]') as List)
          (o as Map).cast<String, dynamic>(),
      ];
      _editingId = prefs.getInt(_editingKey);
    } on Object {
      // A broken save starts empty rather than blocking the shop.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _saveCart() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cartKey,
      jsonEncode([for (final l in _lines) l.toJson()]),
    );
  }

  Future<void> _saveOrders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ordersKey, jsonEncode(_orders));
  }

  /// Adds [quantity] of [product] (or sets it, when [replace]).
  Future<void> add(
    ShopProduct product,
    double quantity, {
    bool replace = false,
  }) async {
    final i = _lines.indexWhere((l) => l.productId == product.id);
    if (i < 0) {
      _lines.add(CartLine.fromProduct(product, quantity));
    } else {
      _lines[i] = _lines[i].copyWith(
        quantity: replace ? quantity : _lines[i].quantity + quantity,
        name: product.name,
        price: product.price,
        imageUrl: product.imageUrl,
      );
    }
    notifyListeners();
    await _saveCart();
  }

  /// Sets the quantity of a line; zero or less removes it.
  Future<void> setQuantity(int productId, double quantity) async {
    final i = _lines.indexWhere((l) => l.productId == productId);
    if (i < 0) return;
    if (quantity <= 0) {
      _lines.removeAt(i);
    } else {
      _lines[i] = _lines[i].copyWith(quantity: quantity);
    }
    notifyListeners();
    await _saveCart();
  }

  Future<void> remove(int productId) => setQuantity(productId, 0);

  /// Empties the cart and stops changing an order, if it was.
  Future<void> clear() async {
    _lines.clear();
    await _setEditing(null);
    notifyListeners();
    await _saveCart();
  }

  Future<void> _setEditing(int? orderId) async {
    _editingId = orderId;
    final prefs = await SharedPreferences.getInstance();
    if (orderId == null) {
      await prefs.remove(_editingKey);
    } else {
      await prefs.setInt(_editingKey, orderId);
    }
  }

  /// Adds the products of [order] that the shop still sells, at today's
  /// price. Returns the names of the ones left out.
  Future<List<String>> repeat(PlacedOrder order, ShopCatalog catalog) async {
    final byId = {for (final p in catalog.products) p.id: p};
    final missing = <String>[];
    for (final item in order.items) {
      final p = item.productId == null ? null : byId[item.productId];
      if (p == null || !p.inStock) {
        missing.add(item.name);
      } else {
        await add(p, item.quantity);
      }
    }
    return missing;
  }

  /// Puts [order] in the cart to change it; the cart had better be empty.
  /// Returns the names of the products that are no longer sold.
  Future<List<String>> startEditing(
    PlacedOrder order,
    ShopCatalog catalog,
  ) async {
    _lines.clear();
    final missing = await repeat(order, catalog);
    await _setEditing(order.id);
    notifyListeners();
    await _saveCart();
    return missing;
  }

  /// Updates names and prices with the catalog just loaded, and drops
  /// products the shop no longer sells. Returns how many were dropped.
  Future<int> syncWith(ShopCatalog catalog) async {
    final byId = {for (final p in catalog.products) p.id: p};
    var dropped = 0;
    for (var i = _lines.length - 1; i >= 0; i--) {
      final p = byId[_lines[i].productId];
      if (p == null) {
        _lines.removeAt(i);
        dropped++;
      } else {
        _lines[i] = _lines[i].copyWith(
          name: p.name,
          price: p.price,
          imageUrl: p.imageUrl,
        );
      }
    }
    notifyListeners();
    await _saveCart();
    return dropped;
  }

  /// Sends the cart as an order, or saves the changes of the order being
  /// edited. The server checks prices and stock again; on success the cart
  /// is emptied and the order is kept in "Mis pedidos".
  Future<OrderResult> placeOrder(
    OrderContact contact, {
    String note = '',
  }) async {
    _contact = contact;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contactKey, jsonEncode(contact.toJson()));

    final body = {
      'name': contact.name,
      'phone': contact.phone,
      'address': contact.address,
      'note': note,
      'items': [
        for (final l in _lines)
          {'productId': l.productId, 'quantity': l.quantity},
      ],
    };
    final editingEntry = _editingId == null ? null : _entry(_editingId!);
    final Map<String, dynamic> res;
    if (editingEntry != null) {
      res = await _api.post('shop/order_update.php', {
        'id': editingEntry['id'],
        'key': editingEntry['key'],
        ...body,
      });
      editingEntry['order'] = (res['order'] as Map).cast<String, dynamic>();
    } else {
      res = await _api.post('shop/order.php', body);
      final orderJson = (res['order'] as Map).cast<String, dynamic>();
      _orders.insert(0, {
        'id': orderJson['id'],
        'key': res['orderKey'],
        'order': orderJson,
      });
      if (_orders.length > 50) _orders = _orders.sublist(0, 50);
    }
    final orderJson = (res['order'] as Map).cast<String, dynamic>();
    await _saveOrders();
    await clear();
    return OrderResult(
      PlacedOrder.fromJson(orderJson),
      res['whatsapp'] as String? ?? '',
      res['whatsappText'] as String? ?? '',
    );
  }

  Map<String, dynamic>? _entry(int orderId) {
    for (final o in _orders) {
      if (o['id'] == orderId) return o;
    }
    return null;
  }

  /// Asks the server how the orders are going and keeps the answer.
  Future<void> refreshOrders() async {
    if (_orders.isEmpty) return;
    final res = await _api.post('shop/orders.php', {
      'orders': [
        for (final o in _orders) {'id': o['id'], 'key': o['key']},
      ],
    });
    final byId = {
      for (final o in res['orders'] as List)
        ((o as Map)['id'] as int): o.cast<String, dynamic>(),
    };
    for (final o in _orders) {
      final fresh = byId[o['id']];
      if (fresh != null) o['order'] = fresh;
    }
    notifyListeners();
    await _saveOrders();
  }
}
