import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'printer.dart';
import 'theme.dart';

/// Single source of truth for live online orders — polling + looping chime +
/// accept/reject/ready/complete. Mirrors OnlineOrdersProvider (React).
class OnlineOrdersController extends ChangeNotifier {
  /// The live controller for the foreground board, so an FCM push can refresh
  /// it immediately (instead of waiting for the 8s poll).
  static OnlineOrdersController? active;

  List<OnlineOrder> orders = [];
  List<OnlineOrder> queue = []; // NEW online orders awaiting accept (drives takeover)
  bool online = true;
  final _seen = <String>{};
  bool _first = true;
  Timer? _timer;
  final _player = AudioPlayer();
  bool _chiming = false;

  void start() {
    active = this;
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => refresh());
  }

  @override
  void dispose() {
    if (active == this) active = null;
    _timer?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    if (!Api.instance.isLoggedIn) return;
    final list = await Api.instance.fetchOnlineOrders();
    final active = list.where((o) => columnOf(o.status, o.source) != null).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    orders = active;
    final fresh = active.where((o) => columnOf(o.status, o.source) == 'new').toList();
    var hasNew = false;
    for (final o in fresh) {
      if (!_seen.contains(o.id)) { _seen.add(o.id); if (!_first) hasNew = true; }
    }
    _first = false;
    queue = fresh;
    if (queue.isEmpty) _stopChime();
    if (hasNew) _startChime();
    notifyListeners();
  }

  Future<void> _startChime() async {
    if (_chiming) return;
    _chiming = true;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('sounds/order_alert.wav'));
    } catch (_) {}
  }

  Future<void> stopChime() => _stopChime();
  Future<void> _stopChime() async {
    _chiming = false;
    try { await _player.stop(); } catch (_) {}
  }

  Future<Map<String, dynamic>> accept(OnlineOrder o, int eta) async {
    final r = await Api.instance.accept(o.id, eta); // backend captures the card here
    if (r['ok'] != true) return {'ok': false, 'error': r['error'] ?? 'Confirm failed'};
    try {
      await printKitchenTicket(
        source: o.source, number: (o.number ?? o.id), type: o.orderType,
        customer: o.customer, phone: o.customerPhone,
        items: o.items.map((it) => {'qty': it.quantity, 'name': it.name, 'mods': it.modifiers, 'notes': it.notes}).toList(),
      );
    } catch (_) {}
    try { await Api.instance.markPrinted(o.id); } catch (_) {}
    await refresh();
    return {'ok': true};
  }

  Future<Map<String, dynamic>> reject(OnlineOrder o, String reason) async {
    final r = await Api.instance.reject(o.id, reason); // backend voids the authorization
    if (r['ok'] != true) return {'ok': false, 'error': r['error'] ?? 'Reject failed'};
    await refresh();
    return {'ok': true};
  }

  Future<void> markReady(OnlineOrder o) async { await Api.instance.markReady(o.id); await refresh(); }
  Future<void> complete(OnlineOrder o) async { await Api.instance.setStatus(o.id, 'completed'); await refresh(); }
}

String _minsAgo(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final m = DateTime.now().difference(t).inMinutes;
  return m < 1 ? 'just now' : '${m}m ago';
}

// ===========================================================================
// ORDERS BOARD — NEW / PREPARING / READY kanban (mirrors React OrdersBoard).
// ===========================================================================
const _colDefs = [
  (key: 'new', title: 'New', icon: Icons.notifications_active, tone: C.online),
  (key: 'preparing', title: 'Preparing', icon: Icons.local_fire_department, tone: C.brandDark),
  (key: 'ready', title: 'Ready', icon: Icons.shopping_bag, tone: C.green),
];

class OrdersBoard extends StatefulWidget {
  final OnlineOrdersController ctrl;
  const OrdersBoard({super.key, required this.ctrl});
  @override
  State<OrdersBoard> createState() => _OrdersBoardState();
}

class _OrdersBoardState extends State<OrdersBoard> {
  String _sel = 'new'; // selected column on narrow screens

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    final cols = {'new': <OnlineOrder>[], 'preparing': <OnlineOrder>[], 'ready': <OnlineOrder>[]};
    for (final o in ctrl.orders) {
      final c = columnOf(o.status, o.source);
      if (c != null) cols[c]!.add(o);
    }
    final wide = MediaQuery.of(context).size.width >= 720;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Online Orders', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: C.ink)),
              Text('${Api.instance.storeName} · live board', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.textMute)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: ctrl.online ? const Color(0x1F4ADE80) : C.redA, borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(ctrl.online ? Icons.wifi : Icons.wifi_off, size: 13, color: ctrl.online ? C.green : C.red),
              const SizedBox(width: 5),
              Text(ctrl.online ? 'Live' : 'Offline', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: ctrl.online ? C.green : C.red)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Expanded(child: wide ? _wide(cols, ctrl) : _narrow(cols, ctrl)),
      ]),
    );
  }

  // Tablet/desktop: three columns side by side.
  Widget _wide(Map<String, List<OnlineOrder>> cols, OnlineOrdersController ctrl) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final d in _colDefs) ...[
            Expanded(child: _Column(def: d, list: cols[d.key]!, ctrl: ctrl)),
            if (d.key != 'ready') const SizedBox(width: 14),
          ]
        ],
      );

  // Phone: a segmented selector + one full-width column (readable cards).
  Widget _narrow(Map<String, List<OnlineOrder>> cols, OnlineOrdersController ctrl) {
    final list = cols[_sel]!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        for (final d in _colDefs) ...[
          Expanded(child: InkWell(
            onTap: () => setState(() => _sel = d.key),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _sel == d.key ? d.tone : C.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _sel == d.key ? d.tone : C.border)),
              child: Column(children: [
                Text(d.title.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: _sel == d.key ? Colors.white : d.tone)),
                Text('${cols[d.key]!.length}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: _sel == d.key ? Colors.white : C.ink)),
              ]),
            ),
          )),
          if (d.key != 'ready') const SizedBox(width: 8),
        ]
      ]),
      const SizedBox(height: 12),
      Expanded(
        child: list.isEmpty
            ? const Center(child: Text('No orders here', style: TextStyle(color: C.textMute, fontWeight: FontWeight.w800)))
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _BoardCard(o: list[i], col: _sel, ctrl: ctrl),
              ),
      ),
    ]);
  }
}

class _Column extends StatelessWidget {
  final ({String key, String title, IconData icon, Color tone}) def;
  final List<OnlineOrder> list;
  final OnlineOrdersController ctrl;
  const _Column({required this.def, required this.list, required this.ctrl});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(children: [
            Icon(def.icon, size: 16, color: def.tone),
            const SizedBox(width: 8),
            Text(def.title.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: def.tone, letterSpacing: .4)),
            const Spacer(),
            Container(
              constraints: const BoxConstraints(minWidth: 24),
              height: 24, padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(color: def.tone, borderRadius: BorderRadius.circular(999)),
              alignment: Alignment.center,
              child: Text('${list.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
            ),
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('—', style: TextStyle(color: Color(0xFFB6BCC6), fontWeight: FontWeight.w800)))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _BoardCard(o: list[i], col: def.key, ctrl: ctrl),
                ),
        ),
      ]),
    );
  }
}

class _BoardCard extends StatelessWidget {
  final OnlineOrder o;
  final String col;
  final OnlineOrdersController ctrl;
  const _BoardCard({required this.o, required this.col, required this.ctrl});
  @override
  Widget build(BuildContext context) {
    final sm = sourceMeta(o.source);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _Badge(label: sm.label, color: sm.color),
          const SizedBox(width: 8),
          Text('#${o.number ?? o.id}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: C.ink)),
          const Spacer(),
          Text(_minsAgo(o.createdAt), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.textMute)),
        ]),
        const SizedBox(height: 8),
        for (final it in o.items.take(3))
          Text('${it.quantity}× ${it.name}', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.ink)),
        if (o.items.length > 3)
          Text('+${o.items.length - 3} more', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.textMute)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('${o.customer} · ${o.orderType.toLowerCase()}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.textMute))),
          Text(money(o.total), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: C.ink)),
        ]),
        if (col == 'new')
          const Padding(padding: EdgeInsets.only(top: 8), child: Row(children: [
            Icon(Icons.notifications_active, size: 12, color: C.online),
            SizedBox(width: 5),
            Text('Awaiting confirmation', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: C.online)),
          ])),
        if (col == 'preparing')
          Padding(padding: const EdgeInsets.only(top: 10), child: _SmallBtn(
            label: 'Mark ready', icon: Icons.shopping_bag, fg: C.brandDark, bg: const Color(0x1AFFCC00),
            onTap: () => ctrl.markReady(o))),
        if (col == 'ready')
          Padding(padding: const EdgeInsets.only(top: 10), child: _SmallBtn(
            label: 'Complete', icon: Icons.check_circle, fg: C.green, bg: const Color(0x1F4ADE80),
            onTap: () => ctrl.complete(o))),
      ]),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: .4)),
      );
}

class _SmallBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color fg, bg;
  final VoidCallback onTap;
  const _SmallBtn({required this.label, required this.icon, required this.fg, required this.bg, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          height: 38,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: fg)),
          alignment: Alignment.center,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: fg)),
          ]),
        ),
      );
}

// ===========================================================================
// NEW ORDER TAKEOVER — full-screen, unmissable (mirrors React NewOrderTakeover).
// ===========================================================================
class NewOrderTakeover extends StatefulWidget {
  final OnlineOrder order;
  final OnlineOrdersController ctrl;
  const NewOrderTakeover({super.key, required this.order, required this.ctrl});
  @override
  State<NewOrderTakeover> createState() => _NewOrderTakeoverState();
}

class _NewOrderTakeoverState extends State<NewOrderTakeover> {
  String _step = 'main'; // main | prep | reason
  bool _busy = false;
  String? _err;
  final _custom = TextEditingController();
  static const _prep = [10, 15, 20, 30, 45];
  static const _reasons = ['Too busy', 'Item unavailable', 'Closing soon', 'Other'];

  Future<void> _accept(int eta) async {
    setState(() { _busy = true; _err = null; });
    final r = await widget.ctrl.accept(widget.order, eta);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['ok'] != true) setState(() { _err = r['error']?.toString(); _step = 'main'; });
  }

  Future<void> _reject(String reason) async {
    setState(() { _busy = true; _err = null; });
    final r = await widget.ctrl.reject(widget.order, reason);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['ok'] != true) setState(() { _err = r['error']?.toString(); _step = 'main'; });
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final sm = sourceMeta(o.source);
    return Container(
      color: const Color(0xB8080A0E),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Material(
          color: C.panel,
          borderRadius: BorderRadius.circular(20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(color: sm.color, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
                child: Row(children: [
                  Text('${sm.label} ORDER', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: .5)),
                  const Spacer(),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.schedule, size: 14, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(_minsAgo(o.createdAt), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                  ]),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Row(children: [
                  Text('#${o.number ?? o.id}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: C.ink)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(999), border: Border.all(color: C.border)),
                    child: Text(o.orderType.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: C.ink)),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Row(children: [
                  Text(o.customer, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: C.ink)),
                  if (o.customerPhone.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.phone, size: 13, color: C.textMute),
                    const SizedBox(width: 4),
                    Text(o.customerPhone, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: C.textMute)),
                  ],
                ]),
              ),
              // items
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.border), bottom: BorderSide(color: C.border))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final it in o.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 38, child: Text('${it.quantity}×', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: C.brand))),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(it.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: C.ink)),
                          if (it.modifiers.isNotEmpty)
                            Text(it.modifiers.join(', '), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.textMute)),
                          if (it.notes.isNotEmpty)
                            Text('“${it.notes}”', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.online)),
                        ])),
                      ]),
                    ),
                ]),
              ),
              // totals
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(children: [
                  _totRow('Subtotal', money(o.subtotal)),
                  if (o.tax > 0) _totRow('Tax', money(o.tax)),
                  if (o.tip > 0) _totRow('Tip', money(o.tip)),
                  _totRow('Total', money(o.total), big: true),
                  Align(alignment: Alignment.centerLeft, child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(o.isCard ? '💳 Card on hold — charged on accept' : '🏪 Pay at store',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: C.textMute)),
                  )),
                ]),
              ),
              if (_err != null)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: C.redA, borderRadius: BorderRadius.circular(10)),
                  child: Text(_err!, style: const TextStyle(color: C.red, fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              Padding(padding: const EdgeInsets.all(20), child: _footer(o)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _totRow(String k, String v, {bool big = false}) => Padding(
        padding: EdgeInsets.symmetric(vertical: big ? 4 : 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: TextStyle(fontWeight: big ? FontWeight.w900 : FontWeight.w700, fontSize: big ? 18 : 13, color: big ? C.ink : C.textMute)),
          Text(v, style: TextStyle(fontWeight: big ? FontWeight.w900 : FontWeight.w700, fontSize: big ? 18 : 13, color: big ? C.ink : C.textMute)),
        ]),
      );

  Widget _footer(OnlineOrder o) {
    if (_step == 'main') {
      return Row(children: [
        Expanded(child: _bigBtn('Reject', Icons.cancel, C.red, C.redA, () { widget.ctrl.stopChime(); setState(() => _step = 'reason'); }, outline: true)),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: _bigBtn('Accept', Icons.check_circle, const Color(0xFF06210F), C.green,
            () { widget.ctrl.stopChime(); setState(() => _step = 'prep'); })),
      ]);
    }
    if (_step == 'prep') {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _back(),
        const Padding(padding: EdgeInsets.only(bottom: 14), child: Text('Prep time — when will it be ready?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: C.ink))),
        Row(children: [
          for (final m in _prep) ...[
            Expanded(child: InkWell(
              onTap: _busy ? null : () => _accept(m),
              child: Container(
                height: 64, decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border, width: 2)),
                alignment: Alignment.center,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('$m', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: C.ink)),
                  const Text('min', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: C.textMute)),
                ]),
              ),
            )),
            if (m != _prep.last) const SizedBox(width: 10),
          ]
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: TextField(controller: _custom, keyboardType: TextInputType.number,
              decoration: InputDecoration(hintText: 'Custom min', filled: true, fillColor: const Color(0xFFF3F4F6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _busy ? null : () { final v = int.tryParse(_custom.text); if (v != null) _accept(v); },
            style: ElevatedButton.styleFrom(backgroundColor: C.green, foregroundColor: const Color(0xFF06210F), elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
            child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Confirm', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ]),
      ]);
    }
    // reason
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _back(),
      const Padding(padding: EdgeInsets.only(bottom: 14), child: Text('Reject reason — the customer is told this', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: C.ink))),
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 3,
        children: [
          for (final r in _reasons) InkWell(
            onTap: _busy ? null : () => _reject(r),
            child: Container(
              decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border, width: 2)),
              alignment: Alignment.center,
              child: Text(r, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: C.ink)),
            ),
          ),
        ],
      ),
      const Padding(padding: EdgeInsets.only(top: 14), child: Text('Rejecting voids the authorization — the customer is NOT charged.',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.textMute), textAlign: TextAlign.center)),
    ]);
  }

  Widget _back() => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _step = 'main'),
          icon: const Icon(Icons.chevron_left, size: 16, color: C.textMute),
          label: const Text('Back', style: TextStyle(color: C.textMute, fontWeight: FontWeight.w800, fontSize: 13)),
        ),
      );

  Widget _bigBtn(String label, IconData icon, Color fg, Color bg, VoidCallback onTap, {bool outline = false}) => SizedBox(
        height: 58,
        child: outline
            ? OutlinedButton.icon(
                onPressed: _busy ? null : onTap,
                style: OutlinedButton.styleFrom(foregroundColor: fg, backgroundColor: bg, side: const BorderSide(color: C.red, width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                icon: Icon(icon, size: 20), label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)))
            : ElevatedButton.icon(
                onPressed: _busy ? null : onTap,
                style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: fg, elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                icon: Icon(icon, size: 22), label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20))),
      );
}
