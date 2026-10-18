import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/medication.dart';
import '../models/pet.dart';
import '../models/vet_visit.dart';
import '../models/weight_entry.dart';
import 'shop_settings.dart';

/// Fonts and logo of the report. Roboto is embedded because the PDF's
/// built-in fonts can't write every Spanish character.
class VetReportAssets {
  VetReportAssets({required this.regular, required this.bold, this.logo});

  final pw.Font regular;
  final pw.Font bold;
  final pw.MemoryImage? logo;

  static Future<VetReportAssets> load() async {
    Future<ByteData> asset(String name) => rootBundle.load('assets/$name');
    return VetReportAssets(
      regular: pw.Font.ttf(await asset('fonts/Roboto-Regular.ttf')),
      bold: pw.Font.ttf(await asset('fonts/Roboto-Bold.ttf')),
      logo: pw.MemoryImage(
        (await asset('icon/icon.png')).buffer.asUint8List(),
      ),
    );
  }
}

/// A PDF with everything the vet wants to know about a pet: its data, the
/// medication it takes and took, the health booklet, the weight and the past
/// visits.
class VetReport {
  VetReport._();

  static const _red = PdfColor.fromInt(0xFFE53935);
  static const _teal = PdfColor.fromInt(0xFF00897B);
  static const _grey = PdfColor.fromInt(0xFF616161);
  static const _light = PdfColor.fromInt(0xFFFFF7F2);

  static final _day = DateFormat('dd/MM/yyyy', 'es');
  static final _dayTime = DateFormat('dd/MM/yyyy HH:mm', 'es');

  static String fileName(Pet pet, DateTime now) =>
      'Ficha de ${pet.name} ${DateFormat('yyyy-MM-dd').format(now)}.pdf';

  /// Medications still going on at [now], and the ones that already ended.
  static (List<Medication>, List<Medication>) splitMedications(
    Pet pet,
    DateTime now,
  ) {
    bool active(Medication m) => m.endsAt == null || m.endsAt!.isAfter(now);
    final current = pet.medications.where(active).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final past = pet.medications.where((m) => !active(m)).toList()
      ..sort((a, b) => b.startsAt.compareTo(a.startsAt));
    return (current, past);
  }

  /// "+0,5 kg", "−1,2 kg", "=" compared with the previous weighing.
  static String weightChange(double kg, double? previous) {
    if (previous == null) return '';
    final diff = ((kg - previous) * 100).round() / 100;
    if (diff == 0) return 'igual';
    final text = formatKg(diff.abs());
    return diff > 0 ? '+$text' : '−$text';
  }

  static Future<Uint8List> build(
    Pet pet, {
    required VetReportAssets assets,
    required DateTime now,
    String shopName = ShopSettings.defaultName,
  }) async {
    final photo = await _photo(pet.photoPath);
    final (currentMeds, pastMeds) = splitMedications(pet, now);
    final records = [...pet.records]
      ..sort((a, b) => b.appliedOn.compareTo(a.appliedOn));
    final weights = pet.weights.reversed.take(12).toList();
    final vetVisits = pet.visits
        .where((v) => v.kind == AppointmentKind.vet)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final doc = pw.Document(
      title: 'Ficha de ${pet.name}',
      author: 'PetTime',
      creator: 'PetTime',
    );
    doc.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
        theme: pw.ThemeData.withFont(base: assets.regular, bold: assets.bold),
      ),
      header: (context) => context.pageNumber == 1
          ? _header(pet, assets.logo, now)
          : pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              child: pw.Text(
                'Ficha de ${pet.name} (continuación)',
                style: const pw.TextStyle(color: _grey, fontSize: 9),
              ),
            ),
      footer: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 12),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generada con PetTime · $shopName',
              style: const pw.TextStyle(color: _grey, fontSize: 8),
            ),
            pw.Text(
              'Página ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(color: _grey, fontSize: 8),
            ),
          ],
        ),
      ),
      build: (context) => [
        _petData(pet, photo, now),
        _section('Medicación actual'),
        if (currentMeds.isEmpty)
          _empty('No está tomando medicación.')
        else
          _table(
            ['Medicamento', 'Dosis', 'Frecuencia', 'Desde', 'Hasta', 'Última toma'],
            [
              for (final m in currentMeds)
                [
                  _withNotes(m.name, m.notes),
                  m.dose,
                  m.intervalLabel,
                  _day.format(m.startsAt),
                  m.endsAt == null ? 'Sin fecha' : _day.format(m.endsAt!),
                  m.lastGiven == null ? '—' : _dayTime.format(m.lastGiven!),
                ],
            ],
          ),
        if (pastMeds.isNotEmpty) ...[
          _section('Medicación anterior'),
          _table(
            ['Medicamento', 'Dosis', 'Frecuencia', 'Desde', 'Hasta', 'Tomas dadas'],
            [
              for (final m in pastMeds)
                [
                  _withNotes(m.name, m.notes),
                  m.dose,
                  m.intervalLabel,
                  _day.format(m.startsAt),
                  _day.format(m.endsAt!),
                  '${m.givenDoses.length}',
                ],
            ],
          ),
        ],
        _section('Vacunas y antiparasitarios'),
        if (records.isEmpty)
          _empty('No hay vacunas ni antiparasitarios cargados.')
        else
          _table(
            ['Tipo', 'Nombre', 'Aplicada', 'Próxima', 'Notas'],
            [
              for (final r in records)
                [
                  r.kind.label,
                  r.name,
                  _day.format(r.appliedOn),
                  r.nextDue == null ? '—' : _day.format(r.nextDue!),
                  r.notes,
                ],
            ],
          ),
        if (weights.isNotEmpty) ...[
          _section('Peso'),
          _table(
            ['Fecha', 'Peso', 'Cambio'],
            [
              for (final (i, w) in weights.indexed)
                [
                  _day.format(w.date),
                  formatKg(w.kg),
                  weightChange(
                    w.kg,
                    i + 1 < weights.length ? weights[i + 1].kg : null,
                  ),
                ],
            ],
          ),
        ],
        if (vetVisits.isNotEmpty) ...[
          _section('Turnos en la veterinaria'),
          _table(
            ['Fecha', 'Veterinaria', 'Motivo', 'Notas'],
            [
              for (final v in vetVisits)
                [
                  _dayTime.format(v.date) +
                      (v.date.isAfter(now) ? ' (próximo)' : ''),
                  v.clinic,
                  v.reason,
                  v.notes,
                ],
            ],
          ),
        ],
      ],
    ));
    return doc.save();
  }

  static Future<pw.MemoryImage?> _photo(String? path) async {
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    return pw.MemoryImage(await file.readAsBytes());
  }

  static pw.Widget _header(Pet pet, pw.MemoryImage? logo, DateTime now) =>
      pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 10),
        margin: const pw.EdgeInsets.only(bottom: 14),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _red, width: 2)),
        ),
        child: pw.Row(
          children: [
            if (logo != null) ...[
              pw.Image(logo, width: 40, height: 40),
              pw.SizedBox(width: 12),
            ],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Ficha de ${pet.name}',
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: _red,
                    ),
                  ),
                  pw.Text(
                    'Para el veterinario · ${DateFormat.yMMMMd('es').format(now)}',
                    style: const pw.TextStyle(color: _grey, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  static pw.Widget _petData(Pet pet, pw.MemoryImage? photo, DateTime now) {
    final weight = pet.currentWeight;
    final birth = pet.birthDate;
    final rows = [
      ('Especie', pet.species),
      ('Raza', pet.breed),
      (
        'Nacimiento',
        birth == null ? '' : '${_day.format(birth)} (${pet.ageLabel(now)})',
      ),
      (
        'Peso actual',
        weight == null
            ? ''
            : '${formatKg(weight.kg)} (el ${_day.format(weight.date)})',
      ),
      ('Alimento', pet.food),
      ('Notas', pet.notes),
    ].where((r) => r.$2.trim().isNotEmpty);

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (photo != null) ...[
          pw.ClipRRect(
            horizontalRadius: 8,
            verticalRadius: 8,
            child: pw.Image(photo, width: 96, height: 96, fit: pw.BoxFit.cover),
          ),
          pw.SizedBox(width: 16),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final (label, value) in rows)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.SizedBox(
                        width: 80,
                        child: pw.Text(
                          label,
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                      pw.Expanded(child: pw.Text(value)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _section(String title) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 18, bottom: 6),
        child: pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            color: _teal,
          ),
        ),
      );

  static pw.Widget _empty(String text) =>
      pw.Text(text, style: const pw.TextStyle(color: _grey));

  static String _withNotes(String name, String notes) =>
      notes.trim().isEmpty ? name : '$name\n${notes.trim()}';

  static pw.Widget _table(List<String> headers, List<List<String>> rows) =>
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: [
          for (final r in rows) [for (final c in r) c.isEmpty ? '—' : c],
        ],
        headerStyle: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
          fontSize: 9,
        ),
        headerDecoration: const pw.BoxDecoration(color: _teal),
        headerAlignment: pw.Alignment.centerLeft,
        cellStyle: const pw.TextStyle(fontSize: 9),
        oddRowDecoration: const pw.BoxDecoration(color: _light),
        border: const pw.TableBorder(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
          horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      );
}
