import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/pet.dart';
import '../models/supply.dart';
import '../screens/supply_form_screen.dart';
import '../services/shop_settings.dart';
import '../state/pets_state.dart';
import '../theme.dart';

void openSupplyForm(BuildContext context, String petId, {Supply? supply}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => SupplyFormScreen(petId: petId, supply: supply),
    ),
  );
}

/// Opens WhatsApp with the order already written, to the pet shop's number
/// when it is set.
Future<void> orderByWhatsApp(BuildContext context, Pet pet, Supply supply) async {
  final messenger = ScaffoldMessenger.of(context);
  final uri = whatsAppUri(
    orderMessage(supply, pet.name),
    phone: ShopSettings.instance.phone,
  );
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!opened) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No se pudo abrir WhatsApp')),
    );
  }
}

/// Asks for the pet shop's name and WhatsApp number.
Future<void> showShopSettingsDialog(BuildContext context) async {
  final shop = ShopSettings.instance;
  final name = TextEditingController(text: shop.name);
  final phone = TextEditingController(text: shop.phone);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Pet shop para pedidos'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Nombre'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'WhatsApp',
              hintText: '+54 9 11 1234-5678',
              helperText: 'Con código de país y de área. Si lo dejás vacío,\n'
                  'WhatsApp te deja elegir a quién mandarlo.',
              helperMaxLines: 3,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
  if (ok == true) await shop.save(name: name.text, phone: phone.text);
  // The dialog may still be animating out; free the fields afterwards.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    name.dispose();
    phone.dispose();
  });
}

IconData supplyIcon(SupplyKind kind) => switch (kind) {
      SupplyKind.food => Icons.set_meal_outlined,
      SupplyKind.medicine => Icons.medication_outlined,
      SupplyKind.other => Icons.inventory_2_outlined,
    };

Color supplyColor(BuildContext context, Supply s, DateTime now) {
  final days = s.daysLeft(now);
  if (days <= 0) return Theme.of(context).colorScheme.error;
  if (s.needsRestock(now)) return Brand.orange;
  return Brand.teal;
}

/// One thing to restock in the pet's profile: how much is left, when it runs
/// out, and buttons to order it or to say a new package was opened.
class SupplyCard extends StatelessWidget {
  const SupplyCard({super.key, required this.pet, required this.supply, this.now});

  final Pet pet;
  final Supply supply;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final at = now ?? DateTime.now();
    final color = supplyColor(context, supply, at);
    final fmt = DateFormat.yMMMd('es');
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openSupplyForm(context, pet.id, supply: supply),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(supplyIcon(supply.kind), color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(supply.name, style: theme.textTheme.titleMedium),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: supply.fractionLeft(at),
                    minHeight: 10,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.15),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${daysLeftLabel(supply.daysLeft(at))} · '
                'se termina el ${fmt.format(supply.runsOutOn)}',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
              Text(
                'Usa ${formatAmount(supply.perDay)} ${supply.unit} por día',
                style: theme.textTheme.bodySmall,
              ),
              Wrap(
                alignment: WrapAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.autorenew),
                    label: const Text('Repuse'),
                    onPressed: () =>
                        context.read<PetsState>().restock(pet.id, supply.id),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('Pedir por WhatsApp'),
                    onPressed: () => orderByWhatsApp(context, pet, supply),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
