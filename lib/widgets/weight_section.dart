import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_lang.dart';
import '../models/pet.dart';
import '../models/weight_entry.dart';
import '../state/pets_state.dart';
import '../theme.dart';
import 'confirm_delete.dart';

/// Asks for a weight and its date and saves it.
Future<void> showAddWeightDialog(BuildContext context, Pet pet) async {
  final state = context.read<PetsState>();
  final result = await showDialog<(double, DateTime)>(
    context: context,
    builder: (_) => _AddWeightDialog(pet: pet),
  );
  if (result == null) return;
  final (kg, date) = result;
  await state.addWeight(
    pet.id,
    WeightEntry(id: state.newId(), date: date, kg: kg),
  );
}

class _AddWeightDialog extends StatefulWidget {
  const _AddWeightDialog({required this.pet});

  final Pet pet;

  @override
  State<_AddWeightDialog> createState() => _AddWeightDialogState();
}

class _AddWeightDialogState extends State<_AddWeightDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _kg = TextEditingController(
    // Starts with the last weight, usually close to the new one.
    text: widget.pet.currentWeight == null
        ? ''
        : formatKg(widget.pet.currentWeight!.kg).replaceAll(' kg', ''),
  );
  DateTime _date = DateUtils.dateOnly(DateTime.now());

  @override
  void dispose() {
    _kg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Peso de {name}', {'name': widget.pet.name})),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _kg,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr('Peso'),
                suffixText: tr('kg'),
                hintText: '32,5',
              ),
              validator: (v) =>
                  parseKg(v ?? '') == null ? tr('Ingresá el peso en kg') : null,
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Fecha')),
              subtitle: Text(DateFormat.yMMMd(AppLang.code).format(_date)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancelar')),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, (parseKg(_kg.text)!, _date));
            }
          },
          child: Text(tr('Guardar')),
        ),
      ],
    );
  }
}

/// The pet's weight in its profile: the latest one, how much it changed since
/// the previous one, and a chart of the last weighings.
class WeightSection extends StatelessWidget {
  const WeightSection({super.key, required this.pet});

  final Pet pet;

  @override
  Widget build(BuildContext context) {
    final weights = pet.weights;
    final theme = Theme.of(context);
    if (weights.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(tr('Todavía no anotaste ningún peso')),
      );
    }
    final fmt = DateFormat.yMMMd(AppLang.code);
    final last = weights.last;
    final previous = weights.length > 1 ? weights[weights.length - 2] : null;
    final diff = previous == null ? null : last.kg - previous.kg;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatKg(last.kg),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Brand.teal,
                  ),
                ),
                const SizedBox(width: 12),
                if (diff != null)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        diff.abs() < 0.005
                            ? tr('Igual que antes')
                            : '${diff > 0 ? '▲ +' : '▼ −'}'
                                '${formatKg(diff.abs())}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: diff.abs() < 0.005
                              ? theme.colorScheme.onSurfaceVariant
                              : diff > 0
                                  ? Brand.orange
                                  : Brand.teal,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Text(
              previous == null
                  ? tr('Pesado el {n}', {'n': fmt.format(last.date)})
                  : tr('Pesado el {n} · antes {n2} ({n3})', {'n': fmt.format(last.date), 'n2': formatKg(previous.kg), 'n3': fmt.format(previous.date)}),
              style: theme.textTheme.bodySmall,
            ),
            if (weights.length > 1) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 140,
                width: double.infinity,
                child: CustomPaint(
                  painter: WeightChartPainter(
                    weights.length > 12
                        ? weights.sublist(weights.length - 12)
                        : weights,
                    lineColor: Brand.teal,
                    textStyle: theme.textTheme.labelSmall!,
                  ),
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.history),
                label: Text(tr('Historial ({length})', {'length': weights.length})),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => WeightHistorySheet(petId: pet.id),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every weighing, newest first, to check or delete a wrong one.
class WeightHistorySheet extends StatelessWidget {
  const WeightHistorySheet({super.key, required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PetsState>();
    final pet = state.byId(petId);
    if (pet == null) return const SizedBox.shrink();
    final fmt = DateFormat.yMMMd(AppLang.code);
    final list = pet.weights.reversed.toList();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                tr('Pesos de {name}', {'name': pet.name}),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final w in list)
                    ListTile(
                      leading: const Icon(Icons.monitor_weight_outlined),
                      title: Text(formatKg(w.kg)),
                      subtitle: Text(fmt.format(w.date)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: tr('Borrar'),
                        onPressed: () async {
                          if (await confirmDelete(
                            context,
                            tr('el peso de {n} del {n2}', {'n': formatKg(w.kg), 'n2': fmt.format(w.date)}),
                          )) {
                            await state.deleteWeight(petId, w.id);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple line chart of weighings: weight up, time to the right (spaced by
/// date), with the lowest and highest weights and the first and last dates.
class WeightChartPainter extends CustomPainter {
  WeightChartPainter(
    this.weights, {
    required this.lineColor,
    required this.textStyle,
  });

  final List<WeightEntry> weights;
  final Color lineColor;
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (weights.length < 2) return;
    final minKg = weights.map((w) => w.kg).reduce(math.min);
    final maxKg = weights.map((w) => w.kg).reduce(math.max);
    // Some margin so a flat line is drawn in the middle.
    final pad = math.max((maxKg - minKg) * 0.15, 0.5);
    final low = minKg - pad, high = maxKg + pad;

    const left = 52.0, bottom = 20.0, top = 6.0, right = 8.0;
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    final t0 = weights.first.date.millisecondsSinceEpoch.toDouble();
    final t1 = weights.last.date.millisecondsSinceEpoch.toDouble();
    final span = math.max(t1 - t0, 1.0);

    Offset at(WeightEntry e) => Offset(
          left + w * (e.date.millisecondsSinceEpoch - t0) / span,
          top + h * (1 - (e.kg - low) / (high - low)),
        );

    final grid = Paint()
      ..color = textStyle.color?.withValues(alpha: 0.15) ?? Colors.black12
      ..strokeWidth = 1;
    for (final kg in [minKg, maxKg]) {
      final y = top + h * (1 - (kg - low) / (high - low));
      canvas.drawLine(Offset(left, y), Offset(left + w, y), grid);
      _text(canvas, formatKg(kg), Offset(0, y - 7), maxWidth: left - 4);
    }

    final points = weights.map(at).toList();
    final fill = Path()..moveTo(points.first.dx, top + h);
    for (final p in points) {
      fill.lineTo(p.dx, p.dy);
    }
    fill
      ..lineTo(points.last.dx, top + h)
      ..close();
    canvas.drawPath(fill, Paint()..color = lineColor.withValues(alpha: 0.12));

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    for (final p in points) {
      canvas.drawCircle(p, 4.5, Paint()..color = Colors.white);
      canvas.drawCircle(
        p,
        4.5,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }

    final dates = DateFormat.MMMd(AppLang.code);
    _text(canvas, dates.format(weights.first.date), Offset(left, top + h + 4));
    final end = dates.format(weights.last.date);
    _text(canvas, end, Offset(left + w, top + h + 4), alignRight: true);
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    double maxWidth = 120,
    bool alignRight = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, alignRight ? at - Offset(tp.width, 0) : at);
  }

  @override
  bool shouldRepaint(WeightChartPainter old) =>
      old.weights != weights || old.lineColor != lineColor;
}
