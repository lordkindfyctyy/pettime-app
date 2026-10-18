import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/pet.dart';

/// Backup of everything in a single .zip: `pettime.json` with the pets
/// (medications, doses given, appointments, health booklet) and the photos
/// under `fotos/`. Photo paths inside the JSON are stored relative to the zip,
/// since the app's folder is different on another phone.
class BackupService {
  BackupService._();

  static const dataFile = 'pettime.json';
  static const photosFolder = 'fotos';
  static const format = 1;

  static String _photoEntry(String path) =>
      '$photosFolder/${path.split(RegExp(r'[\\/]')).last}';

  /// Builds the zip. Photos whose file no longer exists are left out.
  static Uint8List buildZip(List<Pet> pets, {DateTime? now}) {
    final archive = Archive();
    final added = <String>{};

    String? pack(String? path) {
      if (path == null) return null;
      final file = File(path);
      if (!file.existsSync()) return null;
      final entry = _photoEntry(path);
      if (added.add(entry)) {
        archive.addFile(ArchiveFile.bytes(entry, file.readAsBytesSync()));
      }
      return entry;
    }

    final packed = [
      for (final pet in pets)
        pet.copyWith(
          photoPath: pack(pet.photoPath),
          clearPhoto: pack(pet.photoPath) == null,
          medications: [
            for (final m in pet.medications)
              m.copyWith(
                photoPath: pack(m.photoPath),
                clearPhoto: pack(m.photoPath) == null,
              ),
          ],
        ),
    ];
    final json = jsonEncode({
      'app': 'PetTime',
      'format': format,
      'createdAt': (now ?? DateTime.now()).toIso8601String(),
      'pets': [for (final p in packed) p.toJson()],
    });
    archive.addFile(ArchiveFile.bytes(dataFile, utf8.encode(json)));
    return ZipEncoder().encodeBytes(archive);
  }

  /// Reads a backup made by [buildZip]: writes its photos into [photosDir]
  /// and returns the pets pointing to them. Throws a [FormatException] when
  /// the file is not a PetTime backup.
  static List<Pet> readZip(Uint8List bytes, Directory photosDir) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('El archivo no es una copia de PetTime.');
    }
    final data = archive.findFile(dataFile);
    if (data == null) {
      throw const FormatException('El archivo no es una copia de PetTime.');
    }
    final json = jsonDecode(utf8.decode(data.content)) as Map<String, dynamic>;
    if (json['app'] != 'PetTime' || json['pets'] is! List) {
      throw const FormatException('El archivo no es una copia de PetTime.');
    }

    photosDir.createSync(recursive: true);
    final restored = <String, String>{};
    String? unpack(String? entry) {
      if (entry == null) return null;
      if (restored.containsKey(entry)) return restored[entry];
      final file = archive.findFile(entry);
      if (file == null) return null;
      final target = '${photosDir.path}/${entry.split('/').last}';
      File(target).writeAsBytesSync(file.content);
      return restored[entry] = target;
    }

    return [
      for (final raw in json['pets'] as List)
        () {
          final pet = Pet.fromJson(raw as Map<String, dynamic>);
          final photo = unpack(pet.photoPath);
          return pet.copyWith(
            photoPath: photo,
            clearPhoto: photo == null,
            medications: [
              for (final m in pet.medications)
                () {
                  final p = unpack(m.photoPath);
                  return m.copyWith(photoPath: p, clearPhoto: p == null);
                }(),
            ],
          );
        }(),
    ];
  }

  /// Name of the backup file for [now], e.g. `PetTime-copia-2026-10-17.zip`.
  static String fileName(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'PetTime-copia-${now.year}-${two(now.month)}-${two(now.day)}.zip';
  }
}
