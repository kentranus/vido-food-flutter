import 'package:flutter/material.dart';

import '../ui/pos_theme.dart';
import '../ui/pos_widgets.dart';
import 'order_models.dart' show money;

/// Gift Card panel — Phase D2 (check balance) + D3 (apply FULL-COVER only).
///
/// D3 rules: Apply chỉ bật khi balance >= due (đơn được trả TRỌN bằng thẻ).
/// balance < due → "Partial gift card payment is coming soon." (D4 sẽ làm).
/// Redeem đúng `due` (không hơn balance, không hơn đơn) — backend cũng clamp +
/// idempotent theo `redeemRef`, nên retry không trừ đúp.
///
/// Mọi network call được inject để widget test chạy offline:
///   check  → POST /api/gift-cards/check   {code}
///   redeem → POST /api/gift-cards/redeem  {code, amount, orderId: redeemRef}
class GiftCardCheckPanel extends StatefulWidget {
  final Future<Map<String, dynamic>> Function(String code) check;
  final Future<Map<String, dynamic>> Function(String code, double amount, String ref)? redeem;
  final double? due;        // tổng đơn cần trả; null = chế độ chỉ-xem (D2)
  final String? redeemRef;  // id ổn định theo đơn (idempotency + refund)
  final ValueChanged<Map<String, dynamic>>? onApplied; // {code, applied, remaining}
  const GiftCardCheckPanel({super.key, required this.check, this.redeem, this.due, this.redeemRef, this.onApplied});

  @override
  State<GiftCardCheckPanel> createState() => _GiftCardCheckPanelState();
}

/// Display mask: keep prefix + last group, hide the middle (VG-****-H4B3).
String maskGiftCode(String code) {
  final parts = code.split('-');
  if (parts.length < 3) return code;
  return '${parts.first}-${'*' * parts[1].length}-${parts.last}';
}

class _GiftCardCheckPanelState extends State<GiftCardCheckPanel> {
  final _code = TextEditingController();
  bool _busy = false;
  Map<String, dynamic>? _result;  // kết quả check gần nhất
  Map<String, dynamic>? _applied; // kết quả redeem thành công {code, applied, remaining}
  String? _applyError;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final code = _code.text.trim().toUpperCase();
    if (code.isEmpty || _busy) return;
    setState(() { _busy = true; _result = null; _applyError = null; });
    final r = await widget.check(code);
    if (!mounted) return;
    setState(() { _busy = false; _result = r; });
  }

  bool get _canApply {
    final r = _result;
    if (r == null || r['ok'] != true || widget.redeem == null || widget.due == null) return false;
    final balance = (r['balance'] as num?)?.toDouble() ?? 0;
    return balance > 0 && balance >= widget.due!;
  }

  Future<void> _apply() async {
    final r = _result;
    if (!_canApply || _busy || r == null) return;
    final code = r['code']?.toString() ?? _code.text.trim().toUpperCase();
    setState(() { _busy = true; _applyError = null; });
    final ref = widget.redeemRef ?? 'POS-${DateTime.now().millisecondsSinceEpoch}';
    final res = await widget.redeem!(code, widget.due!, ref);
    if (!mounted) return;
    if (res['ok'] == true) {
      final applied = {
        'code': code,
        'applied': (res['applied'] as num?)?.toDouble() ?? widget.due!,
        'remaining': (res['remaining'] as num?)?.toDouble() ?? 0.0,
        'ref': ref,
      };
      setState(() { _busy = false; _applied = applied; });
      widget.onApplied?.call(applied);
    } else {
      setState(() {
        _busy = false;
        _applyError = res['offline'] == true
            ? 'Gift Card requires internet connection.'
            : 'Could not apply the gift card. The card was not charged — please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    final applied = _applied;
    if (applied != null) return _AppliedCard(applied: applied);
    final balance = (_result?['balance'] as num?)?.toDouble();
    final checkedOk = _result?['ok'] == true;
    final partialOnly = checkedOk && widget.due != null && (balance ?? 0) > 0 && (balance ?? 0) < widget.due!;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PField(label: 'Gift Card Code', child: PInput(
        controller: _code,
        hintText: 'VG-XXXX-XXXX',
        capitalization: TextCapitalization.characters,
        onSubmitted: (_) => _check(),
      )),
      PButton(
        _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4))
            : const Text('Check Balance'),
        expand: true,
        onPressed: _busy ? null : _check,
      ),
      if (_result != null) Padding(
        padding: const EdgeInsets.only(top: 14),
        child: _ResultCard(result: _result!),
      ),
      if (partialOnly) Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text('Partial gift card payment is coming soon.', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c.textMute)),
      ),
      if (_applyError != null) Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(_applyError!, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c.red)),
      ),
      const SizedBox(height: 12),
      PButton(
        Text(widget.due != null && _canApply ? 'Apply Gift Card · ${money(widget.due!)}' : 'Apply Gift Card'),
        expand: true,
        variant: _canApply ? PBtnVariant.primary : PBtnVariant.secondary,
        onPressed: _canApply && !_busy ? _apply : null,
      ),
    ]);
  }
}

class _AppliedCard extends StatelessWidget {
  final Map<String, dynamic> applied;
  const _AppliedCard({required this.applied});
  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    final amt = (applied['applied'] as num).toDouble();
    final remaining = (applied['remaining'] as num).toDouble();
    Widget row(String l, String v, {Color? color, double size = 14}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.textMute)),
        Text(v, style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, color: color ?? c.text)),
      ]),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.primaryA, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.check_circle, color: c.primary, size: 20),
          const SizedBox(width: 8),
          Text('GIFT CARD APPLIED', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: c.primary)),
        ]),
        const SizedBox(height: 10),
        row('Gift Card ${maskGiftCode(applied['code'].toString())}', '-${money(amt)}', color: c.primary, size: 18),
        row('Remaining due', money(0)),
        row('Remaining gift card balance', money(remaining)),
      ]),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final Map<String, dynamic> result;
  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    final r = result;
    Widget box(Color bg, Color fg, List<Widget> children) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
    TextStyle big(Color color) => TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color);
    TextStyle label(Color color) => TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color);

    if (r['offline'] == true) {
      return box(c.redA, c.red, [
        Text('GIFT CARD REQUIRES INTERNET CONNECTION', style: label(c.red)),
        const SizedBox(height: 4),
        Text('Connect to the internet and try again.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.text)),
      ]);
    }
    if (r['ok'] != true) {
      final notFound = r['status'] == 404;
      return box(c.redA, c.red, [
        Text(notFound ? 'NOT VALID' : 'CHECK FAILED', style: label(c.red)),
        const SizedBox(height: 4),
        Text(
          notFound
              ? 'Gift card not found or not valid for this store.'
              : 'Unable to check gift card right now. Please try again.',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.text),
        ),
      ]);
    }
    final balance = (r['balance'] as num?)?.toDouble() ?? 0;
    final code = maskGiftCode(r['code']?.toString() ?? '');
    if (balance <= 0) {
      return box(c.card, c.textMute, [
        Text(code, style: label(c.textMute)),
        const SizedBox(height: 4),
        Text('\$0.00', style: big(c.textMute)),
        const SizedBox(height: 2),
        Text('This gift card has no remaining balance.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.textMute)),
      ]);
    }
    return box(c.primaryA, c.primary, [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(code, style: label(c.primary)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(999)),
          child: Text('ACTIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: c.bg)),
        ),
      ]),
      const SizedBox(height: 6),
      Text(money(balance), style: big(c.primary)),
      const SizedBox(height: 2),
      Text('Current balance', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.textMute)),
    ]);
  }
}
