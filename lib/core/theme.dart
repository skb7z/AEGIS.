import 'package:flutter/material.dart';

extension ColorOp on Color {
  /// Same colour with the given opacity (0..1).
  Color op(double o) => withAlpha((o * 255).round().clamp(0, 255));
}

class AegisPalette {
  const AegisPalette({
    required this.id,
    required this.name,
    required this.bg,
    required this.surface,
    required this.text,
    required this.subtext,
    required this.accent,
    required this.listen,
    required this.think,
    required this.brightness,
  });

  final String id;
  final String name;
  final Color bg;
  final Color surface;
  final Color text;
  final Color subtext;
  final Color accent;
  final Color listen;
  final Color think;
  final Brightness brightness;

  bool get dark => brightness == Brightness.dark;

  static const cyber = AegisPalette(
    id: 'cyber',
    name: 'Dark Mode',
    bg: Color(0xFF05070D),
    surface: Color(0xFF0E141F),
    text: Color(0xFFE8F6FF),
    subtext: Color(0xFF8FA6B8),
    accent: Color(0xFF00E5FF),
    listen: Color(0xFF00FFA3),
    think: Color(0xFFB388FF),
    brightness: Brightness.dark,
  );

  static const chalk = AegisPalette(
    id: 'chalk',
    name: 'White Mode',
    bg: Color(0xFFF5F5F0),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF14181F),
    subtext: Color(0xFF5E6672),
    accent: Color(0xFF1565C0),
    listen: Color(0xFF00A86B),
    think: Color(0xFF7B4DFF),
    brightness: Brightness.light,
  );

  static const all = [cyber, chalk];

  static AegisPalette byId(String id) => id == 'chalk' ? chalk : cyber;

  ThemeData get theme {
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
        .copyWith(primary: accent, surface: surface);
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: accent,
        textColor: text,
        subtitleTextStyle: TextStyle(color: subtext, fontSize: 13),
      ),
      dividerColor: text.op(.08),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: TextStyle(color: text),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
