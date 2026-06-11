import 'package:flutter/material.dart';

import '../ui/pos_theme.dart';
import '../ui/pos_widgets.dart';
import 'order_models.dart' show money;

/// Phase D2 — Gift Card: manual code entry + Check Balance ONLY.
/// No redeem/apply here (that is Phase D3+). The panel is public and takes the
/// API call as a callback so widget tests can drive every state offline.
///
/// `check` resolves to the backend response map of POST /api/gift-cards/check:
///   ok:true  → {ok:true, code, balance, initial}
///   not found→ {status:404, ok:false, error}
///   offline  → {status:0, ok:false, offline:true}
class GiftCardCheckPanel extends StatefulWidget {
  final Future<Map<String, dynamic>> Function(String code) check;
  const GiftCardCheckPanel({super.key, required this.check});

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
  Map<String, dynamic>? _result; // last check response (null = chưa check)

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final code = _code.text.trim().toUpperCase();
    if (code.isEmpty || _busy) return;
    setState(() { _busy = true; _result = null; });
    final r = await widget.check(code);
    if (!mounted) return;
    setState(() { _busy = false; _result = r; });
  }

  @override
  Widget build(BuildContext context) {
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
      const SizedBox(height: 12),
      // Placeholder cho Phase D3 — chưa apply được.
      PButton(const Text('Apply — coming next'), expand: true, variant: PBtnVariant.secondary, onPressed: null),
    ]);
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
