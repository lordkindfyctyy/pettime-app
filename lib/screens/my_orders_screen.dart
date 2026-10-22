import 'package:flutter/material.dart';

import '../l10n/app_lang.dart';
import '../models/expense.dart';
import '../services/shop_orders.dart';
import '../services/shop_service.dart';
import '../theme.dart';
import 'cart_screen.dart';

/// The orders made from the app and how each one is going at Lo De Lalo.
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key, this.cart, this.shop});

  final ShopCart? cart;
  final ShopService? shop;

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  late final _cart = widget.cart ?? ShopCart.instance;
  late final _shop = widget.shop ?? ShopService.instance;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      await _cart.refreshOrders();
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// Today's catalog, to put the products of an order back in the cart with
  /// their current price; the saved one when there is no internet.
  Future<ShopCatalog?> _catalog() async {
    try {
      return await _shop.fetch();
    } on Object {
      return _shop.cached();
    }
  }

  Future<void> _repeat(PlacedOrder order) async {
    setState(() => _busy = true);
    try {
      final catalog = await _catalog();
      if (!mounted) return;
      if (catalog == null) {
        _say(tr('No se pudo cargar la tienda'));
        return;
      }
      final missing = await _cart.repeat(order, catalog);
      if (!mounted) return;
      _openCart(missing);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(PlacedOrder order) async {
    if (!_cart.isEmpty && _cart.editing?.id != order.id) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('¿Vaciar el carrito?')),
          content: Text(
            tr(
              'Para modificar el pedido se reemplaza lo que tenés en el carrito.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancelar')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Modificar')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      final catalog = await _catalog();
      if (!mounted) return;
      if (catalog == null) {
        _say(tr('No se pudo cargar la tienda'));
        return;
      }
      final missing = await _cart.startEditing(order, catalog);
      if (!mounted) return;
      _openCart(missing);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openCart(List<String> missing) {
    if (missing.isNotEmpty) {
      _say(
        tr('Ya no están a la venta: {names}', {'names': missing.join(', ')}),
      );
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CartScreen(cart: _cart)),
    );
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  static Color _statusColor(String status) => switch (status) {
    'accepted' => Brand.orange,
    'converted' => Brand.teal,
    'rejected' => Colors.grey,
    _ => Brand.red,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Mis pedidos'))),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListenableBuilder(
          listenable: _cart,
          builder: (context, _) {
            final orders = _cart.orders;
            return ListView(
              padding: EdgeInsets.fromLTRB(
                12,
                8,
                12,
                16 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      tr('Sin conexión: mostramos el último estado guardado.'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (orders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      tr('Todavía no hiciste pedidos.'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final o in orders)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  tr('Pedido #{number}', {'number': o.number}),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              Chip(
                                label: Text(o.statusText),
                                labelStyle: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                                backgroundColor: _statusColor(o.status),
                                side: BorderSide.none,
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          if (o.createdAt.length >= 16)
                            Text(
                              o.createdAt.substring(0, 16),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          const SizedBox(height: 6),
                          for (final i in o.items)
                            Text(
                              '• ${formatCartQuantity(i.quantity, byWeight: false)} × ${i.name}',
                            ),
                          const SizedBox(height: 6),
                          Text(
                            tr('Total: {total}', {
                              'total': formatMoney(o.total),
                            }),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (o.status == 'rejected' &&
                              (o.rejectReason ?? '').isNotEmpty)
                            Text(
                              tr('Motivo: {reason}', {
                                'reason': o.rejectReason,
                              }),
                            ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.replay),
                                label: Text(tr('Repetir pedido')),
                                onPressed: _busy ? null : () => _repeat(o),
                              ),
                              if (o.canEdit)
                                FilledButton.tonalIcon(
                                  icon: const Icon(Icons.edit_outlined),
                                  label: Text(tr('Modificar')),
                                  onPressed: _busy ? null : () => _edit(o),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
