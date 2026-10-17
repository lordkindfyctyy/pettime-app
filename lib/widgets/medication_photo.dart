import 'dart:io';

import 'package:flutter/material.dart';

/// Square photo of a medicine, or a pill icon when there is none (or the file
/// is gone).
class MedicationPhoto extends StatelessWidget {
  const MedicationPhoto({super.key, required this.path, this.size = 48});

  final String? path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final photo = path;
    final hasPhoto = photo != null && File(photo).existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 6),
      child: SizedBox(
        width: size,
        height: size,
        child: hasPhoto
            ? Image.file(File(photo), fit: BoxFit.cover)
            : ColoredBox(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Icon(
                  Icons.medication_outlined,
                  size: size * 0.55,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
      ),
    );
  }
}
