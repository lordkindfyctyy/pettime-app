import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/calendar_service.dart';
import '../state/pets_state.dart';
import 'pet_detail_screen.dart';
import 'pet_form_screen.dart';

class _CalendarButton extends StatelessWidget {
  const _CalendarButton();

  Future<void> _toggle(BuildContext context) async {
    final calendar = CalendarService.instance;
    final messenger = ScaffoldMessenger.of(context);
    final pets = context.read<PetsState>().pets;
    try {
      if (calendar.enabled) {
        await calendar.disable();
        messenger.showSnackBar(
          const SnackBar(content: Text('Google Calendar desconectado')),
        );
      } else {
        await calendar.enable();
        await calendar.syncAll(pets);
        messenger.showSnackBar(
          const SnackBar(content: Text('Agenda sincronizada con Google Calendar')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo conectar con Google Calendar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final calendar = CalendarService.instance;
    if (!calendar.supported) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: calendar,
      builder: (context, _) => IconButton(
        icon: Icon(
          calendar.enabled ? Icons.event_available : Icons.event_busy_outlined,
        ),
        tooltip: calendar.enabled
            ? 'Desconectar Google Calendar'
            : 'Conectar Google Calendar',
        onPressed: () => _toggle(context),
      ),
    );
  }
}

class PetsScreen extends StatelessWidget {
  const PetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pets = context.watch<PetsState>().pets;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis mascotas'),
        actions: const [_CalendarButton()],
      ),
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
