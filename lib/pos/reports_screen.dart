import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../ui/pos_theme.dart';
import '../ui/pos_widgets.dart';
import 'order_models.dart' show money;

/// Reports — faithful port of React ReportsView. Date-range stats computed
/// client-side from /api/orders: Net Sales / Tips / Orders / Avg, Tax + Gross +
/// Refunds, Payment Methods, Top Items, Recent orders, CSV export (to clipboard).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _Range { final String label; final DateTime start, end; const _Range(this.label, this.start, this.end); }

class _ReportsScreenState extends State<ReportsScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  late _Range _range = _ranges()[0];

  List<_Range> _ranges() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [
      _Range('Today', today, today.add(const Duration(days: 1))),
      _Range('Yesterday', today.subtract(const Duration(days: 1)), today),
      _Range('Last 7 Days', today.subtract(const Duration(days: 6)), today.add(const Duration(days: 1))),
      _Range('This Month', DateTime(now.year, now.month, 1), today.add(const Duration(days: 1))),
      _Range('Last 30 Days', today.subtract(const Duration(days: 29)), today.add(const Duration(days: 1))),
    ];
  }

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final o = await Api.instance.getOrders();
    if (!mounted) return;
    setState(() {
      _orders = ((o['orders'] ?? []) as List).map((e) => Map<String, dynamic>.from(e)).toList();
      _loading = false;
    });
  }

  static double _d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
  DateTime? _when(Map o) => DateTime.tryParse((o['completedAt'] ?? o['createdAt'] ?? '').toString());

  List<Map<String, dynamic>> get _inRange => _orders.where((o) {
        final d = _when(o)?.toLocal();
        return d != null && !d.isBefore(_range.start) && d.isBefore(_range.end);
      }).toList();

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    if (_loading) return Center(child: CircularProgressIndicator(color: c.primary));
    final orders = _inRange;
    final valid = orders.where((o) => o['status'] != 'voided').toList();
    final gross = valid.fold(0.0, (s, o) => s + _d(o['total']));
    final refunds = orders.fold(0.0, (s, o) => s + (o['status'] == 'voided' ? _d(o['total']) : _d(o['refundAmount'])));
    final net = gross - refunds;
    final tips = valid.fold(0.0, (s, o) => s + _d(o['tip']));
    final tax = valid.fold(0.0, (s, o) => s + _d(o['taxAmount'] ?? o['tax']));
    final count = valid.length;
    final avg = count > 0 ? net / count : 0.0;
    // tender mix
    final tender = <String, double>{'cash': 0, 'card': 0, 'giftcard': 0};
    for (final o in valid) {
      final m = (o['paymentMethod'] ?? 'card').toString();
      tender[m] = (tender[m] ?? 0) + _d(o['total']);
    }
    // top items
    final items = <String, int>{};
    for (final o in valid) {
      for (final it in (o['items'] ?? []) as List) {
        final n = (it['nameSnapshot'] ?? it['name'] ?? 'Item').toString();
        final q = (it['quantity'] ?? it['qty'] ?? 1);
        items[n] = (items[n] ?? 0) + (q is int ? q : 1);
      }
    }
    final top = items.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return RefreshIndicator(
      onRefresh: _load, color: c.primary, backgroundColor: c.panel,
      child: ListView(padding: const EdgeInsets.all(24), children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Reports', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: c.text)),
            Text('${_range.label}: ${orders.length} orders', style: TextStyle(fontSize: 13, color: c.textMute, fontWeight: FontWeight.w700)),
          ]),
          Row(children: [
            _rangePicker(c),
            const SizedBox(width: 10),
            PButton(const Text('⬇ Export CSV'), variant: PBtnVariant.ghost, onPressed: orders.isEmpty ? null : () => _exportCsv(orders)),
          ]),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          _stat(c, 'Net Sales', money(net), c.primary),
          _stat(c, 'Total Tips', money(tips), c.yellow),
          _stat(c, 'Orders', '$count', c.cyan),
          _stat(c, 'Avg Order', money(avg), c.blue),
        ].expand((w) => [Expanded(child: w), const SizedBox(width: 12)]).toList()..removeLast()),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _card(c, 'Sales summary', Column(children: [
            _row(c, 'Gross sales', money(gross)),
            _row(c, 'Tax collected', money(tax)),
            _row(c, 'Refunds / voids', '-${money(refunds)}', color: c.red),
            const Divider(),
            _row(c, 'Net sales', money(net), bold: true),
          ]))),
          const SizedBox(width: 14),
          Expanded(child: _card(c, 'Payment methods', Column(children: [
            _row(c, '💵 Cash', money(tender['cash'] ?? 0)),
            _row(c, '💳 Card', money(tender['card'] ?? 0)),
            _row(c, '🎁 Gift card', money(tender['giftcard'] ?? 0)),
          ]))),
        ]),
        const SizedBox(height: 14),
        _card(c, 'Top items', top.isEmpty
            ? Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('No sales in this range.', style: TextStyle(color: c.textMute, fontWeight: FontWeight.w700)))
            : Column(children: [for (final e in top.take(8)) _row(c, e.key, '${e.value} sold')])),
        const SizedBox(height: 14),
        _card(c, 'Recent orders (${orders.length})', orders.isEmpty
            ? Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('No orders.', style: TextStyle(color: c.textMute, fontWeight: FontWeight.w700)))
            : Column(children: [for (final o in orders.take(20)) _orderRow(c, o)])),
        const SizedBox(height: 30),
      ]),
    );
  }

  Widget _rangePicker(PosColors c) => Container(
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonHideUnderline(child: DropdownButton<String>(
          value: _range.label, dropdownColor: c.panel, style: TextStyle(color: c.text, fontWeight: FontWeight.w800, fontSize: 13),
          items: [for (final r in _ranges()) DropdownMenuItem(value: r.label, child: Text(r.label))],
          onChanged: (v) { final r = _ranges().firstWhere((x) => x.label == v); setState(() => _range = r); },
        )),
      );

  Widget _stat(PosColors c, String label, String value, Color tone) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: c.textMute, letterSpacing: .4)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: tone)),
        ]),
      );

  Widget _card(PosColors c, String title, Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: c.textMute)),
          const SizedBox(height: 10), child,
        ]),
      );

  Widget _row(PosColors c, String k, String v, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w700, color: c.text, fontSize: 13)),
          Text(v, style: TextStyle(fontWeight: FontWeight.w900, color: color ?? c.text, fontSize: 13)),
        ]),
      );

  Widget _orderRow(PosColors c, Map<String, dynamic> o) {
    final items = (o['items'] ?? []) as List;
    final first = items.isNotEmpty ? (items[0]['nameSnapshot'] ?? items[0]['name'] ?? 'Order') : 'Order';
    final more = items.length > 1 ? ' +${items.length - 1}' : '';
    final voided = o['status'] == 'voided' || o['status'] == 'refunded';
    return Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('#${o['number'] ?? o['id']} · $first$more', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: c.text, fontSize: 13)),
        Text('${(o['paymentMethod'] ?? '').toString().toUpperCase()} · ${o['type'] ?? o['source'] ?? 'POS'}${voided ? ' · ${o['status']}' : ''}', style: TextStyle(fontSize: 11, color: c.textMute, fontWeight: FontWeight.w600)),
      ])),
      Text(money(_d(o['total'])), style: TextStyle(fontWeight: FontWeight.w900, color: voided ? c.red : c.text)),
    ]));
  }

  void _exportCsv(List<Map<String, dynamic>> orders) {
    final b = StringBuffer('Order #,Date,Type,Items,Subtotal,Tax,Tip,Total,Payment,Status\n');
    for (final o in orders) {
      final d = _when(o)?.toLocal();
      final items = (o['items'] ?? []) as List;
      final names = items.map((i) => '${i['quantity'] ?? i['qty'] ?? 1}x ${i['nameSnapshot'] ?? i['name'] ?? ''}').join('; ');
      b.writeln('${o['number'] ?? o['id']},${d?.toIso8601String() ?? ''},${o['type'] ?? ''},"$names",${_d(o['subtotal'])},${_d(o['taxAmount'] ?? o['tax'])},${_d(o['tip'])},${_d(o['total'])},${o['paymentMethod'] ?? ''},${o['status'] ?? ''}');
    }
    Clipboard.setData(ClipboardData(text: b.toString()));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('CSV copied (${orders.length} orders) — paste into Sheets/Excel'), backgroundColor: PT.c.green));
  }
}
