import 'dart:io';

import 'package:flutter/material.dart';

import '../models/pet.dart';

/// The pet's photo, or its initial when it has none (or the file is gone).
class PetAvatar extends StatelessWidget {
  const PetAvatar({super.key, required this.pet, this.radius = 20});

  final Pet pet;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final path = pet.photoPath;
    final hasPhoto = path != null && File(path).existsSync();
    return CircleAvatar(
      radius: radius,
      backgroundImage: hasPhoto ? FileImage(File(path)) : null,
      child: hasPhoto
          ? null
          : Text(
              pet.name.isEmpty ? '?' : pet.name.characters.first.toUpperCase(),
              style: TextStyle(fontSize: radius * 0.9),
            ),
    );
  }
}
