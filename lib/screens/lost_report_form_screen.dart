import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../l10n/app_lang.dart';
import '../models/lost_report.dart';
import '../models/pet.dart';
import '../services/lost_pets_service.dart';

/// Publishes a lost or found pet notice. From a pet's profile it starts
/// filled in with that pet ([pet]).
class LostReportFormScreen extends StatefulWidget {
  const LostReportFormScreen({super.key, this.pet, this.service});

  final Pet? pet;
  final LostPetsService? service;

  @override
  State<LostReportFormScreen> createState() => _LostReportFormScreenState();
}

class _LostReportFormScreenState extends State<LostReportFormScreen> {
  static const maxPhotos = 5;

  late final _service = widget.service ?? LostPetsService.instance;
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final _name = TextEditingController(text: widget.pet?.name ?? '');
  late final _species = TextEditingController(text: widget.pet?.species ?? '');
  late final _breed = TextEditingController(text: widget.pet?.breed ?? '');
  final _description = TextEditingController();
  final _zone = TextEditingController();
  final _contactName = TextEditingController();
  final _phone = TextEditingController();

  ReportKind _kind = ReportKind.lost;
  DateTime _when = DateTime.now();
  late final List<File> _photos = [
    if (widget.pet?.photoPath != null && File(widget.pet!.photoPath!).existsSync())
      File(widget.pet!.photoPath!),
  ];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _service.lastContact().then((c) {
      if (!mounted) return;
      if (_contactName.text.isEmpty) _contactName.text = c.$1;
      if (_phone.text.isEmpty) _phone.text = c.$2;
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _species, _breed, _description, _zone, _contactName, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addPhotos(ImageSource source) async {
    final left = maxPhotos - _photos.length;
    if (left <= 0) return;
    final List<XFile> picked;
    if (source == ImageSource.camera) {
      final one = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80,
      );
      picked = [?one];
    } else {
      picked = await _picker.pickMultiImage(
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80,
        limit: left > 1 ? left : null,
      );
    }
    setState(() => _photos.addAll(picked.take(left).map((x) => File(x.path))));
  }

  Future<void> _pickWhen() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    setState(() => _when = DateTime(
          day.year,
          day.month,
          day.day,
          time?.hour ?? _when.hour,
          time?.minute ?? _when.minute,
        ));
  }

  Future<void> _publish() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    if (_photos.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr('Agregá al menos una foto de la mascota'))),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await _service.publish(
        ReportDraft(
          kind: _kind,
          petName: _name.text.trim(),
          species: _species.text.trim(),
          breed: _breed.text.trim(),
          description: _description.text.trim(),
          eventAt: _when,
          zone: _zone.text.trim(),
          contactName: _contactName.text.trim(),
          contactPhone: _phone.text.trim(),
        ),
        _photos,
      );
      messenger.showSnackBar(SnackBar(
        content: Text(tr('Aviso publicado. Se ve en la app y en sixsevenweb.com')),
      ));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lost = _kind == ReportKind.lost;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Publicar aviso'))),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            24 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            SegmentedButton<ReportKind>(
              segments: [
                // Short labels that shrink instead of wrapping with a big font.
                ButtonSegment(
                  value: ReportKind.lost,
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(tr('Se perdió'), maxLines: 1, softWrap: false),
                  ),
                ),
                ButtonSegment(
                  value: ReportKind.found,
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(tr('La encontré'), maxLines: 1, softWrap: false),
                  ),
                ),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 16),
            Text(tr('Fotos (hasta {maxPhotos})', {'maxPhotos': maxPhotos}), style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, f) in _photos.indexed)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(f, width: 96, height: 96, fit: BoxFit.cover),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton.filledTonal(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: tr('Quitar foto'),
                          onPressed: () => setState(() => _photos.removeAt(i)),
                        ),
                      ),
                    ],
                  ),
                if (_photos.length < maxPhotos) ...[
                  _AddPhotoButton(
                    icon: Icons.photo_library_outlined,
                    label: tr('Galería'),
                    onTap: () => _addPhotos(ImageSource.gallery),
                  ),
                  _AddPhotoButton(
                    icon: Icons.photo_camera_outlined,
                    label: tr('Cámara'),
                    onTap: () => _addPhotos(ImageSource.camera),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: lost ? tr('Nombre de la mascota') : tr('Nombre (si tiene chapita)'),
              ),
              validator: (v) => lost && (v ?? '').trim().isEmpty
                  ? tr('Escribí el nombre de tu mascota')
                  : null,
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _species,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: tr('Especie'),
                      hintText: tr('Perro, gato…'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _breed,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(labelText: tr('Raza o color')),
                  ),
                ),
              ],
            ),
            TextFormField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              minLines: 1,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: tr('Descripción'),
                hintText: tr('Collar, señas, si es mansa o asustadiza…'),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(lost ? tr('Cuándo se perdió') : tr('Cuándo la viste')),
              subtitle: Text(DateFormat(tr("EEEE d 'de' MMMM, HH:mm"), AppLang.code).format(_when)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickWhen,
            ),
            TextFormField(
              controller: _zone,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr('Zona'),
                hintText: tr('Barrio y calles, ej. Villa Ballester, Pueyrredón y Alvear'),
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? tr('Indicá la zona') : null,
            ),
            TextFormField(
              controller: _contactName,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('Tu nombre (opcional)')),
            ),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: tr('Tu WhatsApp'),
                hintText: '11 6472-2908',
              ),
              validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 8
                  ? tr('Ingresá tu WhatsApp con código de área')
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              tr('El aviso es público: se ve en PetTime y en sixsevenweb.com durante 60 días. No pongas tu dirección exacta.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sending ? null : _publish,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.campaign_outlined),
              label: Text(_sending ? 'Publicando…' : tr('Publicar aviso')),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPhotoButton extends StatelessWidget {
  const _AddPhotoButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [Icon(icon), Text(label)],
          ),
        ),
      );
}
