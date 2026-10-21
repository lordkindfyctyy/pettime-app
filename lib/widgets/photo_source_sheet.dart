import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_lang.dart';

/// What the user chose in [showPhotoSourceSheet].
sealed class PhotoChoice {
  const PhotoChoice();
}

class PickPhoto extends PhotoChoice {
  const PickPhoto(this.source);
  final ImageSource source;
}

class RemovePhoto extends PhotoChoice {
  const RemovePhoto();
}

/// Bottom sheet to pick a photo from the gallery or camera, or remove it.
/// Returns null when dismissed.
Future<PhotoChoice?> showPhotoSourceSheet(
  BuildContext context, {
  required bool hasPhoto,
}) {
  return showModalBottomSheet<PhotoChoice>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(tr('Elegir de la galería')),
            onTap: () => Navigator.pop(ctx, const PickPhoto(ImageSource.gallery)),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(tr('Sacar una foto')),
            onTap: () => Navigator.pop(ctx, const PickPhoto(ImageSource.camera)),
          ),
          if (hasPhoto)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(tr('Quitar foto')),
              onTap: () => Navigator.pop(ctx, const RemovePhoto()),
            ),
        ],
      ),
    ),
  );
}
