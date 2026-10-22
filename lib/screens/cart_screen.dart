import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_lang.dart';
import '../models/expense.dart';
import '../services/shop_orders.dart';
import '../theme.dart';
import 'my_orders_screen.dart';

/// The shop cart: change quantities, say who receives it and send the order
/// to Lo De Lalo (it shows up in SixSeven as a web order).
class CartScreen extends StatefulWidget {
  const CartScreen({super.key, this.cart});

  final ShopCart? cart;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  late final _cart = widget.cart ?? ShopCart.instance;
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: _cart.contact.name);
  late final _phone = TextEditingController(text: _cart.contact.phone);
  late final _address = TextEditingController(
    text: _cart.editing?.address ?? _cart.contact.address,
  );
  late final _note = TextEditingController(text: _cart.editing?.note ?? '');
  bool _sending = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _sending = true);
    final changing = _cart.editing != null;
    try {
      final result = await _cart.placeOrder(
        OrderContact(
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          address: _address.text.trim(),
        ),
        note: _note.text.trim(),
      );
      if (!mounted) return;
      await _showDone(result, changed: changing);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _cancelEditing() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('¿Descartar los cambios?')),
        content: Text(tr('El pedido queda como estaba y se vacía el carrito.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Seguir editando')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Descartar')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _cart.clear();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _showDone(OrderResult result, {required bool changed}) async {
    final values = {
      'number': result.order.number,
      'total': formatMoney(result.order.total),
    };
    final next = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Brand.teal, size: 48),
        title: Text(
          changed
              ? tr('¡Listo, pedido modificado!')
              : tr('¡Recibimos tu pedido!'),
        ),
        content: Text(
          changed
              ? tr(
                  'Pedido #{number}, ahora por {total}. Le avisamos a Lo De Lalo del cambio.',
                  values,
                )
              : tr(
                  'Pedido #{number} por {total}. Lo De Lalo te va a avisar por WhatsApp cuando lo acepte. '
                  'Podés ver cómo va en "Mis pedidos".',
                  values,
                ),
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actionsOverflowButtonSpacing: 4,
        actions: [
          if (result.whatsapp.isNotEmpty)
            OutlinedButton.icon(
              icon: const Icon(Icons.chat_outlined),
              label: Text(tr('Avisar también por WhatsApp')),
              onPressed: () => launchUrl(
                Uri.https('wa.me', '/${result.whatsapp}', {
                  'text': result.whatsappText,
                }),
                mode: LaunchMode.externalApplication,
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'orders'),
            child: Text(tr('Ver mis pedidos')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Listo')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (next == 'orders') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => MyOrdersScreen(cart: _cart)),
      );
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ListenableBuilder(
          listenable: _cart,
          builder: (context, _) => Text(
            _cart.editing == null
                ? tr('Tu carrito')
                : tr('Modificar pedido #{number}', {
                    'number': _cart.editing!.number,
                  }),
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: _cart,
        builder: (context, _) {
          final editing = _cart.editing;
          if (_cart.isEmpty && editing == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  tr('Todavía no agregaste productos.'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Form(
            key: _form,
            // A Column, not a ListView: fields scrolled out of sight must
            // still be built so that validate() checks them.
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                24 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (editing != null)
                    Card(
                      color: Brand.orange.withValues(alpha: 0.12),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                        child: Row(
                          children: [
                            const Icon(Icons.edit_note, color: Brand.orange),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                tr(
                                  'Estás cambiando el pedido #{number}. Podés sumar productos desde la Tienda.',
                                  {'number': editing.number},
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _cancelEditing,
                              child: Text(tr('Descartar')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_cart.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        tr('Todavía no agregaste productos.'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  for (final line in _cart.lines)
                    _LineTile(line: line, cart: _cart),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr('Total'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Text(
                        formatMoney(_cart.total),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Brand.red,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr(
                      'El precio final lo confirma Lo De Lalo al aceptar el pedido.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    tr('¿A quién y dónde lo entregamos?'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: tr('Tu nombre'),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) => (v ?? '').trim().length < 2
                        ? tr('Escribí tu nombre')
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: tr('Tu WhatsApp'),
                      hintText: tr('Ej: 11 6472-2908'),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v ?? '').replaceAll(RegExp(r'\D'), '').length < 8
                        ? tr('Escribí tu WhatsApp con código de área')
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _address,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: tr('Dirección de entrega'),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) => (v ?? '').trim().length < 5
                        ? tr('Escribí la dirección de entrega')
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _note,
                    maxLines: 2,
                    maxLength: 400,
                    decoration: InputDecoration(
                      labelText: tr('Aclaraciones (opcional)'),
                      hintText: tr(
                        'Ej: tocar timbre 2B, entregar después de las 18',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.shopping_bag_outlined),
                    label: Text(
                      editing == null
                          ? tr('Hacer pedido · {total}', {
                              'total': formatMoney(_cart.total),
                            })
                          : tr('Guardar cambios · {total}', {
                              'total': formatMoney(_cart.total),
                            }),
                    ),
                    onPressed: _sending || _cart.isEmpty ? null : _send,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.cart});

  final CartLine line;
  final ShopCart cart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 56,
              height: 56,
              color: Colors.white,
              child: line.imageUrl == null
                  ? const Icon(Icons.inventory_2_outlined, color: Colors.grey)
                  : Image.network(
                      line.imageUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.inventory_2_outlined,
                        color: Colors.grey,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(
                  formatMoney(line.subtotal),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Brand.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                QuantityStepper(
                  label: line.quantityLabel,
                  onMinus: () => cart.setQuantity(
                    line.productId,
                    line.quantity - line.step,
                  ),
                  onPlus: () => cart.setQuantity(
                    line.productId,
                    line.quantity + line.step,
                  ),
                  minusIcon: line.quantity <= line.step
                      ? Icons.delete_outline
                      : Icons.remove,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// − 2 + buttons; also used in the product sheet.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.label,
    required this.onMinus,
    required this.onPlus,
    this.minusIcon = Icons.remove,
  });

  final String label;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final IconData minusIcon;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton.outlined(
        icon: Icon(minusIcon),
        tooltip: tr('Menos'),
        visualDensity: VisualDensity.compact,
        onPressed: onMinus,
      ),
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 56),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      IconButton.outlined(
        icon: const Icon(Icons.add),
        tooltip: tr('Más'),
        visualDensity: VisualDensity.compact,
        onPressed: onPlus,
      ),
    ],
  );
}
