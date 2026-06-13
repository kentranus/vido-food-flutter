import 'package:flutter/material.dart';

/// Faithful port of the React app's theme.js design tokens.
/// Dark is the default (matches the original POS). Light variant included.
/// Use `PT.c` for the active palette; toggle with `PT.setMode`.
class PosColors {
  final Color bg, panel, card, cardHover, border, text, textMute, textDim;
  final Color primary, primaryD, primaryA, accent, yellow, red, redA, blue, cyan, cyanD, green;
  final Color shadow, overlay;
  const PosColors({
    required this.bg, required this.panel, required this.card, required this.cardHover,
    required this.border, required this.text, required this.textMute, required this.textDim,
    required this.primary, required this.primaryD, required this.primaryA, required this.accent,
    required this.yellow, required this.red, required this.redA, required this.blue,
    required this.cyan, required this.cyanD, required this.green, required this.shadow, required this.overlay,
  });

  /// Brand gradient (linear-gradient(135deg, #FFE066, #FFCC00 45%, #FF9500)).
  LinearGradient get primaryG => const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFFFFE066), Color(0xFFFFCC00), Color(0xFFFF9500)],
        stops: [0.0, 0.45, 1.0],
      );
}

const PosColors kDark = PosColors(
  bg: Color(0xFF0F1419),
  panel: Color(0xFF1A1F26),
  card: Color(0xFF252A33),
  cardHover: Color(0xFF2D333D),
  border: Color(0xFF374151),
  text: Color(0xFFFFFFFF),
  textMute: Color(0xFF9CA3AF),
  textDim: Color(0xFF6B7280),
  primary: Color(0xFFFFCC00),
  primaryD: Color(0xFFE0B000),
  primaryA: Color(0x2EFFCC00), // rgba(255,204,0,0.18)
  accent: Color(0xFFFFE066),
  yellow: Color(0xFFFFCC00), // brand — đồng bộ #FFCC00 (chart dùng amber riêng)
  red: Color(0xFFEF4444),
  redA: Color(0x26EF4444), // rgba(239,68,68,0.15)
  blue: Color(0xFF3B82F6),
  cyan: Color(0xFF2DD4BF),
  cyanD: Color(0xFF14A89A),
  green: Color(0xFF4ADE80),
  shadow: Color(0x66000000), // rgba(0,0,0,0.4)
  overlay: Color(0xB3000000), // rgba(0,0,0,0.7)
);

const PosColors kLight = PosColors(
  bg: Color(0xFFF5F5F5),
  panel: Color(0xFFFFFFFF),
  card: Color(0xFFF3F4F6),
  cardHover: Color(0xFFE5E7EB),
  border: Color(0xFFD1D5DB),
  text: Color(0xFF111827),
  textMute: Color(0xFF4B5563),
  textDim: Color(0xFF9CA3AF),
  primary: Color(0xFFFFCC00),
  primaryD: Color(0xFFE0B000),
  primaryA: Color(0x33FFCC00),
  accent: Color(0xFFFFE066),
  yellow: Color(0xFFEAB308),
  red: Color(0xFFDC2626),
  redA: Color(0x1ADC2626),
  blue: Color(0xFF2563EB),
  cyan: Color(0xFF0891B2),
  cyanD: Color(0xFF0E7490),
  green: Color(0xFF16A34A),
  shadow: Color(0x1A000000),
  overlay: Color(0x80000000),
);

/// Active theme holder (dark default), mirrors getInitialTheme()='dark'.
class PT {
  static final ValueNotifier<bool> isDark = ValueNotifier(true);
  static PosColors get c => isDark.value ? kDark : kLight;
  static void setMode(bool dark) => isDark.value = dark;
  static void toggle() => isDark.value = !isDark.value;
}
