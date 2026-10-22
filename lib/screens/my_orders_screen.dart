import 'package:flutter/material.dart';

import '../l10n/app_lang.dart';
import '../models/expense.dart';
import '../services/shop_orders.dart';
import '../theme.dart';

/// The orders made from the app and how each one is going at Lo De Lalo.
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key, this.cart});

  final ShopCart? cart;

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  late final _cart = widget.cart ?? ShopCart.instance;
  String? _error;

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
              padding: EdgeInsets.fromLTRB(12, 8, 12, 16 + MediaQuery.viewPaddingOf(context).bottom),
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
                    child: Text(tr('Todavía no hiciste pedidos.'), textAlign: TextAlign.center),
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
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              Chip(
                                label: Text(o.statusText),
                                labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                backgroundColor: _statusColor(o.status),
                                side: BorderSide.none,
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          if (o.createdAt.length >= 16)
                            Text(o.createdAt.substring(0, 16), style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 6),
                          for (final i in o.items)
                            Text('• ${formatCartQuantity(i.quantity, byWeight: false)} × ${i.name}'),
                          const SizedBox(height: 6),
                          Text(
                            tr('Total: {total}', {'total': formatMoney(o.total)}),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (o.status == 'rejected' && (o.rejectReason ?? '').isNotEmpty)
                            Text(tr('Motivo: {reason}', {'reason': o.rejectReason})),
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
