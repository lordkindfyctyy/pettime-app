import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pet.dart';
import '../services/backup_service.dart';
import '../state/pets_state.dart';

/// Saves everything to a .zip (shared to Google Drive, WhatsApp, mail…) and
/// restores it on this or another phone.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, this.pickBackup});

  /// Picks the backup file; tests pass a fake one.
  final Future<Uint8List?> Function()? pickBackup;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  static const lastBackupKey = 'last_backup_at';

  DateTime? _lastBackup;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final raw = prefs.getString(lastBackupKey);
      if (raw != null && mounted) {
        setState(() => _lastBackup = DateTime.tryParse(raw));
      }
    });
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final pets = context.read<PetsState>().pets;
      final now = DateTime.now();
      final bytes = BackupService.buildZip(pets, now: now);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${BackupService.fileName(now)}');
      await file.writeAsBytes(bytes);
      final result = await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/zip')],
        subject: 'Copia de seguridad de PetTime',
        text: 'Copia de seguridad de PetTime. Para restaurarla: PetTime → '
            'Mascotas → ⋮ → Copia de seguridad → Restaurar.',
      ));
      if (result.status != ShareResultStatus.dismissed) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(lastBackupKey, now.toIso8601String());
        if (mounted) setState(() => _lastBackup = now);
      }
    } catch (e) {
      if (mounted) _toast('No se pudo armar la copia: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static Future<Uint8List?> _pickFromDevice() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Elegí la copia de PetTime',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    return file == null ? null : await file.readAsBytes();
  }

  Future<void> _restore() async {
    final state = context.read<PetsState>();
    Uint8List? bytes;
    try {
      bytes = await (widget.pickBackup ?? _pickFromDevice)();
    } catch (_) {
      if (mounted) _toast('No se pudo abrir el archivo.');
      return;
    }
    if (bytes == null || !mounted) return;

    final List<Pet> pets;
    try {
      final docs = await getApplicationDocumentsDirectory();
      pets = BackupService.readZip(bytes, Directory('${docs.path}/pet_photos'));
    } on FormatException catch (e) {
      if (mounted) _toast(e.message);
      return;
    }
    if (!mounted) return;

    final current = state.pets.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Restaurar la copia?'),
        content: Text(
          'La copia tiene ${_count(pets.length)}: '
          '${pets.map((p) => p.name).join(', ')}.\n\n'
          '${current == 0 ? 'Se cargan en este celular.' : 'Reemplaza lo que hay ahora en este celular (${_count(current)}).'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await state.replaceAll(pets);
    if (mounted) _toast('Copia restaurada');
  }

  static String _count(int n) => n == 1 ? '1 mascota' : '$n mascotas';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _lastBackup;
    return Scaffold(
      appBar: AppBar(title: const Text('Copia de seguridad')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          Text(
            'Todo queda guardado solo en este celular. Hacé una copia de vez '
            'en cuando y guardala en Google Drive o mandátela por WhatsApp o '
            'mail: si cambiás o perdés el celular, la restaurás y no perdés '
            'nada.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          Text(
            'Incluye las mascotas con sus fotos, la medicación, las tomas dadas, '
            'los turnos y la libreta de vacunas.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text(
            last == null
                ? 'Todavía no hiciste ninguna copia.'
                : 'Última copia: ${DateFormat.yMMMd('es').add_Hm().format(last)}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Guardar copia'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _restore,
            icon: const Icon(Icons.restore),
            label: const Text('Restaurar una copia'),
          ),
        ],
      ),
    );
  }
}
