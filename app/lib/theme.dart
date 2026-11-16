import 'package:material_ui/material_ui.dart';

/// Colours taken from the Longview design.
class C {
  static const bg = Color(0xFFF4F3EE);
  static const ink = Color(0xFF16181D);
  static const side = Color(0xFF16181D);
  static const sideText = Color(0xFFC9CBD1);
  static const sideOn = Color(0xFF2C3039);
  static const card = Colors.white;
  static const border = Color(0xFFE3E1D9);
  static const rule = Color(0xFFEFEDE6);
  static const field = Color(0xFFCFCCC2);
  static const label = Color(0xFF5B5F66);
  static const muted = Color(0xFF4A4E55);
  static const subtle = Color(0xFFF8F7F3);
  static const link = Color(0xFF2F5BB7);
  static const green = Color(0xFF1E6B4F);
  static const greenBg = Color(0xFFE3F1EA);
  static const orange = Color(0xFF9A4507);
  static const orangeBg = Color(0xFFFBEBDD);
  static const orangeSoft = Color(0xFFFBF3EA);
  static const orangeInk = Color(0xFF4A2B0E);
  static const accent = Color(0xFFB4530A);
  static const accentLight = Color(0xFFE2A06A);
  static const blue = Color(0xFF24489A);
  static const blueBg = Color(0xFFE5ECFA);
  static const grey = Color(0xFF4A4E55);
  static const greyBg = Color(0xFFECEBE6);
  static const future = Color(0xFFD9D6CC);
}

const _display = 'Space Grotesk';

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: C.ink, surface: C.bg, primary: C.ink),
    scaffoldBackgroundColor: C.bg,
    fontFamily: 'Inter',
    fontFamilyFallback: const ['Roboto', 'Helvetica', 'Arial', 'sans-serif'],
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineMedium: const TextStyle(fontFamily: _display, fontWeight: FontWeight.w700, fontSize: 34, color: C.ink),
      titleLarge: const TextStyle(fontFamily: _display, fontWeight: FontWeight.w700, fontSize: 20, color: C.ink),
      titleMedium: const TextStyle(fontSize: 14, color: C.ink),
      bodyLarge: const TextStyle(fontSize: 14, color: C.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.ink, foregroundColor: Colors.white, minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.ink, backgroundColor: Colors.white, minimumSize: const Size(44, 44),
        side: const BorderSide(color: C.field),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: Colors.white, isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: C.field)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: C.field)),
      labelStyle: const TextStyle(color: C.label, fontSize: 13),
    ),
    // Form fields and dropdowns read their text size from these.
    // (Material's default 16px is larger than the design's 14px inputs.)
    dropdownMenuTheme: const DropdownMenuThemeData(textStyle: TextStyle(fontSize: 14, color: C.ink)),
    dividerTheme: const DividerThemeData(color: C.rule, space: 1, thickness: 1),
  );
}

const display = _display;

/// Card/section headings (18px Space Grotesk bold).
const sectionTitle = TextStyle(fontFamily: _display, fontWeight: FontWeight.w700, fontSize: 18, color: C.ink);
