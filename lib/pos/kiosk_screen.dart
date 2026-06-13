import 'package:flutter/material.dart';
import '../api.dart';
import '../menu.dart' hide CartLine;
import '../menu_sync.dart';
import '../pax.dart';
import '../screens/pin_lock.dart';
import '../ui/pos_theme.dart';
import '../ui/pos_widgets.dart';
import 'default_menu.dart';
import 'kiosk_setup.dart';
import 'order_models.dart';
import 'order_view.dart' show CustomizeSheet;

/// Kiosk — faithful port of React KioskOrderView. Customer self-order, large
/// tiles, portrait + landscape layouts, tip + PAX card payment, "Order received"
/// screen. Hidden admin: tap top-left 5× → Manager PIN → exit kiosk.
/// Paid kiosk orders post to the cloud (source Kiosk) → appear on the POS board
/// (auto-accepted + auto-printed there).
class KioskScreen extends StatefulWidget {
  final VoidCallback onExit;
  const KioskScreen({super.key, required this.onExit});
  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> {
  final repo = MenuRepo();
  bool _loading = true;
  late Order _order;
  String _activeCat = 'all';
  Order? _done;
  int _tapCount = 0;
  DateTime _tapAt = DateTime.fromMillisecondsSinceEpoch(0);
  late final MenuSyncListener _menuSync;

  @override
  void initState() {
    super.initState();
    _load();
    // Live sync: refresh the kiosk menu the moment it changes anywhere.
    _menuSync = MenuSyncListener(_reloadMenu)..start();
  }

  @override
  void dispose() {
    _menuSync.stop();
    super.dispose();
  }

  Future<void> _load() async {
    await OrderCounter.init();
    await repo.load();
    if (repo.items.isEmpty) { repo.categories = List.of(kDefaultCategories); repo.items = List.of(kDefaultMenu); }
    if (repo.taxRate > 0) ShopConfig.tax = repo.taxRate;
    if (!mounted) return;
    setState(() { _order = emptyOrder()..type = 'togo'; _loading = false; });
  }

  // Live menu reload (keeps offline-default fallback) — repaints in place.
  Future<void> _reloadMenu() async {
    await repo.load();
    if (repo.items.isEmpty) { repo.categories = List.of(kDefaultCategories); repo.items = List.of(kDefaultMenu); }
    if (repo.taxRate > 0) ShopConfig.tax = repo.taxRate;
    if (mounted) setState(() {});
  }

  void _secretTap() {
    final now = DateTime.now();
    if (now.difference(_tapAt).inSeconds > 3) _tapCount = 0;
    _tapCount++; _tapAt = now;
    if (_tapCount >= 5) { _tapCount = 0; _adminPin(); }
  }

  Future<void> _adminPin() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(fullscreenDialog: true,
      builder: (_) => PinLockScreen(title: 'Manager access', subtitle: 'Enter Manager PIN to open kiosk settings',
        managerOnly: true, onUnlock: (_) => Navigator.of(context).pop(true), onCancel: () => Navigator.of(context).pop(false))));
    if (ok == true && mounted) {
      // PIN now opens the full Kiosk Settings (kiosk PAX terminal, auto-handling,
      // hub pairing). It pops `true` when the manager taps Exit Kiosk Mode —
      // same exit path as the old confirm dialog.
      final exit = await Navigator.of(context).push<bool>(MaterialPageRoute(
          fullscreenDialog: true, builder: (_) => const KioskSettingsScreen()));
      if (exit == true) widget.onExit();
    }
  }

  List<MenuItem> get _visible => repo.items.where((m) =>
      m.category != 'topping' && m.sellable && (_activeCat == 'all' || m.category == _activeCat)).toList();

  Future<void> _select(MenuItem p) async {
    if (p.category == 'snack' || p.category == 'topping') {
      setState(() => _order.items.add(CartLine(id: 'L${DateTime.now().microsecondsSinceEpoch}',
          productId: p.id, name: p.name, emoji: p.icon, category: p.category, basePrice: p.price)));
      return;
    }
    final toppings = repo.items.where((m) => m.category == 'topping' && m.sellable).map((m) => Topping(m.id, m.name, m.price)).toList();
    final line = await showDialog<CartLine>(context: context, barrierColor: PT.c.overlay, builder: (_) => CustomizeSheet(product: p, toppings: toppings));
    if (line != null) setState(() => _order.items.add(line));
  }

  void _qty(CartLine l, int q) => setState(() { if (q <= 0) { _order.items.removeWhere((x) => x.id == l.id); } else { l.qty = q; } });

  Future<void> _pay() async {
    final res = await showDialog<Map<String, dynamic>>(context: context, barrierColor: PT.c.overlay,
        builder: (_) => _KioskPayment(order: _order));
    if (res == null || !mounted) return;
    final tip = (res['tip'] ?? 0.0) as double;
    // Post to cloud (source Kiosk) → POS board auto-accepts + prints.
    Api.instance.createKioskOrder(orderToApi(_order, paymentMethod: 'card', tip: tip)
      ..['customer'] = 'Walk-in'..['customerName'] = 'Walk-in');
    setState(() => _done = _order);
  }

  void _reset() => setState(() { _order = emptyOrder()..type = 'togo'; _activeCat = 'all'; _done = null; });

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    if (_loading) return Scaffold(backgroundColor: c.bg, body: Center(child: CircularProgressIndicator(color: c.primary)));
    if (_done != null) return _doneScreen(c);
    final portrait = MediaQuery.of(context).size.height >= MediaQuery.of(context).size.width;
    // Category bar is a HORIZONTAL top bar in BOTH orientations (like the online
    // order page). Cart stays at the bottom (portrait) or right (landscape).
    return Scaffold(backgroundColor: c.bg, body: SafeArea(child: Stack(children: [
      Column(children: [
        _catBar(c),
        Expanded(child: portrait
            ? Column(children: [Expanded(child: _menuArea(c)), _cart(c, portrait)])
            : Row(children: [Expanded(child: _menuArea(c)), _cart(c, portrait)])),
      ]),
      // hidden admin hotspot (top-left)
      Positioned(top: 0, left: 0, child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _secretTap,
          child: const SizedBox(width: 64, height: 64))),
    ])));
  }

  Widget _catBar(PosColors c) {
    final cats = [const MenuCategory('all', 'All', '🍱'), ...repo.categories.where((x) => x.id != 'topping')];
    return Container(
      decoration: BoxDecoration(color: c.panel, border: Border(bottom: BorderSide(color: c.border))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [for (final cat in cats) _catBtn(c, cat)]),
      ),
    );
  }

  Widget _catBtn(PosColors c, MenuCategory cat) {
    final active = _activeCat == cat.id;
    return GestureDetector(
      onTap: () => setState(() => _activeCat = cat.id),
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 18),
        decoration: BoxDecoration(color: active ? c.primary : c.card, borderRadius: BorderRadius.circular(999),
            border: Border.all(color: active ? c.primary : c.border),
            boxShadow: active ? [BoxShadow(color: c.primaryD, offset: const Offset(0, 3))] : null),
        child: Text(cat.name, // text only — no emoji icon
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: active ? c.bg : c.text)),
      ),
    );
  }

  Widget _menuArea(PosColors c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 10), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Order Now', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: c.text)),
          Text('Choose items, customize, add tip, then pay now.', style: TextStyle(fontSize: 13, color: c.textMute, fontWeight: FontWeight.w600)),
        ])),
        const BrandMark(size: 52, radius: 14),
      ])),
      Expanded(child: LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= 900 ? 2 : 1; // card NGANG giống online
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols, crossAxisSpacing: 14, mainAxisSpacing: 14, mainAxisExtent: 132),
          itemCount: _visible.length,
          itemBuilder: (_, i) => _tile(c, _visible[i]),
        );
      })),
    ]);
  }

  // Card NGANG giống trang order online: info trái, ẢNH VUÔNG phải chạm 3 cạnh,
  // bấm card → mở customize (Add nằm trong đó), KHÔNG nút +Add trên card.
  Widget _tile(PosColors c, MenuItem p) {
    final inCart = _order.items.any((i) => i.productId == p.id);
    final sold = !p.sellable;
    Widget photo() {
      final fallback = Container(
          decoration: BoxDecoration(gradient: gradientFor(p.name)),
          alignment: Alignment.center, child: Text(p.icon, style: const TextStyle(fontSize: 42)));
      return AspectRatio(aspectRatio: 1, child: p.imageUrl.isEmpty
          ? fallback
          : Image.network(p.imageUrl, fit: BoxFit.cover, errorBuilder: (ctx, e, st) => fallback));
    }
    return GestureDetector(
      onTap: sold ? null : () => _select(p),
      child: Opacity(opacity: sold ? .5 : 1, child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .05), blurRadius: 10, offset: const Offset(0, 3))]),
        clipBehavior: Clip.antiAlias,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: Color(0xFF14181F)))),
                if (p.popular) Padding(padding: const EdgeInsets.only(left: 6), child: _badge('HOT', const Color(0xFFFB7185), Colors.white)),
                if (inCart) Padding(padding: const EdgeInsets.only(left: 6), child: _badge('Added', const Color(0xFF16A34A), Colors.white)),
              ]),
              if (p.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5),
                  child: Text(p.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B7280), height: 1.45))),
              const Spacer(),
              Text(sold ? 'Sold out' : money(p.price),
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: sold ? const Color(0xFFDC2626) : const Color(0xFF14181F))),
            ]))),
          photo(), // ảnh vuông sát phải, góc phải bo theo card (clip), cạnh trái thẳng
        ]),
      )),
    );
  }

  Widget _badge(String t, Color bg, Color fg) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(t, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w900)));

  Widget _cart(PosColors c, bool portrait) {
    final t = _order.totals;
    return Container(
      width: portrait ? null : 340,
      height: portrait ? 280 : null,
      decoration: BoxDecoration(color: c.panel, border: Border(
          left: portrait ? BorderSide.none : BorderSide(color: c.border),
          top: portrait ? BorderSide(color: c.border) : BorderSide.none)),
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Align(alignment: Alignment.centerLeft, child: Text('Your Order #${_order.number}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: c.text)))),
        Expanded(child: _order.items.isEmpty
            ? Center(child: Text('Tap a menu item to start.', style: TextStyle(color: c.textDim, fontWeight: FontWeight.w700)))
            : ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [for (final l in _order.items) _cartItem(c, l)])),
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))), child: Column(children: [
          _subRow(c, 'Subtotal', money(t.sub), false),
          _subRow(c, 'Tax', money(t.tax), false),
          _subRow(c, 'Total', money(t.total), true),
          const SizedBox(height: 12),
          PButton(const Text('Pay Now'), size: PBtnSize.lg, expand: true, onPressed: _order.items.isEmpty ? null : _pay),
        ])),
      ]),
    );
  }

  Widget _cartItem(PosColors c, CartLine l) => Container(
        margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.name, style: TextStyle(fontWeight: FontWeight.w900, color: c.text)),
            if (!l.isSimple) Text('${l.size == 'L' ? 'Large' : 'Reg'} · ${l.sugar}% sugar · ${l.ice}% ice', style: TextStyle(fontSize: 11, color: c.textMute, fontWeight: FontWeight.w700)),
            if (l.toppings.isNotEmpty) Text('+ ${l.toppings.map((t) => t.name).join(', ')}', style: TextStyle(fontSize: 11, color: c.primary, fontWeight: FontWeight.w700)),
          ])),
          Row(children: [
            _qbtn(c, '−', () => _qty(l, l.qty - 1)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('${l.qty}', style: TextStyle(fontWeight: FontWeight.w900, color: c.text))),
            _qbtn(c, '+', () => _qty(l, l.qty + 1)),
          ]),
          const SizedBox(width: 8),
          Text(money(l.lineTotal), style: TextStyle(fontWeight: FontWeight.w900, color: c.text)),
        ]),
      );

  Widget _qbtn(PosColors c, String s, VoidCallback onTap) => GestureDetector(onTap: onTap,
      child: Container(width: 28, height: 28, alignment: Alignment.center,
          decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
          child: Text(s, style: TextStyle(color: c.bg, fontWeight: FontWeight.w900, fontSize: 16))));

  Widget _subRow(PosColors c, String k, String v, bool big) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: TextStyle(fontWeight: big ? FontWeight.w900 : FontWeight.w700, fontSize: big ? 18 : 14, color: big ? c.text : c.textMute)),
          Text(v, style: TextStyle(fontWeight: big ? FontWeight.w900 : FontWeight.w700, fontSize: big ? 18 : 14, color: big ? c.primary : c.textMute)),
        ]),
      );

  Widget _doneScreen(PosColors c) {
    final o = _done!;
    return Scaffold(backgroundColor: c.bg, body: Center(child: Container(
      width: 420, padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(24), border: Border.all(color: c.border)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 80, height: 80, alignment: Alignment.center,
            decoration: BoxDecoration(color: c.cyan, shape: BoxShape.circle, boxShadow: [BoxShadow(color: c.cyanD, offset: const Offset(0, 5))]),
            child: const Text('✓', style: TextStyle(fontSize: 44, color: Colors.white, fontWeight: FontWeight.w900))),
        const SizedBox(height: 18),
        Text('Order received', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: c.text)),
        Text('#${o.number}', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: c.primary)),
        const SizedBox(height: 8),
        Text('Your ticket was sent to the counter.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.textMute, fontWeight: FontWeight.w700)),
        const SizedBox(height: 24),
        PButton(const Text('New Order'), size: PBtnSize.lg, onPressed: _reset),
      ]),
    )));
  }
}

// === Kiosk payment (tip + PAX) ===
class _KioskPayment extends StatefulWidget {
  final Order order;
  const _KioskPayment({required this.order});
  @override
  State<_KioskPayment> createState() => _KioskPaymentState();
}

class _KioskPaymentState extends State<_KioskPayment> {
  final List<int> _tips = const [15, 18, 20, 25];
  double _tip = 0;
  final _custom = TextEditingController();
  bool _started = false, _busy = false;
  PaxResult? _result;
  String _termMode = 'tcp', _termIp = '', _termSerial = '';
  int _termPort = 10009, _termTimeout = 60000;

  @override
  void initState() {
    super.initState();
    Api.instance.getSettings().then((s) {
      final settings = Map<String, dynamic>.from(s['settings'] ?? {});
      final pay = Map<String, dynamic>.from(settings['payment'] ?? {});
      // Kiosk Setup can point Pay Now at its OWN PAX terminal; when disabled the
      // kiosk keeps using the POS Payment Settings terminal (previous behavior).
      final kioskPax = Map<String, dynamic>.from(Map<String, dynamic>.from(settings['kiosk'] ?? {})['kioskPax'] ?? {});
      final src = kioskPax['enabled'] == true ? kioskPax : pay;
      if (mounted) {
        setState(() {
          _termMode = (src['connectionMode'] ?? 'tcp').toString();
          _termIp = (src['ip'] ?? '').toString();
          _termPort = int.tryParse('${src['port'] ?? 10009}') ?? 10009;
          _termSerial = (src['terminalSerial'] ?? '').toString();
          _termTimeout = int.tryParse('${src['timeoutMs'] ?? 60000}') ?? 60000;
        });
      }
    });
  }

  double get _tipAmount => _custom.text.isNotEmpty ? (double.tryParse(_custom.text) ?? 0) : _tip;

  Future<void> _send() async {
    setState(() { _started = true; _busy = true; _result = null; });
    try {
      final r = await Pax.sale(amount: widget.order.totals.total + _tipAmount, connectionMode: _termMode,
          host: _termIp.isEmpty ? null : _termIp, port: _termPort, timeout: _termTimeout,
          terminalSerial: _termSerial, refNum: 'K${widget.order.number}');
      if (!mounted) return;
      setState(() { _busy = false; _result = r; });
    } catch (_) { if (mounted) setState(() { _busy = false; _result = PaxResult(approved: false, message: 'Terminal error'); }); }
  }

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    final t = widget.order.totals;
    final approved = _result?.approved == true;
    return Dialog(backgroundColor: Colors.transparent, insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560),
        child: Container(padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(18)),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Pay Now', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: c.text)),
            Text('Order #${widget.order.number}', style: TextStyle(fontSize: 13, color: c.textMute, fontWeight: FontWeight.w800)),
            Container(margin: const EdgeInsets.symmetric(vertical: 14), padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Order total', style: TextStyle(fontWeight: FontWeight.w800, color: c.text)),
                  Text(money(t.total), style: TextStyle(fontSize: 30, color: c.primary, fontWeight: FontWeight.w900)),
                ])),
            if (!_started) ...[
              Text('ADD TIP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: c.textMute, letterSpacing: 1)),
              const SizedBox(height: 8),
              Row(children: [for (final p in _tips) ...[Expanded(child: GestureDetector(
                onTap: () => setState(() { _custom.clear(); _tip = (t.total * p / 100); }),
                child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(vertical: 14), alignment: Alignment.center,
                    decoration: BoxDecoration(color: (_custom.text.isEmpty && _tip == (t.total * p / 100)) ? c.primary : c.card, borderRadius: BorderRadius.circular(12)),
                    child: Column(children: [Text('$p%', style: TextStyle(fontWeight: FontWeight.w900, color: (_custom.text.isEmpty && _tip == (t.total * p / 100)) ? c.bg : c.text)),
                      Text(money(t.total * p / 100), style: TextStyle(fontSize: 11, color: (_custom.text.isEmpty && _tip == (t.total * p / 100)) ? c.bg : c.textMute))])),
              ))]]),
              const SizedBox(height: 10),
              PField(label: 'Custom tip amount', child: PInput(controller: _custom, hintText: '0.00', keyboardType: TextInputType.number, onChanged: (_) => setState(() => _tip = 0))),
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Total with tip', style: TextStyle(fontWeight: FontWeight.w800, color: c.text)),
                    Text(money(t.total + _tipAmount), style: TextStyle(fontWeight: FontWeight.w900, color: c.text)),
                  ])),
              const SizedBox(height: 12),
              PButton(const Text('Send to Terminal'), size: PBtnSize.lg, expand: true, onPressed: _send),
            ],
            if (_started && !approved) ...[
              if (_busy) Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(24), alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14)),
                  child: Column(children: [
                    Container(width: 64, height: 64, alignment: Alignment.center, decoration: BoxDecoration(color: c.yellow, shape: BoxShape.circle), child: const Text('💳', style: TextStyle(fontSize: 28))),
                    const SizedBox(height: 12),
                    Text('Waiting for card', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c.text)),
                    Text('Insert, tap, or swipe', style: TextStyle(fontSize: 12, color: c.textMute, fontWeight: FontWeight.w700)),
                  ])),
              if (!_busy && _result != null) ...[
                Container(margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: c.redA, borderRadius: BorderRadius.circular(12)),
                    child: Text('Declined: ${_result!.message}', style: TextStyle(color: c.red, fontWeight: FontWeight.w800))),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: PButton(const Text('Back'), variant: PBtnVariant.ghost, expand: true, onPressed: () => setState(() { _started = false; _result = null; }))),
                  const SizedBox(width: 10),
                  Expanded(child: PButton(const Text('Try Again'), expand: true, onPressed: _send)),
                ]),
              ],
            ],
            if (approved) ...[
              Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0x1F4ADE80), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Text('✓', style: TextStyle(fontSize: 30, color: c.green, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Payment approved', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c.text)),
                      Text('${_result!.cardType} ••${_result!.cardLast4} · ${money(t.total + _tipAmount)}', style: TextStyle(fontSize: 12, color: c.textMute, fontWeight: FontWeight.w800)),
                    ])),
                  ])),
              const SizedBox(height: 12),
              PButton(const Text('Show Order Number'), expand: true, onPressed: () => Navigator.of(context).pop({'method': 'card', 'tip': _tipAmount,
                'cardLast4': _result!.cardLast4, 'cardType': _result!.cardType, 'authCode': _result!.authCode})),
            ],
          ]),
        ),
      ),
    );
  }
}
