import 'package:flutter/material.dart';
import '../api.dart';
import '../printer.dart';
import '../ui/pos_theme.dart';
import '../ui/pos_widgets.dart';
import 'order_models.dart' show money;

/// Order History — faithful port of React HistoryView. Search by #/staff/card/
/// note, detail sheet, reprint receipt, refund/void. Reads /api/orders.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String _q = '';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final o = await Api.instance.getOrders();
    if (!mounted) return;
    final list = ((o['orders'] ?? []) as List).map((e) => Map<String, dynamic>.from(e)).toList();
    list.sort((a, b) => (b['completedAt'] ?? b['createdAt'] ?? '').toString().compareTo((a['completedAt'] ?? a['createdAt'] ?? '').toString()));
    setState(() { _orders = list; _loading = false; });
  }

  static double _d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  List<Map<String, dynamic>> get _filtered {
    if (_q.isEmpty) return _orders;
    final q = _q.toLowerCase();
    return _orders.where((o) => '${o['number'] ?? ''}'.contains(q) ||
        (o['staffName'] ?? '').toString().toLowerCase().contains(q) ||
        (o['cardLast4'] ?? '').toString().contains(q) ||
        (o['authCode'] ?? '').toString().toLowerCase().contains(q) ||
        (o['note'] ?? '').toString().toLowerCase().contains(q)).toList();
  }

  String _when(Map o) {
    final d = DateTime.tryParse((o['completedAt'] ?? o['createdAt'] ?? '').toString())?.toLocal();
    if (d == null) return '';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    final list = _filtered;
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(24, 20, 24, 6), child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Order History', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: c.text)),
          Text('${list.length} of ${_orders.length} orders', style: TextStyle(fontSize: 13, color: c.textMute, fontWeight: FontWeight.w700)),
        ]),
        const Spacer(),
        SizedBox(width: 320, child: PInput(hintText: 'Search by # / staff / card / note…', onChanged: (v) => setState(() => _q = v))),
      ])),
      Expanded(child: _loading
          ? Center(child: CircularProgressIndicator(color: c.primary))
          : list.isEmpty
              ? Center(child: Text(_orders.isEmpty ? 'No orders yet.' : 'No matches.', style: TextStyle(color: c.textMute, fontWeight: FontWeight.w700)))
              : RefreshIndicator(onRefresh: _load, color: c.primary, backgroundColor: c.panel,
                  child: ListView.builder(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), itemCount: list.length, itemBuilder: (_, i) => _row(c, list[i])))),
    ]);
  }

  Widget _row(PosColors c, Map<String, dynamic> o) {
    final items = (o['items'] ?? []) as List;
    final voided = o['status'] == 'refunded' || o['status'] == 'voided';
    return GestureDetector(
      onTap: () => _detail(o),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('#${o['number'] ?? o['id']}', style: TextStyle(fontWeight: FontWeight.w900, color: c.text)),
              const SizedBox(width: 8),
              if (voided) Text(o['status'].toString().toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: c.red)),
            ]),
            Text('${_when(o)} · ${items.length} items${(o['paymentMethod'] ?? '') != '' ? ' · ${o['paymentMethod'].toString().toUpperCase()}' : ''}${(o['cardLast4'] ?? '') != '' ? ' · ••${o['cardLast4']}' : ''}',
                style: TextStyle(fontSize: 11, color: c.textMute, fontWeight: FontWeight.w700)),
          ])),
          Text(money(_d(o['total'])), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: voided ? c.red : c.primary)),
        ]),
      ),
    );
  }

  Future<void> _detail(Map<String, dynamic> o) async {
    await showDialog(context: context, barrierColor: PT.c.overlay, builder: (_) => _OrderDetail(order: o, onChanged: _load));
  }
}

class _OrderDetail extends StatefulWidget {
  final Map<String, dynamic> order;
  final Future<void> Function() onChanged;
  const _OrderDetail({required this.order, required this.onChanged});
  @override
  State<_OrderDetail> createState() => _OrderDetailState();
}

class _OrderDetailState extends State<_OrderDetail> {
  bool _busy = false;
  static double _d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  Future<void> _reprint() async {
    final o = widget.order;
    final items = ((o['items'] ?? []) as List).map((e) {
      final it = Map<String, dynamic>.from(e);
      final qty = (it['quantity'] ?? it['qty'] ?? 1);
      final line = _d(it['lineTotal']) != 0 ? _d(it['lineTotal']) : _d(it['price']) * (qty is int ? qty : 1);
      return {'qty': qty, 'name': (it['nameSnapshot'] ?? it['name'] ?? 'Item').toString(), 'lineTotal': line};
    }).toList();
    try {
      await printReceipt(storeName: Api.instance.storeName.isEmpty ? 'Vido Food' : Api.instance.storeName,
          number: '${o['number'] ?? o['id']}', type: (o['type'] ?? o['orderType'] ?? 'TO GO').toString(), items: items,
          subtotal: _d(o['subtotal']), tax: _d(o['taxAmount'] ?? o['tax']), tip: _d(o['tip']), total: _d(o['total']),
          paymentMethod: (o['paymentMethod'] ?? '').toString(), cashReceived: _d(o['cashReceived']), change: _d(o['changeGiven'] ?? o['change']));
    } catch (_) {}
  }

  Future<void> _refund() async {
    final reason = await _askReason();
    if (reason == null) return;
    setState(() => _busy = true);
    final r = await Api.instance.refundOrder('${widget.order['id'] ?? widget.order['number']}', reason: reason);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['ok'] == true) { await widget.onChanged(); if (mounted) Navigator.pop(context); }
    else { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((r['error'] ?? 'Refund failed').toString()), backgroundColor: PT.c.red)); }
  }

  Future<String?> _askReason() {
    final ctl = TextEditingController();
    final c = PT.c;
    return showDialog<String>(context: context, builder: (_) => AlertDialog(
      backgroundColor: c.panel,
      title: Text('Refund order?', style: TextStyle(color: c.text)),
      content: PInput(controller: ctl, hintText: 'Reason (optional)'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: c.textMute))),
        TextButton(onPressed: () => Navigator.pop(context, ctl.text.trim()), child: Text('Refund', style: TextStyle(color: c.red, fontWeight: FontWeight.w900))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    final o = widget.order;
    final items = (o['items'] ?? []) as List;
    final voided = o['status'] == 'refunded' || o['status'] == 'voided';
    String when() { final d = DateTime.tryParse((o['completedAt'] ?? o['createdAt'] ?? '').toString())?.toLocal(); return d == null ? '' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'; }
    Widget row(String k, String v, {bool bold = false, Color? color}) => Padding(padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w700, color: bold ? c.text : c.textMute, fontSize: bold ? 16 : 13)),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w800, color: color ?? c.text, fontSize: bold ? 16 : 13)),
        ]));
    return Dialog(backgroundColor: Colors.transparent, insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 460, maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(18)),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Order #${o['number'] ?? o['id']}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c.text)),
            Text(when(), style: TextStyle(fontSize: 12, color: c.textMute, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12)), child: Column(children: [
              for (final e in items) Builder(builder: (_) {
                final it = Map<String, dynamic>.from(e);
                final qty = it['quantity'] ?? it['qty'] ?? 1;
                final line = _d(it['lineTotal']) != 0 ? _d(it['lineTotal']) : _d(it['price']) * (qty is int ? qty : 1);
                return row('$qty× ${it['nameSnapshot'] ?? it['name'] ?? 'Item'}', money(line));
              }),
            ])),
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12)), child: Column(children: [
              row('Subtotal', money(_d(o['subtotal']))),
              row('Tax', money(_d(o['taxAmount'] ?? o['tax']))),
              if (_d(o['tip']) > 0) row('Tip', money(_d(o['tip']))),
              const Divider(),
              row('TOTAL', money(_d(o['total'])), bold: true),
              if ((o['cardLast4'] ?? '') != '') row('Card', '${o['cardType'] ?? 'CARD'} ••${o['cardLast4']}'),
              row('Payment', (o['paymentMethod'] ?? 'card').toString().toUpperCase()),
            ])),
            if (voided) Padding(padding: const EdgeInsets.only(top: 12), child: Container(width: double.infinity, padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.redA, borderRadius: BorderRadius.circular(10)),
                child: Text('${o['status'].toString().toUpperCase()}${(o['refundReason'] ?? o['voidReason'] ?? '') != '' ? ' · ${o['refundReason'] ?? o['voidReason']}' : ''}', style: TextStyle(fontWeight: FontWeight.w800, color: c.red)))),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: PButton(const Text('🖨️ Reprint'), variant: PBtnVariant.ghost, expand: true, onPressed: _busy ? null : _reprint)),
              if (!voided) ...[const SizedBox(width: 10),
                Expanded(child: PButton(const Text('Refund'), variant: PBtnVariant.danger, expand: true, onPressed: _busy ? null : _refund))],
            ]),
          ])),
        ),
      ),
    );
  }
}
