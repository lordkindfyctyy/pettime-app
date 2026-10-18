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
import '../services/drive_backup_service.dart';
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

  /// Builds the backup and hands it to [deliver] (share it, or save it to a
  /// folder). [deliver] returns whether it was actually saved or sent.
  Future<void> _backup(
    Future<bool> Function(Uint8List bytes, String name) deliver,
  ) async {
    setState(() => _busy = true);
    try {
      final pets = context.read<PetsState>().pets;
      final now = DateTime.now();
      final bytes = BackupService.buildZip(pets, now: now);
      if (await deliver(bytes, BackupService.fileName(now))) {
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

  Future<bool> _share(Uint8List bytes, String name) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    final result = await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/zip')],
      subject: 'Copia de seguridad de PetTime',
      text: 'Copia de seguridad de PetTime. Para restaurarla: PetTime → '
          'Mascotas → ⋮ → Copia de seguridad → Restaurar.',
    ));
    return result.status != ShareResultStatus.dismissed;
  }

  /// Opens Android's "save as" screen: Descargas, any folder, or Google
  /// Drive, which shows up there as one more place.
  Future<bool> _saveToFolder(Uint8List bytes, String name) async {
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Guardar la copia de PetTime',
      fileName: name,
      bytes: bytes,
      mimeType: 'application/zip',
    );
    if (uri == null) return false;
    if (mounted) _toast('Copia guardada');
    return true;
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
    Uint8List? bytes;
    try {
      bytes = await (widget.pickBackup ?? _pickFromDevice)();
    } catch (_) {
      if (mounted) _toast('No se pudo abrir el archivo.');
      return;
    }
    if (bytes == null || !mounted) return;
    await _restoreBytes(bytes);
  }

  Future<void> _restoreFromDrive() async {
    setState(() => _busy = true);
    try {
      final found = await DriveBackupService.instance.download();
      if (!mounted) return;
      if (found == null) {
        _toast('No hay ninguna copia de PetTime en tu Google Drive.');
        return;
      }
      final (date, bytes) = found;
      await _restoreBytes(
        bytes,
        from: date == null
            ? null
            : 'Copia de Drive del ${DateFormat.yMMMd('es').add_Hm().format(date)}.',
      );
    } catch (e) {
      if (mounted) _toast('No se pudo bajar la copia de Drive: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleDrive(bool on) async {
    final drive = DriveBackupService.instance;
    setState(() => _busy = true);
    try {
      if (on) {
        await drive.enable(context.read<PetsState>().pets);
        if (mounted) _toast('Copia automática activada y guardada en Drive');
      } else {
        await drive.disable();
      }
    } catch (e) {
      if (mounted) _toast('No se pudo conectar con Google Drive: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBytes(Uint8List bytes, {String? from}) async {
    final state = context.read<PetsState>();
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
          '${from == null ? '' : '$from\n\n'}'
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
          if (DriveBackupService.instance.supported) ...[
            const SizedBox(height: 16),
            Card(
              child: ListenableBuilder(
                listenable: DriveBackupService.instance,
                builder: (context, _) {
                  final drive = DriveBackupService.instance;
                  final lastDrive = drive.lastBackup;
                  return Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.add_to_drive),
                        title: const Text('Copia automática en Google Drive'),
                        subtitle: Text(
                          drive.enabled
                              ? lastDrive == null
                                  ? 'Activada'
                                  : 'Última: ${DateFormat.yMMMd('es').add_Hm().format(lastDrive)}'
                              : 'Se guarda sola una vez por día, cuando abrís la app',
                        ),
                        value: drive.enabled,
                        onChanged: _busy ? null : _toggleDrive,
                      ),
                      ListTile(
                        leading: const Icon(Icons.cloud_download_outlined),
                        title: const Text('Restaurar desde Google Drive'),
                        subtitle: const Text('Por ejemplo, en un celular nuevo'),
                        enabled: !_busy,
                        onTap: _restoreFromDrive,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            last == null
                ? 'Todavía no hiciste ninguna copia manual.'
                : 'Última copia manual: ${DateFormat.yMMMd('es').add_Hm().format(last)}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : () => _backup(_saveToFolder),
            icon: const Icon(Icons.save_alt),
            label: const Text('Guardar en el celular o en Drive'),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => _backup(_share),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Compartir copia (WhatsApp, mail…)'),
          ),
          const SizedBox(height: 24),
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
