import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../state/pets_state.dart';
import 'confirm_delete.dart';

/// Bottom sheet listing the doses given for one medication, newest first.
class DoseHistorySheet extends StatelessWidget {
  const DoseHistorySheet({super.key, required this.petId, required this.medId});

  final String petId;
  final String medId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PetsState>();
    final pet = state.byId(petId);
    final med = pet?.medications.where((m) => m.id == medId).firstOrNull;
    if (pet == null || med == null) return const SizedBox.shrink();

    final doses = med.givenDoses.reversed.toList();
    final fmt = DateFormat.yMMMd('es').add_Hm();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Tomas de ${med.name} · ${pet.name}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (doses.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Todavía no registraste ninguna toma'),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: doses.length,
                  itemBuilder: (context, i) => ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(fmt.format(doses[i])),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Quitar toma',
                      onPressed: () async {
                        if (await confirmDelete(
                          context,
                          'la toma de ${med.name} del ${fmt.format(doses[i])}',
                          detail: 'Queda como no dada. No se puede deshacer.',
                        )) {
                          await state.removeDose(petId, medId, doses[i]);
                        }
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
