import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Cash-drawer bridge — opens the drawer through the native channel
/// (vendor Android intent for built-in POS drawers, or an ESC/POS pulse over a
/// network/USB receipt printer). Mirrors the React hardwareBridge.
/// No-ops on web/iOS.
class CashDrawer {
  static const _ch = MethodChannel('vido/cashdrawer');
  static bool get _native => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// mode: 'android_intent' (built-in drawer) | 'network_escpos' (printer IP).
  static Future<Map<String, dynamic>> open({
    String mode = 'android_intent',
    String? printerHost,
    int printerPort = 9100,
  }) async {
    if (!_native) return {'ok': false, 'skipped': true};
    try {
      final r = await _ch.invokeMethod('openCashDrawer', {
        'mode': mode,
        'printerHost': printerHost ?? '',
        'printerPort': printerPort,
      });
      return Map<String, dynamic>.from(r as Map);
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Cash drawer error');
    } on MissingPluginException {
      return {'ok': false, 'skipped': true};
    }
  }

  static Future<List<Map<String, dynamic>>> listUsb() async {
    if (!_native) return [];
    try {
      final r = await _ch.invokeMethod('listUsbDevices');
      return ((Map<String, dynamic>.from(r as Map)['devices'] ?? []) as List)
          .map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) { return []; }
  }
}
