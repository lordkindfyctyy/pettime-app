import 'package:flutter/material.dart';

/// Colors of the logo: the red cross, the orange cat and a teal to contrast.
class Brand {
  static const red = Color(0xFFE53935);
  static const orange = Color(0xFFFF8F00);
  static const teal = Color(0xFF00897B);
  static const cream = Color(0xFFFFF7F2);
  static const pink = Color(0xFFFFCDD2);
}

ThemeData petTimeTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.red,
    primary: Brand.red,
    secondary: Brand.orange,
    tertiary: Brand.teal,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Brand.cream,
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.red,
      foregroundColor: Colors.white,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Brand.orange,
      foregroundColor: Colors.white,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Brand.pink,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? Brand.red
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    listTileTheme: const ListTileThemeData(iconColor: Brand.teal),
    dividerTheme: DividerThemeData(color: Brand.red.withValues(alpha: 0.15)),
  );
}

/// Title of a section with its icon and color ("Medicación", "Turnos"…).
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.text,
    required this.icon,
    required this.color,
  });

  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}
