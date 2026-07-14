import 'package:flutter/material.dart';

enum OsintThemeMode { dark, light }

class OsintPalette {
  const OsintPalette({
    required this.accent,
    required this.cloud,
    required this.text,
    required this.muted,
    required this.line,
    required this.warn,
    required this.bg,
    required this.surface,
    required this.ok,
  });

  final Color accent;
  final Color cloud;
  final Color text;
  final Color muted;
  final Color line;
  final Color warn;
  final Color bg;
  final Color surface;
  final Color ok;

  static const dark = OsintPalette(
    accent: Color(0xFF22D3EE),
    cloud: Color(0xFFE0A25C),
    text: Color(0xFFE2E8F0),
    muted: Color(0xFF64748B),
    line: Color(0xFF334155),
    warn: Color(0xFFF87171),
    bg: Color(0xFF0B1220),
    surface: Color(0xFF111B2E),
    ok: Color(0xFF4ADE80),
  );

  static const light = OsintPalette(
    accent: Color(0xFF0E7490),
    cloud: Color(0xFFBD6A13),
    text: Color(0xFF0D0D0D),
    muted: Color(0xFF64748B),
    line: Color(0xFFCBD5E1),
    warn: Color(0xFFDC2626),
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFF1F5F9),
    ok: Color(0xFF16A34A),
  );

  static OsintPalette of(OsintThemeMode mode) =>
      mode == OsintThemeMode.light ? light : dark;
}

const List<String> kMonoFallback = <String>[
  'JetBrains Mono',
  'SF Mono',
  'Menlo',
  'Roboto Mono',
  'DejaVu Sans Mono',
  'monospace',
];

const String kMonoFamily = 'monospace';

TextStyle mono({
  required Color color,
  double size = 13,
  FontWeight weight = FontWeight.w400,
  double height = 1.4,
  double letterSpacing = 0.2,
}) {
  return TextStyle(
    fontFamily: kMonoFamily,
    fontFamilyFallback: kMonoFallback,
    color: color,
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: letterSpacing,
  );
}

const String kAsciiBanner = r'''
 ██████╗ ███████╗██╗███╗   ██╗████████╗
██╔═══██╗██╔════╝██║████╗  ██║╚══██╔══╝
██║   ██║███████╗██║██╔██╗ ██║   ██║
██║   ██║╚════██║██║██║╚██╗██║   ██║
╚██████╔╝███████║██║██║ ╚████║   ██║
 ╚═════╝ ╚══════╝╚═╝╚═╝  ╚═══╝   ██║   ''';

const List<String> kSpinnerFrames = <String>[
  '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏',
];

const List<String> kSpinnerVerbs = <String>[
  'Investigating', 'Correlating', 'Triangulating', 'Cross-referencing',
  'Enumerating', 'Scanning feeds', 'Pivoting', 'Corroborating',
  'Aggregating', 'Sifting', 'Ranking headlines', 'Fusing sources',
  'Deconflicting', 'Geolocating signal', 'Parsing wire copy', 'Reasoning',
];

ThemeData buildFlutterTheme(OsintThemeMode mode) {
  final p = OsintPalette.of(mode);
  final brightness =
      mode == OsintThemeMode.light ? Brightness.light : Brightness.dark;
  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: p.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: brightness,
    ).copyWith(surface: p.bg, primary: p.accent),
    fontFamily: kMonoFamily,
    fontFamilyFallback: kMonoFallback,
    useMaterial3: true,
  );
}
