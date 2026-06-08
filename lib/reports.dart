import 'package:flutter/material.dart';
import 'api.dart';
import 'menu_manage.dart';
import 'theme.dart';

/// Reports + recent order history (owner view). Mirrors React ReportsView/HistoryView.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Map<String, dynamic> _sum = {};
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await Api.instance.getReports();
    final o = await Api.instance.getOrders();
    if (!mounted) return;
    setState(() {
      _sum = Map<String, dynamic>.from(r['summary'] ?? {});
      _orders = ((o['orders'] ?? []) as List).map((e) => Map<String, dynamic>.from(e)).toList();
      _loading = false;
    });
  }

  double _d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: C.brand));
    final tenders = Map<String, dynamic>.from(_sum['tenders'] ?? {});
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Reports', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: C.ink)),
        const Text("Today's sales", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.textMute)),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width >= 700 ? 4 : 2,
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.7,
          children: [
            _kpi('Net Sales', money(_d(_sum['netSales'])), C.green),
            _kpi('Orders', '${_sum['orders'] ?? 0}', C.online),
            _kpi('Card', money(_d(tenders['card']) + _d(tenders['online'])), C.kiosk),
            _kpi('Cash', money(_d(tenders['cash'])), C.brandDark),
          ],
        ),
        const SizedBox(height: 16),
        _panel('Tender mix', Column(children: [
          _row('Cash', money(_d(tenders['cash']))),
          _row('Card', money(_d(tenders['card']))),
          _row('Online', money(_d(tenders['online']))),
          _row('Tips', money(_d(_sum['tips']))),
          _row('Tax', money(_d(_sum['tax']))),
          _row('Refunds', '-${money(_d(_sum['refunds']))}', color: C.red),
        ])),
        const SizedBox(height: 16),
        _panel('Recent orders (${_orders.length})',
          _orders.isEmpty
              ? const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('No counter orders yet today.', style: TextStyle(color: C.textMute, fontWeight: FontWeight.w700)))
              : Column(children: [
                  for (final o in _orders.take(20)) _orderRow(o),
                ])),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _kpi(String label, String value, Color tone) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: C.textMute, letterSpacing: .4)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: tone)),
        ]),
      );

  Widget _panel(String title, Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: C.textMute)),
          const SizedBox(height: 10),
          child,
        ]),
      );

  Widget _row(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink, fontSize: 13)),
          Text(v, style: TextStyle(fontWeight: FontWeight.w900, color: color ?? C.ink, fontSize: 13)),
        ]),
      );

  Widget _orderRow(Map<String, dynamic> o) {
    final items = (o['items'] ?? []) as List;
    final first = items.isNotEmpty ? (items[0]['nameSnapshot'] ?? items[0]['name'] ?? 'Order') : 'Order';
    final more = items.length > 1 ? ' +${items.length - 1}' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('#${o['number'] ?? o['id']} · $first$more', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink, fontSize: 13)),
          Text('${(o['paymentMethod'] ?? '').toString().toUpperCase()} · ${o['source'] ?? 'POS'}', style: const TextStyle(fontSize: 11, color: C.textMute, fontWeight: FontWeight.w600)),
        ])),
        Text(money(_d(o['total'])), style: const TextStyle(fontWeight: FontWeight.w900, color: C.ink)),
      ]),
    );
  }
}

/// "More" — store info, order link, unlink.
class MoreScreen extends StatelessWidget {
  final VoidCallback onUnlink;
  final VoidCallback onEnterKiosk;
  const MoreScreen({super.key, required this.onUnlink, required this.onEnterKiosk});
  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('More', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: C.ink)),
      const SizedBox(height: 14),
      _card('Restaurant', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _kv('Name', Api.instance.storeName),
        _kv('Business type', Api.instance.isFullService ? 'Full-service' : 'Quick-service'),
      ])),
      const SizedBox(height: 12),
      _card('Online order link', const _OrderLinkEditor()),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
        child: ListTile(
          leading: const Icon(Icons.restaurant_menu, color: C.brandDark),
          title: const Text('Manage menu', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink)),
          subtitle: const Text('Add / edit / delete items, prices, 86', style: TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MenuManageScreen())),
        ),
      ),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
        child: ListTile(
          leading: const Icon(Icons.tablet_mac, color: C.kiosk),
          title: const Text('Switch to Kiosk mode', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink)),
          subtitle: const Text('Lock this device into customer self-order', style: TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
              title: const Text('Switch to Kiosk mode?'),
              content: const Text('Customers will self-order. Long-press the store name in kiosk to exit.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Switch')),
              ]));
            if (ok == true) onEnterKiosk();
          },
        ),
      ),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
        child: ListTile(
          leading: const Icon(Icons.link_off, color: C.red),
          title: const Text('Unlink this device', style: TextStyle(fontWeight: FontWeight.w800, color: C.red)),
          subtitle: const Text('Sign out the restaurant account', style: TextStyle(fontSize: 12)),
          onTap: () async {
            final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
              title: const Text('Unlink device?'),
              content: const Text('You will need to sign in again.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Unlink', style: TextStyle(color: C.red))),
              ],
            ));
            if (ok == true) onUnlink();
          },
        ),
      ),
    ]);
  }

  Widget _card(String title, Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: C.textMute, letterSpacing: .4)),
          const SizedBox(height: 10),
          child,
        ]),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: const TextStyle(color: C.textMute, fontWeight: FontWeight.w700, fontSize: 13)),
          Flexible(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(color: C.ink, fontWeight: FontWeight.w800, fontSize: 13))),
        ]),
      );
}

/// Editable online-order link (owner can customise the slug). Mirrors store dashboard.
class _OrderLinkEditor extends StatefulWidget {
  const _OrderLinkEditor();
  @override
  State<_OrderLinkEditor> createState() => _OrderLinkEditorState();
}

class _OrderLinkEditorState extends State<_OrderLinkEditor> {
  late final _slug = TextEditingController(text: Api.instance.storeSlug);
  String _url() => 'https://order.vidofood.com/${Api.instance.storeSlug}';
  bool _busy = false;
  String? _msg;
  bool _ok = false;

  Future<void> _save() async {
    final s = _slug.text.trim();
    if (s.isEmpty) { setState(() { _msg = 'Enter a link'; _ok = false; }); return; }
    setState(() { _busy = true; _msg = null; });
    final r = await Api.instance.setSlug(s);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = r['ok'] == true;
      if (_ok) {
        Api.instance.store = Store(id: Api.instance.store!.id, slug: (r['slug'] ?? s).toString(), name: Api.instance.storeName, businessType: Api.instance.store!.businessType);
        _slug.text = Api.instance.storeSlug;
        _msg = 'Updated · ${r['onlineOrderUrl']}';
      } else {
        _msg = (r['error'] ?? 'Could not update').toString();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Share with customers to order online.', style: TextStyle(fontSize: 12, color: C.textMute, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      SelectableText(_url(), style: const TextStyle(fontWeight: FontWeight.w800, color: C.brandDark)),
      const SizedBox(height: 12),
      const Text('CUSTOMISE LINK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: C.textMute, letterSpacing: .4)),
      const SizedBox(height: 6),
      Row(children: [
        const Text('order.vidofood.com/', style: TextStyle(fontWeight: FontWeight.w700, color: C.textMute, fontSize: 12)),
        Expanded(child: TextField(controller: _slug, decoration: InputDecoration(isDense: true, hintText: 'my-shop', filled: true, fillColor: C.bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)))),
        const SizedBox(width: 8),
        SizedBox(height: 40, child: ElevatedButton(
          onPressed: _busy ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: C.brand, foregroundColor: C.ink, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          child: _busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save', style: TextStyle(fontWeight: FontWeight.w900)),
        )),
      ]),
      const SizedBox(height: 6),
      const Text('Lowercase letters, numbers, hyphens. Must be unique. Old link stops working once changed.', style: TextStyle(fontSize: 11, color: C.textMute, fontWeight: FontWeight.w600)),
      if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: _ok ? C.green : C.red))),
    ]);
  }
}
