import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_lang.dart';
import '../models/weight_entry.dart';
import '../state/auth_state.dart';
import '../state/pets_state.dart';
import '../theme.dart';
import '../widgets/account_dialog.dart';
import '../widgets/family_share.dart';
import '../widgets/language_dialog.dart';
import '../widgets/pet_avatar.dart';
import '../widgets/supply_section.dart';
import 'backup_screen.dart';
import 'pet_detail_screen.dart';
import 'pet_form_screen.dart';

class PetsScreen extends StatelessWidget {
  const PetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pets = context.watch<PetsState>().pets;
    final auth = context.watch<AuthState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Mis mascotas')),
        actions: [
          PopupMenuButton<void>(
            itemBuilder: (_) => [
              if (auth.available)
                PopupMenuItem(
                  child: ListTile(
                    leading: const Icon(Icons.account_circle_outlined),
                    title: Text(
                      auth.signedIn ? auth.user!.label : tr('Iniciar sesión'),
                      overflow: TextOverflow.ellipsis,
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  onTap: () => showAccountDialog(context),
                ),
              PopupMenuItem(
                child: ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(tr('Idioma')),
                  contentPadding: EdgeInsets.zero,
                ),
                onTap: () => showLanguageDialog(context),
              ),
              PopupMenuItem(
                child: ListTile(
                  leading: Icon(Icons.backup_outlined),
                  title: Text(tr('Copia de seguridad')),
                  contentPadding: EdgeInsets.zero,
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BackupScreen()),
                ),
              ),
              PopupMenuItem(
                child: ListTile(
                  leading: Icon(Icons.storefront_outlined),
                  title: Text(tr('Pet shop para pedidos')),
                  contentPadding: EdgeInsets.zero,
                ),
                onTap: () => showShopSettingsDialog(context),
              ),
              PopupMenuItem(
                child: ListTile(
                  leading: Icon(Icons.group_add_outlined),
                  title: Text(tr('Unirme con un código')),
                  contentPadding: EdgeInsets.zero,
                ),
                onTap: () => showJoinFamilyDialog(context),
              ),
            ],
          ),
        ],
      ),
      body: pets.isEmpty
          ? Center(child: Text(tr('Todavía no agregaste ninguna mascota')))
          : ListView.builder(
              itemCount: pets.length,
              itemBuilder: (context, i) {
                final pet = pets[i];
                final details = [
                  if (pet.species.isNotEmpty) pet.species,
                  if (pet.ageLabel() != null) pet.ageLabel()!,
                  if (pet.currentWeight != null) formatKg(pet.currentWeight!.kg),
                ].join(' · ');
                return ListTile(
                  leading: PetAvatar(pet: pet),
                  title: Text(pet.name),
                  subtitle: details.isEmpty ? null : Text(details),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (pet.share != null)
                        Icon(
                          Icons.family_restroom,
                          color: Brand.teal,
                          semanticLabel: tr('Compartida con la familia'),
                        ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
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
        label: Text(tr('Mascota')),
      ),
    );
  }
}
