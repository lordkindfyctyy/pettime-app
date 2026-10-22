import 'dart:io';
import 'dart:ui' as ui;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_lang.dart';
import '../models/pet.dart';
import '../models/supply.dart';
import '../services/lost_pets_service.dart';
import '../services/shop_settings.dart';
import '../services/tag_pdf.dart';
import '../services/tag_service.dart';
import '../services/vet_report.dart';
import '../state/pets_state.dart';
import '../theme.dart';
import '../widgets/confirm_delete.dart';

/// The pet's collar tag with a QR: whoever finds the pet scans it and sees
/// its photo and the family's WhatsApp. Here it is created, printed, marked
/// as lost and ordered engraved from the pet shop.
class PetTagScreen extends StatefulWidget {
  const PetTagScreen({super.key, required this.petId, this.tags});

  final String petId;

  /// The tests pass one that doesn't use the server.
  final TagService? tags;

  @override
  State<PetTagScreen> createState() => _PetTagScreenState();
}

class _PetTagScreenState extends State<PetTagScreen> {
  late final TagService _tags = widget.tags ?? TagService.instance;
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final pet = context.watch<PetsState>().byId(widget.petId);
    if (pet == null) return const Scaffold();
    return ListenableBuilder(
      listenable: _tags,
      builder: (context, _) {
        final tag = _tags.of(pet.id);
        final showForm = tag == null || _editing;
        return Scaffold(
          appBar: AppBar(title: Text(tr('Chapita de {pet}', {'pet': pet.name}))),
          body: showForm
              ? _TagForm(
                  pet: pet,
                  tag: tag,
                  tags: _tags,
                  onDone: () => setState(() => _editing = false),
                )
              : _TagView(
                  pet: pet,
                  tag: tag,
                  tags: _tags,
                  onEdit: () => setState(() => _editing = true),
                ),
        );
      },
    );
  }
}

class _TagForm extends StatefulWidget {
  const _TagForm({
    required this.pet,
    required this.tag,
    required this.tags,
    required this.onDone,
  });

  final Pet pet;
  final PetTag? tag;
  final TagService tags;
  final VoidCallback onDone;

  @override
  State<_TagForm> createState() => _TagFormState();
}

class _TagFormState extends State<_TagForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.tag?.contactName);
  late final _phone = TextEditingController(text: widget.tag?.contactPhone);
  late final _message = TextEditingController(text: widget.tag?.message);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.tag == null) _prefillContact();
  }

  /// The contact of the last lost & found notice, so it isn't typed twice.
  Future<void> _prefillContact() async {
    final (name, phone) = await LostPetsService.instance.lastContact();
    if (!mounted) return;
    if (_name.text.isEmpty) _name.text = name;
    if (_phone.text.isEmpty) _phone.text = phone;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.tags.save(
        widget.pet,
        contactName: _name.text,
        contactPhone: _phone.text,
        message: _message.text,
        lost: widget.tag?.lost ?? false,
      );
      await LostPetsService.instance.saveContact(_name.text.trim(), _phone.text.trim());
      widget.onDone();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final creating = widget.tag == null;
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (creating) ...[
            const Icon(Icons.qr_code_2, size: 72, color: Brand.red),
            const SizedBox(height: 8),
            Text(
              tr('Una chapita con un QR para el collar. Si {pet} se pierde, quien '
                  'la encuentre escanea el QR con la cámara y ve su foto y tu '
                  'WhatsApp, sin instalar nada.', {'pet': widget.pet.name}),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: tr('Tu nombre (opcional)')),
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          TextFormField(
            controller: _message,
            maxLines: 3,
            maxLength: 300,
            decoration: InputDecoration(
              labelText: tr('Mensaje para quien la encuentre (opcional)'),
              hintText: tr('Toma un remedio para el corazón. Es mansa.'),
            ),
          ),
          Text(
            tr('Se muestran en una página pública de sixsevenweb.com: el nombre y '
                'la foto de {pet}, tu nombre, tu WhatsApp y el mensaje.',
                {'pet': widget.pet.name}),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.qr_code_2),
            label: Text(_busy
                ? tr('Guardando…')
                : creating
                    ? tr('Crear chapita')
                    : tr('Guardar cambios')),
            onPressed: _busy ? null : _save,
          ),
          if (!creating)
            TextButton(onPressed: widget.onDone, child: Text(tr('Cancelar'))),
        ],
      ),
    );
  }
}

class _TagView extends StatefulWidget {
  const _TagView({
    required this.pet,
    required this.tag,
    required this.tags,
    required this.onEdit,
  });

  final Pet pet;
  final PetTag tag;
  final TagService tags;
  final VoidCallback onEdit;

  @override
  State<_TagView> createState() => _TagViewState();
}

class _TagViewState extends State<_TagView> {
  final _card = GlobalKey();
  bool _busy = false;

  Future<void> _run(Future<void> Function() task) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await task();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printPdf() => _run(() async {
        final bytes = await TagPdf.build(
          petName: widget.pet.name,
          url: widget.tag.url,
          assets: await VetReportAssets.load(),
        );
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/${TagPdf.fileName(widget.pet.name)}');
        await file.writeAsBytes(bytes);
        await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: tr('Chapita de {pet}', {'pet': widget.pet.name}),
        ));
      });

  /// The QR card as a picture, e.g. to send to whoever engraves the tag.
  Future<void> _shareImage() => _run(() async {
        final boundary =
            _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 4);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/QR ${widget.pet.name}.png');
        await file.writeAsBytes(png!.buffer.asUint8List());
        await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: widget.tag.url,
        ));
      });

  Future<void> _orderEngraved() async {
    final shop = ShopSettings.instance;
    final message = tr(
      'Hola! Quiero una chapita grabada con el QR de {pet}. Este es el link del QR: {url}',
      {'pet': widget.pet.name, 'url': widget.tag.url},
    );
    await launchUrl(
      whatsAppUri(message, phone: shop.phone),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _delete() async {
    if (!await confirmDelete(
      context,
      tr('la chapita de {pet}', {'pet': widget.pet.name}),
      detail: tr('El QR deja de mostrar a {pet}. Si la volvés a crear, tiene un QR '
          'nuevo y hay que reimprimirlo.', {'pet': widget.pet.name}),
    )) {
      return;
    }
    await _run(() => widget.tags.delete(widget.pet.id));
  }

  @override
  Widget build(BuildContext context) {
    final tag = widget.tag;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: RepaintBoundary(
            key: _card,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Brand.red, width: 3),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BarcodeWidget(
                    barcode: Barcode.qrCode(
                      errorCorrectLevel: BarcodeQRCorrectionLevel.medium,
                    ),
                    data: tag.url,
                    width: 220,
                    height: 220,
                    drawText: false,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.pet.name,
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    tr('Si me encontraste, escaneame'),
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: tag.lost ? theme.colorScheme.errorContainer : null,
          child: SwitchListTile(
            secondary: Icon(
              tag.lost ? Icons.warning_amber_rounded : Icons.pets,
              color: tag.lost ? theme.colorScheme.error : null,
            ),
            title: Text(tr('Se perdió')),
            subtitle: Text(tag.lost
                ? tr('La página del QR dice que está perdida y que la están buscando.')
                : tr('Si se pierde, activalo: la página del QR lo dice bien grande.')),
            value: tag.lost,
            onChanged: _busy
                ? null
                : (on) => _run(() => widget.tags.setLost(widget.pet, on)),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: const Icon(Icons.print_outlined),
          label: Text(tr('Imprimir o guardar en PDF')),
          onPressed: _busy ? null : _printPdf,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.image_outlined),
          label: Text(tr('Compartir el QR como imagen')),
          onPressed: _busy ? null : _shareImage,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.storefront_outlined),
          label: Text(tr('Pedir la chapita grabada a {shop}',
              {'shop': ShopSettings.instance.name})),
          onPressed: _orderEngraved,
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.open_in_new),
          label: Text(tr('Ver la página del QR')),
          onPressed: () => launchUrl(
            Uri.parse(tag.url),
            mode: LaunchMode.externalApplication,
          ),
        ),
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(tag.contactName.isEmpty ? tag.contactPhone : tag.contactName),
          subtitle: Text(tag.message.isEmpty
              ? '+${tag.contactPhone}'
              : '+${tag.contactPhone} · ${tag.message}'),
          trailing: IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: tr('Editar datos'),
            onPressed: _busy ? null : widget.onEdit,
          ),
        ),
        Text(
          tr('Si cambiás la foto o el nombre de {pet}, tocá el lápiz y Guardar '
              'para actualizar la página. El QR no cambia.', {'pet': widget.pet.name}),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.delete_outline),
          label: Text(tr('Borrar chapita')),
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          onPressed: _busy ? null : _delete,
        ),
      ],
    );
  }
}
