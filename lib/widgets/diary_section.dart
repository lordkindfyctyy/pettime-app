import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_lang.dart';
import '../models/diary_entry.dart';
import '../models/pet.dart';
import '../screens/diary_entry_form_screen.dart';
import '../state/pets_state.dart';
import '../theme.dart';

void openDiaryForm(BuildContext context, String petId, {DiaryEntry? entry}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => DiaryEntryFormScreen(petId: petId, entry: entry),
    ),
  );
}

/// One entry of the diary: when, the symptoms, what was written and the
/// photos. Tapping it edits it.
class DiaryEntryCard extends StatelessWidget {
  const DiaryEntryCard({super.key, required this.petId, required this.entry});

  final String petId;
  final DiaryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openDiaryForm(context, petId, entry: entry),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat(tr("EEEE d 'de' MMMM, HH:mm"), AppLang.code).format(entry.date),
                style: theme.textTheme.labelLarge,
              ),
              if (entry.symptoms.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final s in entry.symptoms)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Brand.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          s.label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: Brand.red,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (entry.text.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(entry.text, maxLines: 4, overflow: TextOverflow.ellipsis),
              ],
              if (entry.photos.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final p in entry.photos) DiaryPhoto(path: p)],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The diary in the pet's profile: the latest entries and a link to all.
class DiarySection extends StatelessWidget {
  const DiarySection({super.key, required this.pet});

  final Pet pet;

  static const shown = 3;

  @override
  Widget build(BuildContext context) {
    if (pet.diary.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          tr('Anotá síntomas, cambios o lo que te llame la atención, con fotos. Va en la ficha para el veterinario.'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final d in pet.diary.take(shown))
          DiaryEntryCard(petId: pet.id, entry: d),
        if (pet.diary.length > shown)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.menu_book_outlined),
              label: Text(tr('Ver todo el diario ({length})', {'length': pet.diary.length})),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DiaryScreen(petId: pet.id)),
              ),
            ),
          ),
      ],
    );
  }
}

/// Every entry of the diary, newest first, by month.
class DiaryScreen extends StatelessWidget {
  const DiaryScreen({super.key, required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context) {
    final pet = context.watch<PetsState>().byId(petId);
    if (pet == null) return const Scaffold(body: SizedBox.shrink());
    final month = DateFormat.yMMMM(AppLang.code);
    final children = <Widget>[];
    String? current;
    for (final d in pet.diary) {
      final m = month.format(d.date);
      if (m != current) {
        current = m;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
            child: Text(
              m[0].toUpperCase() + m.substring(1),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        );
      }
      children.add(DiaryEntryCard(petId: petId, entry: d));
    }
    return Scaffold(
      appBar: AppBar(title: Text(tr('Diario de {name}', {'name': pet.name}))),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.edit_note),
        label: Text(tr('Anotar')),
        onPressed: () => openDiaryForm(context, petId),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          12,
          0,
          12,
          88 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: children,
      ),
    );
  }
}
