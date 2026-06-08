import 'package:flutter/material.dart';
import 'api.dart';
import 'printer.dart';
import 'theme.dart';

/// Order History — look up completed receipts, reprint, refund.
/// Mirrors the React HistoryView (cloud-backed via /api/orders).
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
  void initState() {
    super.initState();
    _load();
  }

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
    return _orders.where((o) {
      return '${o['number'] ?? ''}'.contains(q) ||
          (o['staffName'] ?? '').toString().toLowerCase().contains(q) ||
          (o['cardLast4'] ?? '').toString().contains(q) ||
          (o['source'] ?? '').toString().toLowerCase().contains(q) ||
          (o['note'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(backgroundColor: C.panel, elevation: 0, foregroundColor: C.ink,
        title: const Text('Order History', style: TextStyle(fontWeight: FontWeight.w900))),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 6), child: TextField(
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 20),
            hintText: 'Search by # / staff / card / note…',
            isDense: true, filled: true, fillColor: C.panel,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: const BorderSide(color: C.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: const BorderSide(color: C.border)),
          ),
        )),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2), child: Align(alignment: Alignment.centerLeft,
          child: Text('${list.length} of ${_orders.length} orders', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.textMute)))),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: C.brand))
            : list.isEmpty
                ? Center(child: Text(_orders.isEmpty ? 'No orders yet.' : 'No matches.', style: const TextStyle(color: C.textMute, fontWeight: FontWeight.w700)))
                : RefreshIndicator(onRefresh: _load, child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _row(list[i]),
                  ))),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> o) {
    final items = (o['items'] ?? []) as List;
    final total = _d(o['total']);
    final refunded = o['status'] == 'refunded' || o['status'] == 'voided';
    final meta = sourceMeta((o['source'] ?? 'POS').toString());
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
      child: ListTile(
        onTap: () => _detail(o),
        title: Row(children: [
          Text('#${o['number'] ?? o['id']}', style: const TextStyle(fontWeight: FontWeight.w900, color: C.ink)),
          const SizedBox(width: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: meta.color.withValues(alpha: .12), borderRadius: BorderRadius.circular(6)),
            child: Text(meta.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: meta.color))),
          if (refunded) ...[const SizedBox(width: 6), Text(o['status'].toString().toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: C.red))],
        ]),
        subtitle: Text('${_when(o)} · ${items.length} items${(o['paymentMethod'] ?? '') != '' ? ' · ${o['paymentMethod'].toString().toUpperCase()}' : ''}${(o['cardLast4'] ?? '') != '' ? ' · ••${o['cardLast4']}' : ''}',
            style: const TextStyle(fontSize: 11, color: C.textMute, fontWeight: FontWeight.w700)),
        trailing: Text(money(total), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: refunded ? C.red : C.brandDark)),
      ),
    );
  }

  String _when(Map<String, dynamic> o) {
    final raw = (o['completedAt'] ?? o['createdAt'] ?? '').toString();
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final l = dt.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _detail(Map<String, dynamic> o) async {
    await showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _OrderDetail(order: o, onChanged: _load));
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
      final name = (it['nameSnapshot'] ?? it['name'] ?? 'Item').toString();
      final line = _d(it['lineTotal']) != 0 ? _d(it['lineTotal']) : _d(it['price']) * (qty is int ? qty : 1);
      return {'qty': qty, 'name': name, 'lineTotal': line};
    }).toList();
    try {
      await printReceipt(
        storeName: Api.instance.storeName,
        number: '${o['number'] ?? o['id']}',
        type: (o['type'] ?? o['orderType'] ?? 'TO GO').toString(),
        items: items,
        subtotal: _d(o['subtotal']),
        tax: _d(o['taxAmount'] ?? o['tax']),
        tip: _d(o['tip']),
        total: _d(o['total']),
        paymentMethod: (o['paymentMethod'] ?? '').toString(),
        cashReceived: _d(o['cashReceived']),
        change: _d(o['changeGiven'] ?? o['change']),
      );
    } catch (_) {}
  }

  Future<void> _refund() async {
    final reason = await _askReason();
    if (reason == null) return;
    setState(() => _busy = true);
    final r = await Api.instance.refundOrder('${widget.order['id'] ?? widget.order['number']}', reason: reason);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['ok'] == true) {
      await widget.onChanged();
      if (mounted) Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((r['error'] ?? 'Refund failed').toString()), backgroundColor: C.red));
    }
  }

  Future<String?> _askReason() {
    final c = TextEditingController();
    return showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: const Text('Refund order?'),
      content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'Reason (optional)')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Refund', style: TextStyle(color: C.red))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final items = (o['items'] ?? []) as List;
    final refunded = o['status'] == 'refunded' || o['status'] == 'voided';
    return DraggableScrollableSheet(
      initialChildSize: .7, minChildSize: .4, maxChildSize: .95, expand: false,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(color: C.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
        child: ListView(controller: sc, padding: const EdgeInsets.all(20), children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: C.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Text('Order #${o['number'] ?? o['id']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: C.ink)),
          Text(_when(o), style: const TextStyle(fontSize: 12, color: C.textMute, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
            child: Column(children: [
              for (final e in items) _itemLine(Map<String, dynamic>.from(e)),
            ])),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
            child: Column(children: [
              _kv('Subtotal', money(_d(o['subtotal']))),
              if (_d(o['discount']) > 0) _kv('Discount', '−${money(_d(o['discount']))}', color: C.brandDark),
              _kv('Tax', money(_d(o['taxAmount'] ?? o['tax']))),
              if (_d(o['tip']) > 0) _kv('Tip', money(_d(o['tip']))),
              const Divider(),
              _kv('TOTAL', money(_d(o['total'])), bold: true),
              if (_d(o['cashReceived']) > 0) _kv('Cash', money(_d(o['cashReceived']))),
              if (_d(o['changeGiven'] ?? o['change']) > 0) _kv('Change', money(_d(o['changeGiven'] ?? o['change']))),
              if ((o['cardLast4'] ?? '') != '') _kv('Card', '${o['cardType'] ?? 'CARD'} ••${o['cardLast4']}'),
              _kv('Payment', (o['paymentMethod'] ?? 'card').toString().toUpperCase()),
            ])),
          if (refunded) Padding(padding: const EdgeInsets.only(top: 12),
            child: Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: C.redA, borderRadius: BorderRadius.circular(10)),
              child: Text('${o['status'].toString().toUpperCase()}${(o['refundReason'] ?? o['voidReason'] ?? '') != '' ? ' · ${o['refundReason'] ?? o['voidReason']}' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: C.red)))),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _reprint, icon: const Icon(Icons.print), label: const Text('Reprint'),
              style: OutlinedButton.styleFrom(foregroundColor: C.ink, side: const BorderSide(color: C.border), padding: const EdgeInsets.symmetric(vertical: 14)))),
            if (!refunded) ...[const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _refund, icon: const Icon(Icons.undo), label: const Text('Refund'),
                style: OutlinedButton.styleFrom(foregroundColor: C.red, side: const BorderSide(color: C.red), padding: const EdgeInsets.symmetric(vertical: 14))))],
          ]),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  String _when(Map<String, dynamic> o) {
    final dt = DateTime.tryParse((o['completedAt'] ?? o['createdAt'] ?? '').toString());
    if (dt == null) return '';
    final l = dt.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Widget _itemLine(Map<String, dynamic> it) {
    final qty = it['quantity'] ?? it['qty'] ?? 1;
    final name = (it['nameSnapshot'] ?? it['name'] ?? 'Item').toString();
    final mods = ((it['modifiers'] ?? []) as List).map((m) => (m is Map ? (m['optionName'] ?? m['name'] ?? '') : m).toString()).where((s) => s.isNotEmpty).toList();
    final line = _d(it['lineTotal']) != 0 ? _d(it['lineTotal']) : _d(it['price']) * (qty is int ? qty : 1);
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Text('$qty× $name', style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
        Text(money(line), style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink)),
      ]),
      if (mods.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text('+ ${mods.join(', ')}', style: const TextStyle(fontSize: 11, color: C.brandDark, fontWeight: FontWeight.w700))),
      if ((it['notes'] ?? '') != '') Padding(padding: const EdgeInsets.only(top: 2), child: Text('“${it['notes']}”', style: const TextStyle(fontSize: 11, color: C.textMute, fontWeight: FontWeight.w700))),
    ]));
  }

  Widget _kv(String k, String v, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w700, color: bold ? C.ink : C.textMute, fontSize: bold ? 16 : 13)),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w800, color: color ?? C.ink, fontSize: bold ? 16 : 13)),
        ]),
      );
}
