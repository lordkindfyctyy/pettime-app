import 'package:flutter/material.dart';

void main() => runApp(const PetTimeApp());

class PetTimeApp extends StatelessWidget {
  const PetTimeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PetTime',
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(child: Text('PetTime')),
      ),
    );
  }
}
