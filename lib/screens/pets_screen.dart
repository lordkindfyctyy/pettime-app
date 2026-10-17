import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/pets_state.dart';
import 'pet_detail_screen.dart';
import 'pet_form_screen.dart';

class PetsScreen extends StatelessWidget {
  const PetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pets = context.watch<PetsState>().pets;
    return Scaffold(
      appBar: AppBar(title: const Text('Mis mascotas')),
      body: pets.isEmpty
          ? const Center(child: Text('Todavía no agregaste ninguna mascota'))
          : ListView.builder(
              itemCount: pets.length,
              itemBuilder: (context, i) {
                final pet = pets[i];
                final details = [
                  if (pet.species.isNotEmpty) pet.species,
                  if (pet.ageLabel() != null) pet.ageLabel()!,
                ].join(' · ');
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(pet.name.characters.first.toUpperCase()),
                  ),
                  title: Text(pet.name),
                  subtitle: details.isEmpty ? null : Text(details),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PetDetailScreen(petId: pet.id),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PetFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Mascota'),
      ),
    );
  }
}
