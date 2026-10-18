import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettime_app/models/health_record.dart';
import 'package:pettime_app/models/medication.dart';
import 'package:pettime_app/models/pet.dart';
import 'package:pettime_app/models/vet_visit.dart';
import 'package:pettime_app/services/backup_service.dart';
import 'package:pettime_app/services/drive_backup_service.dart';
import 'package:pettime_app/state/pets_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('pettime_backup');
  });

  tearDown(() => tmp.delete(recursive: true));

  Pet sample({String? petPhoto, String? medPhoto}) => Pet(
        id: 'p',
        name: 'Pancho',
        species: 'Perro',
        photoPath: petPhoto,
        medications: [
          Medication(
            id: 'm',
            name: 'Bicarbonato',
            everyMinutes: 60,
            startsAt: DateTime(2026, 10, 17, 8),
            photoPath: medPhoto,
            givenDoses: [DateTime(2026, 10, 17, 8, 5)],
          ),
        ],
        visits: [
          VetVisit(id: 'v', clinic: 'Vet Sur', date: DateTime(2026, 11, 1, 10)),
        ],
        records: [
          HealthRecord(
            id: 'r',
            kind: HealthKind.vaccine,
            name: 'Antirrábica',
            appliedOn: DateTime(2026, 3, 1),
            nextDue: DateTime(2027, 3, 1),
          ),
        ],
      );

  test('la copia guarda todo, con las fotos, y se restaura en otra carpeta', () {
    final petPhoto = File('${tmp.path}/origen/p_1.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    final medPhoto = File('${tmp.path}/origen/m_2.jpg')
      ..writeAsBytesSync([4, 5]);

    final zip = BackupService.buildZip(
      [sample(petPhoto: petPhoto.path, medPhoto: medPhoto.path)],
      now: DateTime(2026, 10, 17),
    );

    // El JSON no guarda rutas del celular viejo.
    final json = utf8.decode(ZipDecoder()
        .decodeBytes(zip)
        .findFile(BackupService.dataFile)!
        .content);
    expect(json, isNot(contains(tmp.path.replaceAll('\\', '\\\\'))));

    final dest = Directory('${tmp.path}/nuevo/pet_photos');
    final pets = BackupService.readZip(zip, dest);
    final pet = pets.single;
    expect(pet.name, 'Pancho');
    expect(pet.photoPath, '${dest.path}/p_1.jpg');
    expect(File(pet.photoPath!).readAsBytesSync(), [1, 2, 3]);
    final med = pet.medications.single;
    expect(File(med.photoPath!).readAsBytesSync(), [4, 5]);
    expect(med.givenDoses, [DateTime(2026, 10, 17, 8, 5)]);
    expect(pet.visits.single.clinic, 'Vet Sur');
    expect(pet.records.single.nextDue, DateTime(2027, 3, 1));
  });

  test('una foto que ya no existe no rompe la copia', () {
    final zip = BackupService.buildZip(
        [sample(petPhoto: '${tmp.path}/no_existe.jpg')]);
    final pet = BackupService.readZip(zip, Directory('${tmp.path}/d')).single;
    expect(pet.photoPath, isNull);
    expect(pet.name, 'Pancho');
  });

  test('rechaza archivos que no son una copia de PetTime', () {
    final dir = Directory('${tmp.path}/d');
    expect(() => BackupService.readZip(Uint8List.fromList([1, 2, 3]), dir),
        throwsFormatException);
    final otherZip = ZipEncoder().encodeBytes(
        Archive()..addFile(ArchiveFile.bytes('hola.txt', utf8.encode('hola'))));
    expect(() => BackupService.readZip(otherZip, dir), throwsFormatException);
  });

  test('la copia en Drive se renueva una vez por día', () {
    final now = DateTime(2026, 10, 18, 9);
    expect(DriveBackupService.isDue(null, now), isTrue);
    expect(DriveBackupService.isDue(DateTime(2026, 10, 17, 22), now), isFalse);
    expect(DriveBackupService.isDue(DateTime(2026, 10, 17, 9), now), isTrue);
  });

  test('nombre del archivo con la fecha', () {
    expect(BackupService.fileName(DateTime(2026, 3, 5)),
        'PetTime-copia-2026-03-05.zip');
  });

  test('restaurar reemplaza las mascotas y queda guardado', () async {
    final state = PetsState();
    await state.savePet(Pet(id: 'old', name: 'Luna'));
    await state.replaceAll([sample()]);
    expect(state.pets.map((p) => p.name), ['Pancho']);

    final again = PetsState();
    await again.load();
    expect(again.pets.single.records.single.name, 'Antirrábica');
  });
}