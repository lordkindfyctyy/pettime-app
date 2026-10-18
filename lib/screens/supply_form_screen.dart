import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/supply.dart';
import '../state/pets_state.dart';

/// Adds or edits something to restock: what it is, how much a package
/// brings, how much is used per day and when the current one was opened.
class SupplyFormScreen extends StatefulWidget {
  const SupplyFormScreen({super.key, required this.petId, this.supply});

  final String petId;
  final Supply? supply;

  @override
  State<SupplyFormScreen> createState() => _SupplyFormScreenState();
}

class _SupplyFormScreenState extends State<SupplyFormScreen> {
  static const _warnOptions = [3, 5, 7, 10];

  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.supply?.name);
  late final _amount = TextEditingController(
    text: widget.supply == null ? '' : formatAmount(widget.supply!.packageAmount),
  );
  late final _perDay = TextEditingController(
    text: widget.supply == null ? '' : formatAmount(widget.supply!.perDay),
  );
  late SupplyKind _kind = widget.supply?.kind ?? SupplyKind.food;
  late String _unit = widget.supply?.unit ?? 'kg';
  late DateTime _openedOn =
      widget.supply?.openedOn ?? DateUtils.dateOnly(DateTime.now());
  late int _warn = widget.supply?.warnDaysBefore ?? 5;

  @override
  void initState() {
    super.initState();
    // Live summary of how long it lasts.
    _amount.addListener(_refresh);
    _perDay.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _perDay.dispose();
    super.dispose();
  }

  Supply? get _draft {
    final amount = parseAmount(_amount.text);
    final perDay = parseAmount(_perDay.text);
    if (amount == null || perDay == null) return null;
    return Supply(
      id: widget.supply?.id ?? '',
      name: _name.text.trim(),
      kind: _kind,
      packageAmount: amount,
      unit: _unit,
      perDay: perDay,
      openedOn: _openedOn,
      warnDaysBefore: _warn,
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<PetsState>();
    final draft = _draft!;
    await state.saveSupply(
      widget.petId,
      Supply(
        id: widget.supply?.id ?? state.newId(),
        name: draft.name,
        kind: draft.kind,
        packageAmount: draft.packageAmount,
        unit: draft.unit,
        perDay: draft.perDay,
        openedOn: draft.openedOn,
        warnDaysBefore: draft.warnDaysBefore,
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Eliminar ${widget.supply!.name}?'),
        content: const Text('Deja de avisar cuando se termine.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<PetsState>().deleteSupply(widget.petId, widget.supply!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.yMMMd('es');
    final draft = _draft;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.supply == null ? 'Nuevo producto' : 'Editar producto'),
        actions: [
          if (widget.supply != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Eliminar',
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            DropdownButtonFormField<SupplyKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: [
                for (final k in SupplyKind.values)
                  DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              onChanged: (k) => setState(() => _kind = k ?? _kind),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Producto',
                hintText: 'Royal Canin Fit 15 kg',
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Ingresá el producto' : null,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Trae el paquete',
                      hintText: '15',
                    ),
                    validator: (v) => parseAmount(v ?? '') == null
                        ? 'Ingresá la cantidad'
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: Supply.units.contains(_unit) ? _unit : 'unidades',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Unidad'),
                    items: [
                      for (final u in Supply.units)
                        DropdownMenuItem(value: u, child: Text(u)),
                    ],
                    onChanged: (u) => setState(() => _unit = u ?? _unit),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _perDay,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Usa por día',
                hintText: _unit == 'kg' ? '0,3' : '1',
                suffixText: '$_unit por día',
              ),
              validator: (v) =>
                  parseAmount(v ?? '') == null ? 'Ingresá cuánto usa por día' : null,
            ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Se abrió el paquete el'),
              subtitle: Text(fmt.format(_openedOn)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _openedOn,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _openedOn = d);
              },
            ),
            Text('Avisar antes', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final days in _warnOptions)
                  ChoiceChip(
                    label: Text('$days días'),
                    selected: _warn == days,
                    onSelected: (_) => setState(() => _warn = days),
                  ),
              ],
            ),
            if (draft != null) ...[
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(
                    'Dura ${(draft.packageAmount / draft.perDay).floor()} días: '
                    'se termina el ${fmt.format(draft.runsOutOn)}',
                  ),
                  subtitle: Text('Te avisamos el ${fmt.format(draft.warnOn)} '
                      'y el día que se termina.'),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(onPressed: _submit, child: const Text('Guardar')),
          ],
        ),
      ),
    );
  }
}
