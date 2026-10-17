import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Picks a pet photo and keeps a resized copy inside the app's own storage, so
/// it survives the gallery file being moved or deleted.
class PhotoService {
  PhotoService._();
  static final instance = PhotoService._();

  final _picker = ImagePicker();

  /// Returns the path of the stored copy, or null if the user cancelled.
  Future<String?> pick(ImageSource source, String petId) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked == null) return null;

    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/pet_photos');
    await dir.create(recursive: true);
    // A new name each time, so the image cache never shows the old photo.
    final target = '${dir.path}/${petId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(picked.path).copy(target);
    return target;
  }

  Future<void> delete(String? path) async {
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
