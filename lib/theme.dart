import 'package:flutter/material.dart';

/// Vido Food brand palette (mirrors the React app theme).
class C {
  static const brand = Color(0xFFFFCC00);
  static const brandDark = Color(0xFFE0B000);
  static const ink = Color(0xFF14181F);
  static const bg = Color(0xFFF6F7F9);
  static const panel = Color(0xFFFFFFFF);
  static const border = Color(0xFFE5E7EB);
  static const textMute = Color(0xFF6B7280);
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFDC2626);
  static const redA = Color(0xFFFEF2F2);
  static const online = Color(0xFFFF6A00);
  static const kiosk = Color(0xFF8B5CF6);
  static const pos = Color(0xFF64748B);
}

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: C.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: C.brand, primary: C.brand),
    fontFamily: 'Roboto',
  );
}

String money(num v) => '\$${v.toStringAsFixed(2)}';

({String label, Color color}) sourceMeta(String source) {
  final s = source.toLowerCase();
  if (s.contains('online') || s.contains('web')) return (label: 'ONLINE', color: C.online);
  if (s.contains('kiosk')) return (label: 'KIOSK', color: C.kiosk);
  return (label: 'POS', color: C.pos);
}

/// NEW / preparing / ready column for an order (kiosk pre-paid → preparing).
String? columnOf(String status, String source) {
  final src = source.toLowerCase();
  if (status == 'ready') return 'ready';
  if (status == 'accepted' || status == 'preparing') return 'preparing';
  if (status == 'pending_accept' || status == 'new') return src.contains('kiosk') ? 'preparing' : 'new';
  return null;
}
