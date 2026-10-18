import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pettime_app/models/health_record.dart';
import 'package:pettime_app/models/medication.dart';
import 'package:pettime_app/models/pet.dart';
import 'package:pettime_app/models/vet_visit.dart';
import 'package:pettime_app/models/weight_entry.dart';
import 'package:pettime_app/services/vet_report.dart';

Pet pancho() => Pet(
      id: 'p',
      name: 'Pancho',
      species: 'Perro',
      breed: 'Labrador',
      birthDate: DateTime(2020, 3, 12),
      food: 'Royal Canin Fit, 300 g por día',
      notes: 'Alérgico al pollo. Se pone nervioso en la camilla.',
      medications: [
        Medication(
          id: 'm1',
          name: 'Amoxicilina',
          dose: '1 comprimido de 500 mg',
          everyMinutes: 8 * 60,
          startsAt: DateTime(2026, 10, 15, 8),
          endsAt: DateTime(2026, 10, 22, 8),
          givenDoses: [DateTime(2026, 10, 18, 8, 5)],
        ),
        Medication(
          id: 'm2',
          name: 'Meloxicam',
          dose: '0,5 ml',
          everyMinutes: 24 * 60,
          startsAt: DateTime(2026, 8, 1, 9),
          endsAt: DateTime(2026, 8, 6, 9),
          notes: 'Con comida',
          givenDoses: [DateTime(2026, 8, 1, 9), DateTime(2026, 8, 2, 9)],
        ),
      ],
      records: [
        HealthRecord(
          id: 'r1',
          kind: HealthKind.vaccine,
          name: 'Antirrábica',
          appliedOn: DateTime(2026, 3, 10),
          nextDue: DateTime(2027, 3, 10),
        ),
        HealthRecord(
          id: 'r2',
          kind: HealthKind.fleaTick,
          name: 'Pipeta',
          appliedOn: DateTime(2026, 10, 1),
          nextDue: DateTime(2026, 11, 1),
          notes: 'Frontline',
        ),
      ],
      weights: [
        WeightEntry(id: 'w1', date: DateTime(2026, 6, 1), kg: 31),
        WeightEntry(id: 'w2', date: DateTime(2026, 8, 1), kg: 32.5),
        WeightEntry(id: 'w3', date: DateTime(2026, 10, 1), kg: 32),
      ],
      visits: [
        VetVisit(
          id: 'v1',
          clinic: 'Veterinaria San Martín',
          date: DateTime(2026, 10, 15, 17, 30),
          reason: 'Otitis',
          notes: 'Control en 7 días',
        ),
        VetVisit(
          id: 'v2',
          clinic: 'Peluquería Guau',
          kind: AppointmentKind.grooming,
          date: DateTime(2026, 9, 1, 10),
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('es'));

  final now = DateTime(2026, 10, 18, 10);

  test('separa la medicación actual de la anterior', () {
    final (current, past) = VetReport.splitMedications(pancho(), now);
    expect(current.map((m) => m.name), ['Amoxicilina']);
    expect(past.map((m) => m.name), ['Meloxicam']);
  });

  test('cambio de peso respecto del pesaje anterior', () {
    expect(VetReport.weightChange(32.5, 31), '+1,5 kg');
    expect(VetReport.weightChange(32, 32.5), '−0,5 kg');
    expect(VetReport.weightChange(32, 32), 'igual');
    expect(VetReport.weightChange(31, null), '');
  });

  test('arma el PDF con todos los datos, y también sin datos', () async {
    final assets = await VetReportAssets.load();
    final bytes = await VetReport.build(pancho(), assets: assets, now: now);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(VetReport.fileName(pancho(), now), 'Ficha de Pancho 2026-10-18.pdf');

    final empty = await VetReport.build(
      Pet(id: 'x', name: 'Michi'),
      assets: assets,
      now: now,
    );
    expect(String.fromCharCodes(empty.take(5)), '%PDF-');

    // PDF_OUT=ruta para mirar el resultado a mano.
    final out = Platform.environment['PDF_OUT'];
    if (out != null) await File(out).writeAsBytes(bytes);
  });
}
