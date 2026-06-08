import 'package:flutter/material.dart';
import '../api.dart';
import '../ui/pos_theme.dart';
import '../ui/pos_widgets.dart';
import 'order_models.dart' show money;

/// Operations — faithful port of React OperationsView. KPIs, live counter queue,
/// refunds & voids (Adjust → refund/void), and end-of-shift Closeout with cash
/// variance. Computes from /api/orders (today).
class OperationsScreen extends StatefulWidget {
  const OperationsScreen({super.key});
  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  final _cashCounted = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final o = await Api.instance.getOrders();
    if (!mounted) return;
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final list = ((o['orders'] ?? []) as List).map((e) => Map<String, dynamic>.from(e))
        .where((x) { final d = DateTime.tryParse((x['completedAt'] ?? x['createdAt'] ?? '').toString())?.toLocal(); return d != null && !d.isBefore(start); })
        .toList()
      ..sort((a, b) => (b['completedAt'] ?? '').toString().compareTo((a['completedAt'] ?? '').toString()));
    setState(() { _orders = list; _loading = false; });
  }

  static double _d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  Future<void> _adjust(Map<String, dynamic> o) async {
    final res = await showDialog<({String type, double amount, String reason})>(
      context: context, barrierColor: PT.c.overlay, builder: (_) => _AdjustDialog(order: o));
    if (res == null) return;
    if (res.type == 'void') {
      await Api.instance.voidOrder('${o['id'] ?? o['number']}', reason: res.reason);
    } else {
      await Api.instance.refundOrder('${o['id'] ?? o['number']}', amount: res.amount, reason: res.reason);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    if (_loading) return Center(child: CircularProgressIndicator(color: c.primary));
    // metrics
    var orders = 0; var refunds = 0.0, net = 0.0, card = 0.0, cash = 0.0, gift = 0.0;
    for (final o in _orders) {
      final total = _d(o['total']);
      final refund = o['status'] == 'voided' ? total : _d(o['refundAmount']);
      final n = (total - refund).clamp(0, double.infinity).toDouble();
      if (o['status'] != 'voided') orders++;
      refunds += refund; net += n;
      final m = (o['paymentMethod'] ?? 'card').toString();
      if (m == 'cash') { cash += n; } else if (m == 'giftcard') { gift += n; } else { card += n; }
    }
    final counted = double.tryParse(_cashCounted.text) ?? 0;
    final variance = counted - cash;
    final queue = _orders.where((o) => o['status'] != 'voided').take(8).toList();
    final adj = _orders.where((o) => o['status'] != 'voided').take(12).toList();

    return ListView(padding: const EdgeInsets.all(24), children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Operations', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: c.text)),
          Text('Queue, closeout, refunds — today', style: TextStyle(fontSize: 13, color: c.textMute, fontWeight: FontWeight.w700)),
        ]),
        PButton(const Text('Refresh'), variant: PBtnVariant.ghost, onPressed: _load),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        _kpi(c, 'Orders Today', '$orders', c.cyan),
        _kpi(c, 'Net Sales', money(net), c.primary),
        _kpi(c, 'Card Payment', money(card), c.blue),
        _kpi(c, 'Expected Cash', money(cash), c.yellow),
      ].expand((w) => [Expanded(child: w), const SizedBox(width: 12)]).toList()..removeLast()),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // left
        Expanded(flex: 2, child: Column(children: [
          _panel(c, 'Live Counter Queue', queue.isEmpty
              ? _empty(c, 'No completed tickets today yet.')
              : Column(children: [for (final o in queue) _queueRow(c, o)])),
          const SizedBox(height: 14),
          _panel(c, 'Refunds & Voids', adj.isEmpty
              ? _empty(c, 'No orders to adjust.')
              : Column(children: [for (final o in adj) _adjRow(c, o)])),
        ])),
        const SizedBox(width: 14),
        // right — closeout
        Expanded(child: _panel(c, 'Closeout', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _row(c, 'Cash sales', money(cash)),
          _row(c, 'Card sales', money(card)),
          if (gift > 0) _row(c, 'Gift card', money(gift)),
          _row(c, 'Refunds', '-${money(refunds)}', color: c.red),
          const SizedBox(height: 10),
          PField(label: 'Cash counted', child: PInput(controller: _cashCounted, hintText: '0.00', keyboardType: TextInputType.number, onChanged: (_) => setState(() {}))),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
                color: variance.abs() < 0.01 ? const Color(0x1F4ADE80) : variance < 0 ? c.redA : c.primaryA),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Variance', style: TextStyle(fontWeight: FontWeight.w900, color: c.text)),
              Text(money(variance), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18,
                  color: variance.abs() < 0.01 ? c.green : variance < 0 ? c.red : c.primary)),
            ]),
          ),
          const SizedBox(height: 10),
          PField(label: 'Closeout note', child: PInput(controller: _note, hintText: 'Closeout note…')),
        ]))),
      ]),
      const SizedBox(height: 30),
    ]);
  }

  Widget _kpi(PosColors c, String label, String value, Color tone) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: c.textMute, letterSpacing: .4)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: tone)),
        ]),
      );

  Widget _panel(PosColors c, String title, Widget child) => Container(
        width: double.infinity, padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: c.textMute)),
          const SizedBox(height: 10), child,
        ]),
      );

  Widget _empty(PosColors c, String t) => Padding(padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(t, style: TextStyle(color: c.textDim, fontWeight: FontWeight.w700)));

  String _name(Map o) {
    final items = (o['items'] ?? []) as List;
    if (items.isEmpty) return 'Order';
    final f = (items[0]['nameSnapshot'] ?? items[0]['name'] ?? 'Order').toString();
    return items.length > 1 ? '$f +${items.length - 1}' : f;
  }

  Widget _queueRow(PosColors c, Map<String, dynamic> o) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Text('#${o['number'] ?? o['id']}', style: TextStyle(fontWeight: FontWeight.w900, color: c.primary)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_name(o), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: c.text, fontSize: 13)),
            Text('${(o['paymentMethod'] ?? '').toString().toUpperCase()} · ${o['type'] ?? o['source'] ?? 'POS'}', style: TextStyle(fontSize: 11, color: c.textMute, fontWeight: FontWeight.w600)),
          ])),
          Text(money(_d(o['total'])), style: TextStyle(fontWeight: FontWeight.w900, color: c.text)),
        ]),
      );

  Widget _adjRow(PosColors c, Map<String, dynamic> o) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('#${o['number'] ?? o['id']} · ${money(_d(o['total']))}', style: TextStyle(fontWeight: FontWeight.w800, color: c.text, fontSize: 13)),
            Text('${(o['paymentMethod'] ?? '').toString().toUpperCase()}${_d(o['refundAmount']) > 0 ? ' · Refunded ${money(_d(o['refundAmount']))}' : ''}', style: TextStyle(fontSize: 11, color: c.textMute, fontWeight: FontWeight.w600)),
          ])),
          PButton(const Text('Adjust'), variant: PBtnVariant.ghost, size: PBtnSize.sm, onPressed: () => _adjust(o)),
        ]),
      );

  Widget _row(PosColors c, String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: TextStyle(fontWeight: FontWeight.w700, color: c.text, fontSize: 13)),
          Text(v, style: TextStyle(fontWeight: FontWeight.w900, color: color ?? c.text, fontSize: 13)),
        ]),
      );
}

class _AdjustDialog extends StatefulWidget {
  final Map<String, dynamic> order;
  const _AdjustDialog({required this.order});
  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  String _type = 'refund';
  late final _amount = TextEditingController(text: '${(widget.order['total'] ?? 0)}');
  final _reason = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    return Dialog(backgroundColor: Colors.transparent, child: Container(
      constraints: const BoxConstraints(maxWidth: 420), padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(18)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Adjust Order #${widget.order['number'] ?? widget.order['id']}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c.text)),
        const SizedBox(height: 14),
        Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(10)), child: Row(children: [
          _seg(c, 'Refund', _type == 'refund', () => setState(() => _type = 'refund')),
          _seg(c, 'Void', _type == 'void', () => setState(() => _type = 'void')),
        ])),
        const SizedBox(height: 12),
        if (_type == 'refund') PField(label: 'Refund Amount', child: PInput(controller: _amount, keyboardType: TextInputType.number)),
        PField(label: 'Reason', child: PInput(controller: _reason, hintText: 'Optional')),
        PButton(const Text('Save Adjustment'), expand: true, onPressed: () => Navigator.of(context).pop((
          type: _type, amount: double.tryParse(_amount.text) ?? 0, reason: _reason.text.trim()))),
      ]),
    ));
  }

  Widget _seg(PosColors c, String label, bool active, VoidCallback onTap) => Expanded(child: GestureDetector(
        onTap: onTap,
        child: Container(padding: const EdgeInsets.symmetric(vertical: 10), alignment: Alignment.center,
            decoration: BoxDecoration(color: active ? c.primary : Colors.transparent, borderRadius: BorderRadius.circular(8)),
            child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: active ? c.bg : c.text))),
      ));
}
