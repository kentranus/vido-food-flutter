import 'package:flutter/material.dart';
import 'api.dart';
import 'menu.dart';
import 'pax.dart';
import 'printer.dart';
import 'theme.dart';

const _orderTypes = ['Dine In', 'To Go', 'Delivery'];

class SellScreen extends StatefulWidget {
  const SellScreen({super.key});
  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen> {
  final repo = MenuRepo();
  final cart = <CartLine>[];
  String _cat = 'all';
  String _type = 'To Go';
  String _table = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    repo.load().then((_) { if (mounted) setState(() => _loading = false); });
  }

  double get _subtotal => cart.fold(0.0, (s, l) => s + l.lineTotal);
  double get _tax => _subtotal * repo.taxRate;
  double get _total => _subtotal + _tax;
  int get _count => cart.fold(0, (s, l) => s + l.qty);

  void _add(CartLine line) {
    setState(() => cart.add(line));
  }

  Future<void> _tapItem(MenuItem it) async {
    if (!it.sellable) return;
    final hasMods = it.modifierGroupIds.any((g) => (repo.groups[g]?.options.length ?? 0) > 0);
    if (!hasMods) { _add(CartLine(it)); return; }
    final line = await showModalBottomSheet<CartLine>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => CustomizeSheet(item: it, repo: repo),
    );
    if (line != null) _add(line);
  }

  Future<void> _toggle86(MenuItem it) async {
    final next = !it.is86d;
    final ok = await repo.set86(it.id, next);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? '${it.name} ${next ? 'marked 86 (sold out)' : 'available again'}' : 'Could not update'),
      backgroundColor: ok ? (next ? C.red : C.green) : C.red, duration: const Duration(seconds: 2)));
  }

  Future<void> _pay() async {
    if (cart.isEmpty) return;
    final paid = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => PaymentSheet(total: _total, onComplete: (method, received, card) async {
        final order = {
          'source': 'POS',
          'orderType': _type.toUpperCase().replaceAll(' ', '_'),
          'tableNumber': _table,
          'status': 'completed',
          'paymentMethod': method,
          'subtotal': _subtotal,
          'tax': _tax,
          'total': _total,
          'cashReceived': received,
          'changeGiven': received > 0 ? (received - _total) : 0,
          if (card != null) ...{
            'cardLast4': card.cardLast4,
            'cardType': card.cardType,
            'authCode': card.authCode,
          },
          'items': cart.map((l) => {
                'nameSnapshot': l.item.name,
                'quantity': l.qty,
                'priceSnapshot': l.item.price,
                'lineTotal': l.lineTotal,
                'modifiers': l.mods.map((m) => {'optionName': m.name, 'priceDelta': m.priceDelta}).toList(),
                'notes': l.note,
              }).toList(),
        };
        final r = await Api.instance.createOrder(order);
        if (r['ok'] == true) {
          final num = (r['order']?['number'] ?? r['order']?['id'] ?? '').toString();
          try {
            await printReceipt(
              storeName: Api.instance.storeName, number: num, type: _type,
              items: cart.map((l) => {'qty': l.qty, 'name': l.item.name, 'lineTotal': l.lineTotal}).toList(),
              subtotal: _subtotal, tax: _tax, total: _total,
              paymentMethod: method, cashReceived: received, change: received > 0 ? received - _total : 0,
            );
          } catch (_) {}
        }
        return r['ok'] == true;
      }),
    );
    if (paid == true && mounted) {
      setState(() { cart.clear(); _table = ''; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order completed'), backgroundColor: C.green));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: C.brand));
    final wide = MediaQuery.of(context).size.width >= 760;
    final menu = _menuPane();
    if (wide) {
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: menu),
        SizedBox(width: 340, child: _cartPane(embedded: true)),
      ]);
    }
    return Stack(children: [
      Padding(padding: const EdgeInsets.only(bottom: 70), child: menu),
      Positioned(left: 12, right: 12, bottom: 12, child: _cartBar()),
    ]);
  }

  Widget _menuPane() {
    final cats = [const MenuCategory('all', 'All'), ...repo.categories];
    final items = _cat == 'all' ? repo.items : repo.items.where((i) => i.category == _cat).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 56,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          itemCount: cats.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final c = cats[i]; final on = c.id == _cat;
            return InkWell(
              onTap: () => setState(() => _cat = c.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: on ? C.brand : C.panel, borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: on ? C.brandDark : C.border)),
                alignment: Alignment.center,
                child: Text(c.name, style: TextStyle(fontWeight: FontWeight.w800, color: on ? C.ink : C.textMute)),
              ),
            );
          },
        ),
      ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 180, mainAxisExtent: 150, crossAxisSpacing: 12, mainAxisSpacing: 12),
          itemCount: items.length,
          itemBuilder: (_, i) => _ItemTile(item: items[i], onTap: () => _tapItem(items[i]), onLongPress: () => _toggle86(items[i])),
        ),
      ),
    ]);
  }

  Widget _cartBar() {
    return Material(
      color: C.ink, borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: cart.isEmpty ? null : () => showModalBottomSheet(
          context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
          builder: (_) => DraggableScrollableSheet(
            initialChildSize: .85, maxChildSize: .95, minChildSize: .5, expand: false,
            builder: (_, sc) => Container(
              decoration: const BoxDecoration(color: C.panel, borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
              child: _cartPane(embedded: false, scroll: sc),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(children: [
            Text('$_count item${_count == 1 ? '' : 's'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
            const Spacer(),
            Text('View cart · ${money(_total)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
          ]),
        ),
      ),
    );
  }

  Widget _cartPane({required bool embedded, ScrollController? scroll}) {
    return Container(
      color: embedded ? C.bg : C.panel,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            const Text('Order', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: C.ink)),
            const Spacer(),
            if (cart.isNotEmpty)
              TextButton(onPressed: () => setState(() => cart.clear()), child: const Text('Clear', style: TextStyle(color: C.red, fontWeight: FontWeight.w800))),
          ]),
        ),
        // order type
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            for (final t in _orderTypes) ...[
              Expanded(child: InkWell(
                onTap: () => setState(() => _type = t),
                child: Container(
                  height: 38, alignment: Alignment.center,
                  decoration: BoxDecoration(color: _type == t ? C.brand : C.panel, borderRadius: BorderRadius.circular(10), border: Border.all(color: _type == t ? C.brandDark : C.border)),
                  child: Text(t, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: _type == t ? C.ink : C.textMute)),
                ),
              )),
              if (t != _orderTypes.last) const SizedBox(width: 8),
            ]
          ]),
        ),
        if (_type == 'Dine In')
          Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: TextField(
            onChanged: (v) => _table = v,
            decoration: InputDecoration(hintText: 'Table number', isDense: true, filled: true, fillColor: C.panel,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))))),
        Expanded(
          child: cart.isEmpty
              ? const Center(child: Text('Tap items to add', style: TextStyle(color: C.textMute, fontWeight: FontWeight.w700)))
              : ListView.builder(
                  controller: scroll, padding: const EdgeInsets.all(12), itemCount: cart.length,
                  itemBuilder: (_, i) => _CartRow(line: cart[i], onChanged: () => setState(() {}), onRemove: () => setState(() => cart.removeAt(i))),
                ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(color: C.panel, border: Border(top: BorderSide(color: C.border))),
          child: Column(children: [
            _row('Subtotal', money(_subtotal)),
            _row('Tax (${(repo.taxRate * 100).toStringAsFixed(2)}%)', money(_tax)),
            const SizedBox(height: 4),
            _row('Total', money(_total), big: true),
            const SizedBox(height: 12),
            SizedBox(height: 52, child: ElevatedButton(
              onPressed: cart.isEmpty ? null : _pay,
              style: ElevatedButton.styleFrom(backgroundColor: C.brand, foregroundColor: C.ink, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: Text('Pay ${money(_total)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            )),
          ]),
        ),
      ]),
    );
  }

  Widget _row(String k, String v, {bool big = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: TextStyle(fontWeight: big ? FontWeight.w900 : FontWeight.w700, fontSize: big ? 18 : 13, color: big ? C.ink : C.textMute)),
          Text(v, style: TextStyle(fontWeight: big ? FontWeight.w900 : FontWeight.w700, fontSize: big ? 18 : 13, color: big ? C.ink : C.textMute)),
        ]),
      );
}

class _ItemTile extends StatelessWidget {
  final MenuItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _ItemTile({required this.item, required this.onTap, required this.onLongPress});
  @override
  Widget build(BuildContext context) {
    final dim = !item.sellable;
    return InkWell(
      onTap: dim ? null : onTap,
      onLongPress: onLongPress, // long-press to toggle 86 (sold out)
      child: Opacity(
        opacity: dim ? .45 : 1,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.icon, style: const TextStyle(fontSize: 30)),
            const Spacer(),
            Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: C.ink)),
            const SizedBox(height: 4),
            Row(children: [
              Text(money(item.price), style: const TextStyle(fontWeight: FontWeight.w900, color: C.ink)),
              const Spacer(),
              if (dim) const Text('86', style: TextStyle(fontWeight: FontWeight.w900, color: C.red, fontSize: 11)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  final CartLine line;
  final VoidCallback onChanged, onRemove;
  const _CartRow({required this.line, required this.onChanged, required this.onRemove});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.border)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(line.item.name, style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink)),
          if (line.modText.isNotEmpty) Text(line.modText, style: const TextStyle(fontSize: 11, color: C.textMute, fontWeight: FontWeight.w600)),
        ])),
        _qtyBtn(Icons.remove, () { if (line.qty > 1) { line.qty--; onChanged(); } else { onRemove(); } }),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('${line.qty}', style: const TextStyle(fontWeight: FontWeight.w900, color: C.ink))),
        _qtyBtn(Icons.add, () { line.qty++; onChanged(); }),
        SizedBox(width: 64, child: Text(money(line.lineTotal), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900, color: C.ink))),
      ]),
    );
  }

  Widget _qtyBtn(IconData i, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Container(width: 30, height: 30, decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: C.border)), child: Icon(i, size: 16, color: C.ink)),
      );
}

// ---------------------------------------------------------------------------
// Customize sheet — size/sugar/ice/toppings (mirrors the React modifier flow).
// ---------------------------------------------------------------------------
class CustomizeSheet extends StatefulWidget {
  final MenuItem item;
  final MenuRepo repo;
  const CustomizeSheet({super.key, required this.item, required this.repo});
  @override
  State<CustomizeSheet> createState() => _CustomizeSheetState();
}

class _CustomizeSheetState extends State<CustomizeSheet> {
  final Map<String, Set<String>> _sel = {}; // groupId -> chosen option ids
  int _qty = 1;

  bool _isSingle(String gname) => gname == 'Size' || gname == 'Sugar' || gname == 'Ice';

  void _toggle(ModGroup g, ModOption o) {
    final set = _sel.putIfAbsent(g.id, () => {});
    setState(() {
      if (_isSingle(g.name)) { set..clear()..add(o.id); }
      else { set.contains(o.id) ? set.remove(o.id) : set.add(o.id); }
    });
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final groups = it.modifierGroupIds.map((id) => widget.repo.groups[id]).whereType<ModGroup>().where((g) => g.options.isNotEmpty).toList();
    final chosen = <ModOption>[];
    for (final g in groups) {
      for (final id in (_sel[g.id] ?? {})) {
        final o = g.options.firstWhere((x) => x.id == id, orElse: () => ModOption('', '', 0));
        if (o.id.isNotEmpty) chosen.add(o);
      }
    }
    final unit = it.price + chosen.fold(0.0, (s, m) => s + m.priceDelta);
    return DraggableScrollableSheet(
      initialChildSize: .8, maxChildSize: .95, minChildSize: .5, expand: false,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(color: C.panel, borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Row(children: [
            Text(it.icon, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 10),
            Expanded(child: Text(it.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: C.ink))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ])),
          Expanded(child: ListView(controller: sc, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            for (final g in groups) ...[
              Padding(padding: const EdgeInsets.only(top: 12, bottom: 6), child: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w900, color: C.ink))),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final o in g.options)
                  InkWell(
                    onTap: () => _toggle(g, o),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: (_sel[g.id]?.contains(o.id) ?? false) ? C.brand : C.panel,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: (_sel[g.id]?.contains(o.id) ?? false) ? C.brandDark : C.border)),
                      child: Text('${o.name}${o.priceDelta > 0 ? ' +${money(o.priceDelta)}' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink, fontSize: 13)),
                    ),
                  ),
              ]),
            ],
            const SizedBox(height: 16),
          ])),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.border))),
            child: Row(children: [
              _qbtn(Icons.remove, () => setState(() { if (_qty > 1) _qty--; })),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('$_qty', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
              _qbtn(Icons.add, () => setState(() => _qty++)),
              const SizedBox(width: 12),
              Expanded(child: SizedBox(height: 50, child: ElevatedButton(
                onPressed: () => Navigator.pop(context, CartLine(it, qty: _qty, mods: chosen)),
                style: ElevatedButton.styleFrom(backgroundColor: C.brand, foregroundColor: C.ink, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: Text('Add · ${money(unit * _qty)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _qbtn(IconData i, VoidCallback onTap) => InkWell(onTap: onTap, child: Container(width: 38, height: 38, decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.border)), child: Icon(i, color: C.ink)));
}

// ---------------------------------------------------------------------------
// Payment sheet — cash (change) / card (real PAX terminal). Mirrors the React PaymentModal.
// ---------------------------------------------------------------------------
class PaymentSheet extends StatefulWidget {
  final double total;
  final Future<bool> Function(String method, double received, PaxResult? card) onComplete;
  const PaymentSheet({super.key, required this.total, required this.onComplete});
  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<PaymentSheet> {
  String _method = 'cash';
  final _received = TextEditingController();
  bool _busy = false;
  String? _cardStatus; // live terminal status / error
  // Terminal config (loaded from settings; empty IP → simulated card).
  String _termIp = '';
  int _termPort = 10009;

  @override
  void initState() {
    super.initState();
    _loadTerminal();
  }

  Future<void> _loadTerminal() async {
    final s = await Api.instance.getSettings();
    if (!mounted) return;
    final pay = Map<String, dynamic>.from(Map<String, dynamic>.from(s['settings'] ?? {})['payment'] ?? {});
    setState(() {
      _termIp = (pay['ip'] ?? '').toString();
      _termPort = int.tryParse('${pay['port'] ?? 10009}') ?? 10009;
    });
  }

  double get _recv => double.tryParse(_received.text) ?? 0;
  double get _change => _recv - widget.total;

  Future<void> _done() async {
    if (_method == 'cash') {
      setState(() => _busy = true);
      final ok = await widget.onComplete('cash', _recv, null);
      if (!mounted) return;
      setState(() => _busy = false);
      if (ok) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment failed'), backgroundColor: C.red));
      }
      return;
    }
    // Card → drive the PAX terminal (or simulated approval if no IP set).
    setState(() { _busy = true; _cardStatus = _termIp.isEmpty ? 'Charging card (test)…' : 'Waiting for card on terminal…'; });
    try {
      final res = await Pax.sale(amount: widget.total, host: _termIp.isEmpty ? null : _termIp, port: _termPort);
      if (!mounted) return;
      if (!res.approved) {
        setState(() { _busy = false; _cardStatus = 'Declined${res.message.isNotEmpty ? ': ${res.message}' : ''}'; });
        return;
      }
      setState(() => _cardStatus = res.simulated ? 'Approved (test)' : 'Approved · ${res.cardType} ••${res.cardLast4}');
      final ok = await widget.onComplete('card', 0, res);
      if (!mounted) return;
      setState(() => _busy = false);
      if (ok) {
        Navigator.pop(context, true);
      } else {
        setState(() => _cardStatus = 'Card approved but saving the order failed');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _cardStatus = 'Terminal error: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final quick = <double>{widget.total, (widget.total / 5).ceil() * 5, (widget.total / 10).ceil() * 10, (widget.total / 20).ceil() * 20}
        .toList()..sort();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(color: C.panel, borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Text('Total ${money(widget.total)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: C.ink))),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _methodBtn('cash', 'Cash', Icons.payments)),
            const SizedBox(width: 10),
            Expanded(child: _methodBtn('card', 'Card', Icons.credit_card)),
          ]),
          if (_method == 'cash') ...[
            const SizedBox(height: 16),
            TextField(controller: _received, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: 'Cash received', prefixText: '\$ ', filled: true, fillColor: C.bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [for (final q in quick) ActionChip(label: Text(money(q)), onPressed: () => setState(() => _received.text = q.toStringAsFixed(2)))]),
            const SizedBox(height: 10),
            if (_recv > 0)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: _change >= 0 ? const Color(0x1F4ADE80) : C.redA, borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Change', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink)),
                  Text(money(_change.clamp(0, double.infinity)), style: TextStyle(fontWeight: FontWeight.w900, color: _change >= 0 ? C.green : C.red, fontSize: 18)),
                ]),
              ),
          ] else ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
              child: Row(children: [
                Icon(_termIp.isEmpty ? Icons.wifi_off : Icons.point_of_sale, color: _termIp.isEmpty ? C.textMute : C.kiosk, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  _cardStatus ?? (_termIp.isEmpty
                      ? 'No terminal IP set (Settings → Payment). Card will be a test approval.'
                      : 'PAX terminal $_termIp:$_termPort — tap Charge to send the sale.'),
                  style: const TextStyle(color: C.ink, fontWeight: FontWeight.w700, fontSize: 13))),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(height: 54, child: ElevatedButton(
            onPressed: _busy || (_method == 'cash' && _recv < widget.total) ? null : _done,
            style: ElevatedButton.styleFrom(backgroundColor: C.green, foregroundColor: const Color(0xFF06210F), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_method == 'card' ? 'Charge card' : 'Complete order', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          )),
        ]),
      ),
    );
  }

  Widget _methodBtn(String id, String label, IconData icon) => InkWell(
        onTap: () => setState(() => _method = id),
        child: Container(
          height: 52,
          decoration: BoxDecoration(color: _method == id ? C.brand : C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: _method == id ? C.brandDark : C.border)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 18, color: C.ink), const SizedBox(width: 8), Text(label, style: const TextStyle(fontWeight: FontWeight.w900, color: C.ink))]),
        ),
      );
}
