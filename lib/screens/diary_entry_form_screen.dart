import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/diary_entry.dart';
import '../services/photo_service.dart';
import '../state/pets_state.dart';
import '../theme.dart';
import '../widgets/photo_source_sheet.dart';

/// Writes or edits an entry of the pet's health diary: what was seen, the
/// symptoms ticked and up to [maxPhotos] photos.
class DiaryEntryFormScreen extends StatefulWidget {
  const DiaryEntryFormScreen({super.key, required this.petId, this.entry});

  final String petId;
  final DiaryEntry? entry;

  static const maxPhotos = 6;

  @override
  State<DiaryEntryFormScreen> createState() => _DiaryEntryFormScreenState();
}

class _DiaryEntryFormScreenState extends State<DiaryEntryFormScreen> {
  late final _text = TextEditingController(text: widget.entry?.text ?? '');
  late DateTime _date = widget.entry?.date ?? DateTime.now();
  late final _symptoms = {...?widget.entry?.symptoms};
  late final _photos = [...?widget.entry?.photos];

  /// Photos taken in this screen: deleted if it is left without saving.
  final _added = <String>{};
  bool _saved = false;

  @override
  void dispose() {
    _text.dispose();
    if (!_saved) {
      for (final p in _added) {
        PhotoService.instance.delete(p);
      }
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    setState(() {
      _date = DateTime(
        d.year,
        d.month,
        d.day,
        t?.hour ?? _date.hour,
        t?.minute ?? _date.minute,
      );
    });
  }

  Future<void> _addPhoto() async {
    final choice = await showPhotoSourceSheet(context, hasPhoto: false);
    if (choice is! PickPhoto) return;
    final path = await PhotoService.instance.pick(
      choice.source,
      'diary_${widget.entry?.id ?? 'new'}',
    );
    if (path == null) return;
    setState(() {
      _photos.add(path);
      _added.add(path);
    });
  }

  void _removePhoto(String path) {
    setState(() => _photos.remove(path));
    // A photo taken here and removed is not needed; one already saved is
    // deleted when the entry is saved without it.
    if (_added.remove(path)) PhotoService.instance.delete(path);
  }

  Future<void> _save() async {
    if (_symptoms.isEmpty && _text.text.trim().isEmpty && _photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Marcá un síntoma, escribí algo o agregá una foto'),
        ),
      );
      return;
    }
    final state = context.read<PetsState>();
    final navigator = Navigator.of(context);
    await state.saveDiaryEntry(
      widget.petId,
      DiaryEntry(
        id: widget.entry?.id ?? state.newId(),
        date: _date,
        symptoms: [
          for (final s in Symptom.values)
            if (_symptoms.contains(s)) s,
        ],
        text: _text.text.trim(),
        photos: _photos,
      ),
    );
    _saved = true;
    navigator.pop();
  }

  Future<void> _delete() async {
    final state = context.read<PetsState>();
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '¿Borrar la anotación del diario del '
          '${DateFormat.yMMMd('es').format(widget.entry!.date)}?',
        ),
        content: const Text(
          'Se borran también sus fotos. No se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await state.deleteDiaryEntry(widget.petId, widget.entry!.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final pet = context.watch<PetsState>().byId(widget.petId);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.entry == null ? 'Anotar en el diario' : 'Editar anotación',
        ),
        actions: [
          if (widget.entry != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Borrar',
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: const Text('Cuándo'),
            subtitle: Text(DateFormat.yMMMd('es').add_Hm().format(_date)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: _pickDate,
          ),
          const SizedBox(height: 8),
          Text('¿Qué le notaste?', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in Symptom.values)
                FilterChip(
                  label: Text(s.label),
                  selected: _symptoms.contains(s),
                  onSelected: (on) => setState(
                    () => on ? _symptoms.add(s) : _symptoms.remove(s),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Qué pasó',
              hintText: 'Vomitó dos veces a la mañana, después comió bien…',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('Fotos', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _photos)
                Stack(
                  children: [
                    DiaryPhoto(path: p, size: 96),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton.filledTonal(
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        tooltip: 'Quitar foto',
                        icon: const Icon(Icons.close),
                        onPressed: () => _removePhoto(p),
                      ),
                    ),
                  ],
                ),
              if (_photos.length < DiaryEntryFormScreen.maxPhotos)
                SizedBox(
                  width: 96,
                  height: 96,
                  child: OutlinedButton(
                    onPressed: _addPhoto,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Icon(Icons.add_a_photo_outlined, size: 32),
                  ),
                ),
            ],
          ),
          if (pet?.share != null) ...[
            const SizedBox(height: 8),
            Text(
              'Las fotos quedan solo en este celular; lo escrito le llega a todos.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Guardar'),
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

/// A square photo of the diary; tapping it opens it full screen.
class DiaryPhoto extends StatelessWidget {
  const DiaryPhoto({super.key, required this.path, this.size = 72});

  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(backgroundColor: Colors.black),
            body: Center(child: InteractiveViewer(child: Image.file(file))),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: size,
            height: size,
            color: Brand.pink,
            child: const Icon(Icons.broken_image_outlined),
          ),
        ),
      ),
    );
  }
}
