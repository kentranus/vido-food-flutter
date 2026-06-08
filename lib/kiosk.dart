import 'package:flutter/material.dart';
import 'api.dart';
import 'menu.dart';
import 'pos_sell.dart' show CustomizeSheet;
import 'theme.dart';

/// KIOSK MODE — customer self-order (big touch UI). Orders post to the backend
/// as paid Kiosk orders → appear on the POS board. Long-press the title to exit.
class KioskScreen extends StatefulWidget {
  final VoidCallback onExit;
  const KioskScreen({super.key, required this.onExit});
  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> {
  final repo = MenuRepo();
  final cart = <CartLine>[];
  String _cat = 'all';
  bool _loading = true;
  bool _checkout = false;
  String? _doneNumber;

  @override
  void initState() {
    super.initState();
    repo.load().then((_) { if (mounted) setState(() => _loading = false); });
  }

  double get _subtotal => cart.fold(0.0, (s, l) => s + l.lineTotal);
  double get _tax => _subtotal * repo.taxRate;
  double get _total => _subtotal + _tax;
  int get _count => cart.fold(0, (s, l) => s + l.qty);

  Future<void> _tap(MenuItem it) async {
    if (!it.sellable) return;
    final hasMods = it.modifierGroupIds.any((g) => (repo.groups[g]?.options.length ?? 0) > 0);
    if (!hasMods) { setState(() => cart.add(CartLine(it))); return; }
    final line = await showModalBottomSheet<CartLine>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (_) => CustomizeSheet(item: it, repo: repo));
    if (line != null) setState(() => cart.add(line));
  }

  Future<void> _placeOrder(String payMethod) async {
    final order = {
      'orderType': 'PICKUP',
      'paymentMethod': payMethod,
      'subtotal': _subtotal, 'tax': _tax, 'total': _total,
      'items': cart.map((l) => {
            'nameSnapshot': l.item.name, 'quantity': l.qty, 'priceSnapshot': l.item.price, 'lineTotal': l.lineTotal,
            'modifiers': l.mods.map((m) => {'optionName': m.name, 'priceDelta': m.priceDelta}).toList(), 'notes': l.note,
          }).toList(),
    };
    final r = await Api.instance.createKioskOrder(order);
    if (!mounted) return;
    if (r['ok'] == true) {
      setState(() { _doneNumber = (r['order']?['number'] ?? r['order']?['id'] ?? '').toString(); cart.clear(); _checkout = false; });
      Future.delayed(const Duration(seconds: 6), () { if (mounted) setState(() => _doneNumber = null); });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r['error']?.toString() ?? 'Order failed'), backgroundColor: C.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: C.brand)));
    if (_doneNumber != null) return _thankYou();
    if (_checkout) return _checkoutScreen();
    return _orderScreen();
  }

  Widget _header() => Container(
        color: C.brand,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Row(children: [
          GestureDetector(
            onLongPress: () async {
              final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
                title: const Text('Exit kiosk mode?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Exit')),
                ]));
              if (ok == true) widget.onExit();
            },
            child: Row(children: [
              const Icon(Icons.storefront, color: C.ink, size: 26),
              const SizedBox(width: 10),
              Text(Api.instance.storeName, style: const TextStyle(color: C.ink, fontSize: 22, fontWeight: FontWeight.w900)),
            ]),
          ),
          const Spacer(),
          const Text('Order here', style: TextStyle(color: C.ink, fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
      );

  Widget _orderScreen() {
    final cats = [const MenuCategory('all', 'All'), ...repo.categories];
    final items = _cat == 'all' ? repo.items : repo.items.where((i) => i.category == _cat).toList();
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(child: Column(children: [
        _header(),
        SizedBox(height: 64, child: ListView.separated(
          scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(12),
          itemCount: cats.length, separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) { final c = cats[i]; final on = c.id == _cat;
            return InkWell(onTap: () => setState(() => _cat = c.id), child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(color: on ? C.brand : C.panel, borderRadius: BorderRadius.circular(999), border: Border.all(color: on ? C.brandDark : C.border)),
              alignment: Alignment.center, child: Text(c.name, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: on ? C.ink : C.textMute)))); },
        )),
        Expanded(child: GridView.builder(
          padding: const EdgeInsets.all(14),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 230, mainAxisExtent: 200, crossAxisSpacing: 14, mainAxisSpacing: 14),
          itemCount: items.length,
          itemBuilder: (_, i) { final it = items[i]; final dim = !it.sellable;
            return InkWell(onTap: dim ? null : () => _tap(it), child: Opacity(opacity: dim ? .45 : 1, child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.icon, style: const TextStyle(fontSize: 44)),
                const Spacer(),
                Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: C.ink)),
                const SizedBox(height: 4),
                Row(children: [
                  Text(money(it.price), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: C.ink)),
                  const Spacer(),
                  if (dim) const Text('Sold out', style: TextStyle(color: C.red, fontWeight: FontWeight.w900, fontSize: 12))
                  else Container(width: 34, height: 34, decoration: const BoxDecoration(color: C.brand, shape: BoxShape.circle), child: const Icon(Icons.add, color: C.ink)),
                ]),
              ])))); },
        )),
      ])),
      bottomNavigationBar: cart.isEmpty ? null : SafeArea(child: Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(height: 64, child: ElevatedButton(
          onPressed: () => setState(() => _checkout = true),
          style: ElevatedButton.styleFrom(backgroundColor: C.ink, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('$_count item${_count == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            Text('Review & pay · ${money(_total)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          ]),
        )),
      )),
    );
  }

  Widget _checkoutScreen() {
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(child: Column(children: [
        _header(),
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Your order', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: C.ink)),
          const SizedBox(height: 12),
          for (int i = 0; i < cart.length; i++) _cartRow(i),
          const Divider(height: 28),
          _totRow('Subtotal', money(_subtotal)),
          _totRow('Tax', money(_tax)),
          _totRow('Total', money(_total), big: true),
        ])),
        SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          Row(children: [
            Expanded(child: SizedBox(height: 60, child: OutlinedButton(
              onPressed: () => setState(() => _checkout = false),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: C.border, width: 2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: const Text('Add more', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: C.ink))))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: SizedBox(height: 66, child: ElevatedButton.icon(
              onPressed: () => _placeOrder('card'),
              style: ElevatedButton.styleFrom(backgroundColor: C.green, foregroundColor: const Color(0xFF06210F), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              icon: const Icon(Icons.credit_card, size: 24), label: Text('Pay ${money(_total)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))))),
          ]),
          const SizedBox(height: 8),
          TextButton(onPressed: () => _placeOrder('pay_at_store'), child: const Text('Pay at counter', style: TextStyle(fontWeight: FontWeight.w800, color: C.textMute))),
        ]))),
      ])),
    );
  }

  Widget _thankYou() => Scaffold(
        backgroundColor: C.brand,
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 90),
          const SizedBox(height: 18),
          const Text('Thank you!', style: TextStyle(color: C.ink, fontSize: 34, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text('Order #$_doneNumber', style: const TextStyle(color: C.ink, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Please wait for your number.', style: TextStyle(color: C.ink, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          TextButton(onPressed: () => setState(() => _doneNumber = null), child: const Text('Start new order', style: TextStyle(color: C.ink, fontWeight: FontWeight.w900, fontSize: 16))),
        ])),
      );

  Widget _cartRow(int i) {
    final l = cart[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.item.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: C.ink)),
          if (l.modText.isNotEmpty) Text(l.modText, style: const TextStyle(fontSize: 12, color: C.textMute, fontWeight: FontWeight.w600)),
        ])),
        IconButton(onPressed: () => setState(() { if (l.qty > 1) { l.qty--; } else { cart.removeAt(i); } }), icon: const Icon(Icons.remove_circle_outline)),
        Text('${l.qty}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        IconButton(onPressed: () => setState(() => l.qty++), icon: const Icon(Icons.add_circle_outline)),
        SizedBox(width: 70, child: Text(money(l.lineTotal), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: C.ink))),
      ]),
    );
  }

  Widget _totRow(String k, String v, {bool big = false}) => Padding(
        padding: EdgeInsets.symmetric(vertical: big ? 4 : 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: TextStyle(fontWeight: big ? FontWeight.w900 : FontWeight.w700, fontSize: big ? 20 : 14, color: big ? C.ink : C.textMute)),
          Text(v, style: TextStyle(fontWeight: big ? FontWeight.w900 : FontWeight.w700, fontSize: big ? 20 : 14, color: big ? C.ink : C.textMute)),
        ]),
      );
}
