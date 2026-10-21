import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_lang.dart';
import '../models/agenda.dart';
import '../models/health_record.dart';
import '../models/vet_visit.dart';
import '../state/pets_state.dart';
import '../theme.dart';
import '../widgets/health_booklet.dart';
import '../widgets/pet_avatar.dart';
import '../widgets/supply_section.dart';
import '../widgets/walk_section.dart';
import 'pet_detail_screen.dart';

/// Everything for today, of every pet: the doses (with a button to mark them
/// as given), today's appointments, the pets still to walk and the vaccines
/// or antiparasitics that are overdue or due within a week.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, this.clock});

  /// Current time; tests pass a fixed one.
  final DateTime Function()? clock;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  Timer? _timer;

  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    // Doses go from "pending" to "late" as time passes.
    if (widget.clock == null) {
      _timer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _openPet(String petId) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PetDetailScreen(petId: petId)),
      );

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PetsState>();
    final pets = state.pets;
    final now = _now;
    final doses = dosesOfDay(pets, now);
    final visits = visitsOfDay(pets, now);
    final due = recordsDueSoon(pets, now);
    final restock = suppliesToRestock(pets, now);
    final toWalk = petsToWalk(pets, now);
    final theme = Theme.of(context);
    final hm = DateFormat.Hm(AppLang.code);
    final dayMonth = DateFormat.yMMMd(AppLang.code);

    Widget header(String text, IconData icon, Color color) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: SectionTitle(text: text, icon: icon, color: color),
        );

    final children = <Widget>[];
    if (doses.isNotEmpty) {
      final left = doses.where((d) => !d.given).length;
      children.add(header(
        left == 0 ? tr('Medicación · todo dado ✓') : tr('Medicación · faltan {left}', {'left': left}),
        Icons.medication_outlined,
        Brand.red,
      ));
      for (final d in doses) {
        final missed = d.missed(now);
        final status = d.given
            ? tr('Dada a las {n}', {'n': hm.format(d.givenAt!)})
            : missed
                ? tr('Sin registrar')
                : now.isAfter(d.time)
                    ? tr('Atrasada')
                    : tr('Pendiente');
        final statusColor = d.given
            ? Colors.green.shade700
            : (missed || now.isAfter(d.time))
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant;
        final dose = d.med.dose.isEmpty ? '' : ' (${d.med.dose})';
        children.add(ListTile(
          leading: PetAvatar(pet: d.pet),
          title: Text('${hm.format(d.time)} · ${d.med.name}$dose'),
          subtitle: Text.rich(TextSpan(children: [
            TextSpan(text: '${d.pet.name} · '),
            TextSpan(
              text: status,
              style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
            ),
          ])),
          onTap: () => _openPet(d.pet.id),
          trailing: d.given
              ? Icon(Icons.check_circle, color: Colors.green.shade700)
              : d.canGive(now)
                  ? FilledButton.tonal(
                      onPressed: () => state.logDose(d.pet.id, d.med.id, now),
                      child: Text(tr('Dar')),
                    )
                  : null,
        ));
      }
    }

    if (visits.isNotEmpty) {
      children.add(header(tr('Turnos de hoy'), Icons.event_outlined, Brand.teal));
      for (final (pet, v) in visits) {
        children.add(ListTile(
          leading: Icon(
            v.kind == AppointmentKind.vet
                ? Icons.local_hospital_outlined
                : Icons.content_cut,
          ),
          title: Text('${hm.format(v.date)} · ${v.kind.placeLabel}: ${v.clinic}'),
          subtitle: Text([
            pet.name,
            if (v.reason.isNotEmpty) v.reason,
          ].join(' · ')),
          onTap: () => _openPet(pet.id),
        ));
      }
    }

    if (toWalk.isNotEmpty) {
      children.add(header(tr('Paseos'), Icons.directions_walk, Brand.teal));
      for (final pet in toWalk) {
        children.add(
          ListTile(
            leading: PetAvatar(pet: pet),
            title: Text(pet.name),
            subtitle: Text(tr('Todavía no salió hoy')),
            onTap: () => _openPet(pet.id),
            trailing: FilledButton.tonal(
              onPressed: () => showWalkDialog(context, pet),
              child: Text(tr('Anotar')),
            ),
          ),
        );
      }
    }

    if (restock.isNotEmpty) {
      children.add(header(
        tr('Por reponer'),
        Icons.shopping_basket_outlined,
        Brand.orange,
      ));
      for (final (pet, s) in restock) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SupplyCard(pet: pet, supply: s, now: now),
        ));
      }
    }

    if (due.isNotEmpty) {
      children.add(header(
        tr('Vacunas y antiparasitarios'),
        Icons.vaccines_outlined,
        Brand.orange,
      ));
      for (final (pet, r) in due) {
        children.add(ListTile(
          leading: Icon(healthIcon(r.kind)),
          title: Text('${r.name} · ${pet.name}'),
          subtitle: Text(
            '${dayMonth.format(r.nextDue!)} · ${dueLabel(r.nextDue!, now)}',
            style: TextStyle(
              color: dueColor(context, r.nextDue!),
              fontWeight: FontWeight.w600,
            ),
          ),
          onTap: () => _openPet(pet.id),
          trailing: IconButton(
            icon: const Icon(Icons.check_circle_outline),
            tooltip: tr('Registrar que se aplicó'),
            onPressed: () => openRecordForm(context, pet.id, repeatOf: r),
          ),
        ));
      }
    }

    final title = DateFormat(tr("EEEE d 'de' MMMM"), AppLang.code).format(now);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Hoy')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title[0].toUpperCase() + title.substring(1),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
        ),
      ),
      body: children.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  pets.isEmpty
                      ? tr('Agregá tu primera mascota en la pestaña Mascotas')
                      : tr('No hay nada para hoy 🎉'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            )
          : ListView(
              padding: EdgeInsets.only(
                bottom: 16 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              children: children,
            ),
    );
  }
}
