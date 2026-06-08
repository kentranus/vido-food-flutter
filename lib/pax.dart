import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// PAX PosLink card-terminal bridge — mirrors the React paxBridge.
/// On Android it drives the real PAX terminal over TCP via the native
/// MethodChannel (MainActivity → PosLink SDK). Off-terminal (web/iOS, or no IP
/// configured) it falls back to a clearly-flagged simulated approval so the POS
/// is still usable for testing without hardware.
class PaxResult {
  final bool approved;
  final String authCode, cardLast4, cardType, message, refNum;
  final double totalCharged;
  final bool simulated;
  PaxResult({
    required this.approved,
    this.authCode = '',
    this.cardLast4 = '',
    this.cardType = '',
    this.message = '',
    this.refNum = '',
    this.totalCharged = 0,
    this.simulated = false,
  });
}

class PaxException implements Exception {
  final String message;
  PaxException(this.message);
  @override
  String toString() => message;
}

class Pax {
  static const _ch = MethodChannel('vido/pax');
  static bool get _native => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Run a CREDIT SALE. Throws [PaxException] on terminal error / decline-as-error;
  /// returns a [PaxResult] (approved may be false for a normal decline).
  static Future<PaxResult> sale({
    required double amount,
    String? host,
    int port = 10009,
    int timeout = 60000,
    String? refNum,
    String tipAmount = '',
  }) async {
    final ref = refNum ?? DateTime.now().millisecondsSinceEpoch.toString();
    // Off-terminal demo path (no native channel or no IP yet).
    if (!_native || (host == null || host.trim().isEmpty)) {
      return _simulate(amount, ref);
    }
    try {
      final raw = await _ch.invokeMethod('sale', {
        'amount': amount,
        'connectionMode': 'tcp',
        'host': host.trim(),
        'port': port,
        'timeout': timeout,
        'refNum': ref,
        'tipAmount': tipAmount,
        'extData': '',
      });
      final r = Map<String, dynamic>.from(raw as Map);
      if (r['ok'] != true) {
        throw PaxException((r['processMessage'] ?? 'Card terminal error').toString());
      }
      final approved = r['approved'] == true;
      final masked = (r['maskedCard'] ?? '').toString();
      final last4 = RegExp(r'(\d{4})\s*$').firstMatch(masked)?.group(1) ?? '';
      final cents = int.tryParse('${r['approvedAmount'] ?? r['requestedAmount'] ?? ''}') ?? (amount * 100).round();
      return PaxResult(
        approved: approved,
        authCode: (r['authCode'] ?? '').toString(),
        cardLast4: last4,
        cardType: (r['cardType'] ?? '').toString(),
        message: (r['resultText'] ?? r['message'] ?? '').toString(),
        refNum: (r['refNum'] ?? ref).toString(),
        totalCharged: cents / 100,
        simulated: false,
      );
    } on PlatformException catch (e) {
      throw PaxException(e.message ?? 'Card terminal error');
    } on MissingPluginException {
      // Native channel not present (older build) → simulate so flow continues.
      return _simulate(amount, ref);
    }
  }

  static Future<PaxResult> _simulate(double amount, String ref) async {
    await Future.delayed(const Duration(milliseconds: 900));
    const types = ['Visa', 'Mastercard', 'Amex', 'Discover'];
    final t = types[DateTime.now().second % types.length];
    final last4 = (1000 + (DateTime.now().millisecond % 9000)).toString();
    return PaxResult(
      approved: true,
      authCode: 'TEST${100000 + (DateTime.now().millisecond % 900000)}',
      cardLast4: last4,
      cardType: t,
      message: 'Approved (test)',
      refNum: ref,
      totalCharged: amount,
      simulated: true,
    );
  }
}
