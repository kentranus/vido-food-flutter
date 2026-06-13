import 'package:flutter/material.dart';
import '../api.dart';
import '../hardware.dart';
import '../menu.dart' hide CartLine;
import '../menu_sync.dart';
import '../pax.dart';
import '../printer.dart';
import '../services/staff_store.dart';
import '../screens/pin_lock.dart';
import '../ui/pos_theme.dart';
import '../ui/pos_widgets.dart';
import 'gift_card_panel.dart';
import 'default_menu.dart';
import 'order_models.dart';

/// OrderView (Sell) — faithful port of React views/OrderView.jsx.
/// Layout: OrderRail (multi-order tabs) | Middle (type toggle + search + cash
/// drawer + category rail + product grid) | Cart. Dark theme.
/// 4a = layout + cart + multi-order + add/qty. Customize/Discount/Note/Payment
/// modals are wired in the following steps (4b/4c).
class OrderView extends StatefulWidget {
  final Staff staff;
  const OrderView({super.key, required this.staff});
  @override
  State<OrderView> createState() => _OrderViewState();
}

class _OrderViewState extends State<OrderView> {
  final repo = MenuRepo();
  bool _loading = true;
  List<Order> _orders = [];
  String? _activeId;
  String _activeCat = 'all';
  String _search = '';
  late final MenuSyncListener _menuSync;

  @override
  void initState() {
    super.initState();
    _load();
    // Live sync: reload the menu when it changes anywhere (edit / 86 / photo
    // approved) so POS stays in step with online, Kiosk and Manager.
    _menuSync = MenuSyncListener(_reloadMenu)..start();
  }

  @override
  void dispose() {
    _menuSync.stop();
    super.dispose();
  }

  // Re-fetch just the menu (keeps the offline-default fallback) and repaint.
  Future<void> _reloadMenu() async {
    await repo.load();
    if (repo.items.isEmpty) {
      repo.categories = List.of(kDefaultCategories);
      repo.items = List.of(kDefaultMenu);
    }
    if (mounted) setState(() {});
  }

  // Hardware config (cash drawer) loaded from settings.
  String _drawerMode = 'android_intent';
  String _drawerHost = '';

  Future<void> _load() async {
    await OrderCounter.init();
    await repo.load();
    // Offline-first fallback: if the cloud menu is empty, seed the defaults
    // (mirrors React shipping DEFAULT_MENU then overriding from cloud).
    if (repo.items.isEmpty) {
      repo.categories = List.of(kDefaultCategories);
      repo.items = List.of(kDefaultMenu);
    }
    if (repo.taxRate > 0) ShopConfig.tax = repo.taxRate;
    // Shop pricing + cash-drawer config from settings.
    final s = await Api.instance.getSettings();
    final settings = Map<String, dynamic>.from(s['settings'] ?? {});
    final shop = Map<String, dynamic>.from(settings['shop'] ?? {});
    final hw = Map<String, dynamic>.from(settings['hardware'] ?? {});
    if (shop['currencySymbol'] != null) ShopConfig.currencySymbol = shop['currencySymbol'].toString();
    if (shop['sizeLargeBonus'] != null) ShopConfig.sizeLargeBonus = (shop['sizeLargeBonus'] as num).toDouble();
    _drawerMode = (hw['cashDrawerMode'] ?? 'android_intent').toString();
    _drawerHost = (hw['printerHost'] ?? '').toString();
    if (!mounted) return;
    setState(() {
      _orders = [emptyOrder()];
      _activeId = _orders.first.id;
      _loading = false;
    });
  }

  Future<void> _kickDrawer() async {
    try {
      final r = await CashDrawer.open(mode: _drawerMode, printerHost: _drawerHost.isEmpty ? null : _drawerHost);
      if (r['skipped'] != true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cash drawer opened'), duration: Duration(seconds: 1)));
      }
    } catch (_) {}
  }

  Order get _active => _orders.firstWhere((o) => o.id == _activeId, orElse: () => _orders.first);

  void _updateActive(VoidCallback mutate) => setState(mutate);

  void _addOrder() {
    final o = emptyOrder();
    setState(() { _orders.insert(0, o); _activeId = o.id; });
  }

  void _addLine(CartLine l) { _updateActive(() => _active.items.add(l)); _pushDisplay(_active); }

  Future<void> _addProduct(MenuItem p) async {
    if (!p.sellable) return;
    // Snacks/toppings add directly; drinks open the customize sheet.
    if (p.category == 'snack' || p.category == 'topping') {
      _addLine(CartLine(
        id: 'L${DateTime.now().microsecondsSinceEpoch}',
        productId: p.id, name: p.name, emoji: p.icon, category: p.category, basePrice: p.price));
      return;
    }
    final toppingItems = repo.items
        .where((m) => m.category == 'topping' && m.sellable)
        .map((m) => Topping(m.id, m.name, m.price))
        .toList();
    final line = await showDialog<CartLine>(
      context: context, barrierColor: PT.c.overlay,
      builder: (_) => CustomizeSheet(product: p, toppings: toppingItems),
    );
    if (line != null) _addLine(line);
  }

  Future<void> _openDiscount() async {
    // Manager-only — gate with a manager PIN if the cashier isn't a manager.
    if (!widget.staff.isManager) {
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PinLockScreen(
          title: 'Manager PIN', subtitle: 'Required for discount', managerOnly: true,
          onUnlock: (_) => Navigator.of(context).pop(true),
          onCancel: () => Navigator.of(context).pop(false),
        ),
      ));
      if (ok != true) return;
    }
    if (!mounted) return;
    final res = await showDialog<({double value, String type})>(
      context: context, barrierColor: PT.c.overlay,
      builder: (_) => _DiscountDialog(order: _active),
    );
    if (res != null) _updateActive(() { _active.discount = res.value; _active.discountType = res.type; });
  }

  Future<void> _openNote() async {
    final note = await showDialog<String>(
      context: context, barrierColor: PT.c.overlay,
      builder: (_) => _NoteDialog(initial: _active.note),
    );
    if (note != null) _updateActive(() => _active.note = note);
  }

  void _pushDisplay(Order o, {String state = 'order'}) {
    final t = o.totals;
    CustomerDisplay.update({
      'state': state, 'shop': {'name': Api.instance.storeName}, 'orderNumber': o.number,
      'total': t.total, 'subtotal': t.sub, 'tax': t.tax,
      'items': o.items.map((l) => {'name': l.name, 'emoji': l.emoji, 'qty': l.qty, 'total': l.lineTotal,
        'details': l.isSimple ? '' : '${l.size == 'L' ? 'Large' : 'Reg'} · ${l.sugar}% sugar · ${l.ice}% ice'}).toList(),
    });
  }

  Future<void> _openPayment() async {
    final o = _active;
    _pushDisplay(o, state: 'payment'); // mirror amount due on the 2nd screen
    final pay = await showDialog<Map<String, dynamic>>(
      context: context, barrierColor: PT.c.overlay,
      builder: (_) => _PaymentSheet(order: o),
    );
    if (pay == null || !mounted) { _pushDisplay(o); return; }
    final tip = (pay['tip'] ?? 0.0) as double;
    // Cash with change → pop the drawer.
    if (pay['method'] == 'cash' && ((pay['changeGiven'] ?? 0.0) as double) > 0) _kickDrawer();
    CustomerDisplay.update({'state': 'done', 'total': o.totals.total + tip, 'shop': {'name': Api.instance.storeName}});
    // Persist the completed order to the cloud, print kitchen ticket.
    // Đơn có gift-card REDEEM (tiền thật đã trừ trên thẻ — full HOẶC partial)
    // → PHẢI await; lưu thất bại thì hoàn thẻ (idempotent theo giftRef), gỡ thẻ
    // khỏi đơn và giữ đơn mở để thử lại.
    if (o.giftApplied > 0 && o.giftCode != null && o.giftRef != null) {
      final saved = await Api.instance.createOrder(orderToApi(o,
          paymentMethod: pay['method']?.toString(), tip: tip,
          giftCode: o.giftCodeMasked, giftApplied: o.giftApplied));
      if (saved['ok'] == true) { o.serverNumber = saved['order']?['number']?.toString(); }
      if (saved['ok'] != true) {
        await Api.instance.giftRefund(o.giftCode!, o.giftRef!);
        if (!mounted) return;
        setState(o.clearGift);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save the order — the gift card was NOT charged. Please try again.')));
        _pushDisplay(o);
        return; // đơn vẫn mở, không in bill, không xoá khỏi danh sách
      }
    } else {
      // await để lấy số đơn CHUNG từ server (online); offline → trả nhanh, dùng số local.
      final saved = await Api.instance.createOrder(orderToApi(o, paymentMethod: pay['method']?.toString(), tip: tip));
      if (saved['ok'] == true) o.serverNumber = saved['order']?['number']?.toString();
    }
    try {
      await printKitchenTicket(
        source: 'POS', number: o.officialNumber, type: orderTypeOf(o.type).label,
        items: o.items.map((l) => {
          'qty': l.qty, 'name': l.name,
          'mods': [if (!l.isSimple) '${l.size == 'L' ? 'Large' : 'Reg'} · ${l.sugar}% sugar · ${l.ice}% ice', ...l.toppings.map((t) => t.name)],
          'notes': '',
        }).toList());
    } catch (_) {}
    if (!mounted) return;
    await showDialog(context: context, barrierColor: PT.c.overlay,
        builder: (_) => _ReceiptDialog(order: o, pay: pay, storeName: Api.instance.storeName));
    if (!mounted) return;
    // Order done → drop it and start fresh (mirrors React removeOrder on receipt close).
    setState(() {
      _orders.removeWhere((x) => x.id == o.id);
      if (_orders.isEmpty) _orders = [emptyOrder()];
      _activeId = _orders.first.id;
    });
  }

  void _setQty(CartLine l, int qty) {
    setState(() {
      if (qty <= 0) {
        _active.items.removeWhere((x) => x.id == l.id);
      } else {
        l.qty = qty;
      }
    });
    _pushDisplay(_active);
  }

  List<MenuItem> get _visible => repo.items.where((m) {
        if (m.category == 'topping') return false;
        if (_activeCat != 'all' && m.category != _activeCat) return false;
        if (_search.isNotEmpty && !m.name.toLowerCase().contains(_search.toLowerCase())) return false;
        return true;
      }).toList();

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    if (_loading) return Center(child: CircularProgressIndicator(color: c.primary));
    return Row(children: [
      _orderRail(c),
      Expanded(child: _middle(c)),
      _cart(c),
    ]);
  }

  // ----------------------------------------------------------- order rail (left)
  Widget _orderRail(PosColors c) {
    return Container(
      width: 140,
      decoration: BoxDecoration(color: c.panel, border: Border(right: BorderSide(color: c.border))),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('ORDERS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: c.textMute, letterSpacing: 0.5)),
            GestureDetector(
              onTap: _addOrder,
              child: Container(width: 26, height: 26, alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: c.primaryD, offset: const Offset(0, 2))]),
                  child: Icon(Icons.add, size: 14, color: c.bg)),
            ),
          ]),
        ),
        Expanded(child: ListView(padding: const EdgeInsets.all(10), children: [
          for (final o in _orders) _railItem(c, o),
        ])),
      ]),
    );
  }

  Widget _railItem(PosColors c, Order o) {
    final active = o.id == _activeId;
    final t = orderTypeOf(o.type);
    return GestureDetector(
      onTap: () => setState(() => _activeId = o.id),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? c.primary : c.card, borderRadius: BorderRadius.circular(12),
          boxShadow: active ? [BoxShadow(color: c.primaryD, offset: const Offset(0, 3))] : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${t.icon} #${o.number}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: active ? c.bg : c.text)),
          Padding(padding: const EdgeInsets.only(top: 4),
              child: Text('${o.items.length} items', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: active ? c.bg.withValues(alpha: 0.85) : c.textMute))),
          Padding(padding: const EdgeInsets.only(top: 4),
              child: Text(money(o.totals.total), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: active ? c.bg : c.text))),
        ]),
      ),
    );
  }

  // ----------------------------------------------------------- middle
  Widget _middle(PosColors c) {
    return Column(children: [
      // order bar: type toggle + search + cash drawer
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: c.panel, border: Border(bottom: BorderSide(color: c.border))),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final t in kOrderTypes) _typeBtn(c, t),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            constraints: const BoxConstraints(minWidth: 240),
            decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(999)),
            child: Row(children: [
              Icon(Icons.search, size: 14, color: c.textDim),
              const SizedBox(width: 8),
              Expanded(child: TextField(
                onChanged: (v) => setState(() => _search = v),
                style: TextStyle(color: c.text, fontWeight: FontWeight.w800, fontSize: 14),
                cursorColor: c.primary,
                decoration: InputDecoration(isDense: true, border: InputBorder.none,
                    hintText: 'Search menu...', hintStyle: TextStyle(color: c.textDim, fontWeight: FontWeight.w700)),
              )),
            ]),
          )),
          const SizedBox(width: 10),
          // Open Cash Drawer — wired to the hardware bridge (vido/cashdrawer).
          GestureDetector(
            onTap: _kickDrawer,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(color: c.primaryA, borderRadius: BorderRadius.circular(999), border: Border.all(color: c.primary)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.inventory_2_outlined, size: 14, color: c.primary),
                const SizedBox(width: 7),
                Text('Open Cash Drawer', style: TextStyle(color: c.primary, fontWeight: FontWeight.w900, fontSize: 13)),
              ]),
            ),
          ),
        ]),
      ),
      // category bar (horizontal, top) + product grid — matches online order page
      _catBarH(c),
      Expanded(child: _grid(c)),
    ]);
  }

  Widget _typeBtn(PosColors c, OrderType t) {
    final active = _active.type == t.id;
    return GestureDetector(
      onTap: () => _updateActive(() => _active.type = t.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active ? c.cyan : Colors.transparent, borderRadius: BorderRadius.circular(10),
          boxShadow: active ? [BoxShadow(color: c.cyanD, offset: const Offset(0, 3))] : null,
        ),
        child: Text('${t.icon} ${t.label}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: active ? c.bg : c.textMute)),
      ),
    );
  }

  // Horizontal category bar on top (text-only pills, no icon) — like the
  // online order page. Replaces the old vertical sidebar (_catRail).
  Widget _catBarH(PosColors c) {
    final cats = [const MenuCategory('all', 'All', '🍱'), ...repo.categories.where((x) => x.id != 'topping')];
    return Container(
      decoration: BoxDecoration(color: c.panel, border: Border(bottom: BorderSide(color: c.border))),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final cat in cats) _catChip(c, cat),
        ]),
      ),
    );
  }

  Widget _catChip(PosColors c, MenuCategory cat) {
    final active = _activeCat == cat.id;
    return GestureDetector(
      onTap: () => setState(() => _activeCat = cat.id),
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
        decoration: BoxDecoration(
          color: active ? c.primary : c.card, borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? c.primary : c.border),
          boxShadow: active ? [BoxShadow(color: c.primaryD, offset: const Offset(0, 3))] : null,
        ),
        child: Text(cat.name, // text only — no emoji icon
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: active ? c.bg : c.textMute)),
      ),
    );
  }

  Widget _grid(PosColors c) {
    final items = _visible;
    if (items.isEmpty) {
      return Center(child: Text('No items${_search.isNotEmpty ? ' matching "$_search"' : ' in this category'}',
          style: TextStyle(color: c.textDim, fontSize: 14, fontWeight: FontWeight.w700)));
    }
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 1100 ? 5 : box.maxWidth >= 820 ? 4 : box.maxWidth >= 560 ? 3 : 2;
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 0.82),
        itemCount: items.length,
        itemBuilder: (_, i) => _productCard(c, items[i]),
      );
    });
  }

  Widget _productCard(PosColors c, MenuItem p) {
    final soldOut = !p.sellable;
    final inCart = _active.items.any((i) => i.productId == p.id);
    return Opacity(
      opacity: soldOut ? 0.4 : 1,
      child: GestureDetector(
        onTap: soldOut ? null : () => _addProduct(p),
        child: Container(
          decoration: BoxDecoration(
            color: c.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border),
            boxShadow: [BoxShadow(color: c.shadow, blurRadius: 16, offset: const Offset(0, 5))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10), // bo góc như hiện tại
                  child: _itemImage(c, p),
                ),
              )),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 10, 13, 13),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, height: 1.25, color: c.text)),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(money(p.price), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: c.text)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(10),
                          boxShadow: [BoxShadow(color: c.primaryD, offset: const Offset(0, 2))]),
                      child: Text('+ Add', style: TextStyle(color: c.bg, fontWeight: FontWeight.w900, fontSize: 13)),
                    ),
                  ]),
                ]),
              ),
            ]),
            if (p.popular) Positioned(top: 7, left: 7, child: _badge('★ HOT', const Color(0xFFFB7185), Colors.white)),
            if (inCart) Positioned(top: 7, right: 7, child: _badge('✓ Added', c.cyan, c.bg)),
            if (soldOut) Positioned(left: 0, right: 0, top: 0, bottom: 0, child: Center(
              child: Container(width: double.infinity, color: Colors.black.withValues(alpha: 0.7), padding: const EdgeInsets.all(6),
                  child: const Text('SOLD OUT', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1))),
            )),
          ]),
        ),
      ),
    );
  }

  // Item image: synced 1:1 WebP photo (same imageUrl as kiosk + online); when
  // the item has no photo yet, fall back to the emoji-on-gradient tile.
  Widget _itemImage(PosColors c, MenuItem p) {
    // Real photo if set, else the shared VIDO default placeholder; gradient+emoji
    // only if even the default fails to load (offline).
    final url = p.imageUrl.isNotEmpty ? p.imageUrl : kDefaultItemImage;
    final fallback = Container(
      decoration: BoxDecoration(gradient: gradientFor(p.name)),
      alignment: Alignment.center,
      child: Text(p.icon, style: const TextStyle(fontSize: 46)),
    );
    return Image.network(
      url, fit: BoxFit.cover, width: double.infinity, height: double.infinity,
      errorBuilder: (ctx, e, st) => fallback,
      loadingBuilder: (ctx, child, prog) =>
          prog == null ? child : Container(color: c.card, child: const Center(
              child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))),
    );
  }

  Widget _badge(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w900)),
      );

  // ----------------------------------------------------------- cart (right)
  Widget _cart(PosColors c) {
    final o = _active;
    final t = o.totals;
    return Container(
      width: 360,
      decoration: BoxDecoration(color: c.panel, border: Border(left: BorderSide(color: c.border))),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 16),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('🛍️ Order #${o.number}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: c.text)),
            Text(_time(o.createdAt), style: TextStyle(fontSize: 12, color: c.textMute, fontWeight: FontWeight.w800)),
          ]),
        ),
        Expanded(child: o.items.isEmpty
            ? Center(child: Text('No items yet.\nTap a drink to add it.', textAlign: TextAlign.center,
                style: TextStyle(color: c.textDim, fontSize: 13, fontWeight: FontWeight.w700)))
            : ListView(padding: const EdgeInsets.all(10), children: [for (final l in o.items) _cartItem(c, l)])),
        _cartFoot(c, o, t),
      ]),
    );
  }

  Widget _cartItem(PosColors c, CartLine l) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 44, height: 44, alignment: Alignment.center,
            decoration: BoxDecoration(gradient: gradientFor(l.name), borderRadius: BorderRadius.circular(9)),
            child: Text(l.emoji, style: const TextStyle(fontSize: 22))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.name, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, height: 1.3, color: c.text)),
          if (!l.isSimple) Padding(padding: const EdgeInsets.only(top: 2),
              child: Text('${l.size == 'L' ? 'Large' : 'Regular'} · ${l.sugar}% sugar · ${l.ice}% ice',
                  style: TextStyle(fontSize: 12, color: c.textMute, fontWeight: FontWeight.w800))),
          if (l.toppings.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2),
              child: Text('+ ${l.toppings.map((t) => t.name).join(', ')}', style: TextStyle(fontSize: 12, color: c.primary, fontWeight: FontWeight.w800))),
          Padding(padding: const EdgeInsets.only(top: 8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _qtyBtn(c, '−', () => _setQty(l, l.qty - 1)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('${l.qty}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c.text))),
                _qtyBtn(c, '+', () => _setQty(l, l.qty + 1)),
              ]),
            ),
            Text(money(l.lineTotal), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: c.text)),
          ])),
        ])),
      ]),
    );
  }

  Widget _qtyBtn(PosColors c, String s, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(width: 26, height: 26, alignment: Alignment.center,
            decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
            child: Text(s, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: c.bg))),
      );

  Widget _cartFoot(PosColors c, Order o, ({double sub, double discount, double taxable, double tax, double total}) t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          _chip(c, '🏷️ ${o.discount > 0 ? (o.discountType == 'percent' ? '${o.discount.toStringAsFixed(0)}% off' : '-${money(o.discount)}') : 'Discount'}',
              active: o.discount > 0, activeColor: c.primary, onTap: _openDiscount),
          const SizedBox(width: 6),
          _chip(c, '📝 ${o.note.isNotEmpty ? 'Note ✓' : 'Note'}', active: o.note.isNotEmpty, activeColor: c.cyan, onTap: _openNote),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            _subRow(c, 'Subtotal', money(t.sub), c.text),
            if (t.discount > 0) _subRow(c, 'Discount', '−${money(t.discount)}', c.primary),
            _subRow(c, 'Tax (${(ShopConfig.tax * 100).toStringAsFixed(2)}%)', money(t.tax), c.text),
            Container(
              margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.primary, width: 1, style: BorderStyle.solid))),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Total', style: TextStyle(fontWeight: FontWeight.w800, color: c.text)),
                Text(money(t.total), style: TextStyle(fontSize: 28, color: c.primary, fontWeight: FontWeight.w900)),
              ]),
            ),
            Padding(padding: const EdgeInsets.only(top: 7), child: Align(alignment: Alignment.centerLeft,
                child: Text('✨ Customer adds tip on card terminal', style: TextStyle(fontSize: 12, color: c.yellow, fontWeight: FontWeight.w800)))),
          ]),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: o.items.isEmpty ? null : _openPayment,
          child: Opacity(
            opacity: o.items.isEmpty ? 0.4 : 1,
            child: Container(
              padding: const EdgeInsets.all(16), alignment: Alignment.center,
              decoration: BoxDecoration(gradient: c.primaryG, borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: const Color(0xFFFF9500).withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 4))]),
              child: Text('💳 Pay ${money(t.total)} →', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: c.bg)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _chip(PosColors c, String text, {required bool active, required Color activeColor, required VoidCallback onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(color: active ? activeColor : c.card, borderRadius: BorderRadius.circular(999)),
          child: Text(text, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: active ? c.bg : c.text)),
        ),
      );

  Widget _subRow(PosColors c, String k, String v, Color vColor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: TextStyle(fontSize: 14, color: c.textMute, fontWeight: FontWeight.w800)),
          Text(v, style: TextStyle(fontSize: 14, color: vColor, fontWeight: FontWeight.w800)),
        ]),
      );

  String _time(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }
}

// ============================================================================
// CUSTOMIZE SHEET — size / sugar / ice / toppings. Port of CustomizeModal.
// ============================================================================
class CustomizeSheet extends StatefulWidget {
  final MenuItem product;
  final List<Topping> toppings;
  const CustomizeSheet({super.key, required this.product, required this.toppings});
  @override
  State<CustomizeSheet> createState() => _CustomizeSheetState();
}

class _CustomizeSheetState extends State<CustomizeSheet> {
  String _size = 'R';
  int _sugar = 100, _ice = 100;
  final List<Topping> _sel = [];

  double get _total {
    var p = widget.product.price + (_size == 'L' ? ShopConfig.sizeLargeBonus : 0);
    p += _sel.fold(0.0, (s, t) => s + t.price);
    return p;
  }

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    final p = widget.product;
    return _PosDialog(
      maxWidth: 520, padding: EdgeInsets.zero,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: 140, decoration: BoxDecoration(gradient: gradientFor(p.name)),
            alignment: Alignment.center, child: Text(p.icon, style: const TextStyle(fontSize: 80))),
        Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(22, 18, 22, 8), child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(p.name, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c.text)),
            Padding(padding: const EdgeInsets.only(top: 4),
                child: Text('Base: ${money(p.price)}', style: TextStyle(fontSize: 13, color: c.textMute, fontWeight: FontWeight.w700))),
            _label(c, 'SIZE'),
            Row(children: [
              _seg(c, 'Regular', _size == 'R', () => setState(() => _size = 'R')),
              const SizedBox(width: 8),
              _seg(c, 'Large  +${money(ShopConfig.sizeLargeBonus)}', _size == 'L', () => setState(() => _size = 'L')),
            ]),
            _label(c, 'SUGAR'),
            Row(children: [for (final v in const [0,25,50,75,100]) ...[_seg(c, '$v%', _sugar == v, () => setState(() => _sugar = v), small: true), if (v != 100) const SizedBox(width: 6)]]),
            _label(c, 'ICE'),
            Row(children: [for (final v in const [0,25,50,75,100]) ...[_seg(c, '$v%', _ice == v, () => setState(() => _ice = v), small: true), if (v != 100) const SizedBox(width: 6)]]),
            if (widget.toppings.isNotEmpty) ...[
              _label(c, 'ADD TOPPINGS'),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final t in widget.toppings) _toppingChip(c, t)]),
            ],
            const SizedBox(height: 8),
          ]),
        )),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('Item total', style: TextStyle(fontSize: 12, color: c.textMute)),
              Text(money(_total), style: TextStyle(fontSize: 26, color: c.primary, fontWeight: FontWeight.w900)),
            ]),
            const Spacer(),
            PButton(const Text('Add to Order'), size: PBtnSize.lg, onPressed: () {
              Navigator.of(context).pop(CartLine(
                id: 'L${DateTime.now().microsecondsSinceEpoch}',
                productId: p.id, name: p.name, emoji: p.icon, category: p.category,
                size: _size, sugar: _sugar, ice: _ice, toppings: List.of(_sel), basePrice: p.price));
            }),
          ]),
        ),
      ]),
    );
  }

  Widget _toppingChip(PosColors c, Topping t) {
    final active = _sel.any((x) => x.id == t.id);
    return GestureDetector(
      onTap: () => setState(() { active ? _sel.removeWhere((x) => x.id == t.id) : _sel.add(t); }),
      child: Container(
        width: 152, padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: active ? c.cyan : c.card, borderRadius: BorderRadius.circular(12),
          boxShadow: active ? [BoxShadow(color: c.cyanD, offset: const Offset(0, 3))] : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(t.name, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: active ? c.bg : c.text)),
          Padding(padding: const EdgeInsets.only(top: 2),
              child: Text('+${money(t.price)}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: active ? c.bg : c.textMute))),
        ]),
      ),
    );
  }
}

Widget _label(PosColors c, String t) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c.textMute, letterSpacing: 1)),
    );

Widget _seg(PosColors c, String label, bool active, VoidCallback onTap, {bool small = false}) => Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: small ? 8 : 12, horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? c.primary : c.card, borderRadius: BorderRadius.circular(10),
            boxShadow: active ? [BoxShadow(color: c.primaryD, offset: const Offset(0, 3))] : null,
          ),
          child: Text(label, textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: small ? 12 : 14, color: active ? c.bg : c.text)),
        ),
      ),
    );

// ============================================================================
// DISCOUNT DIALOG — manager-gated. Port of DiscountModal.
// ============================================================================
class _DiscountDialog extends StatefulWidget {
  final Order order;
  const _DiscountDialog({required this.order});
  @override
  State<_DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<_DiscountDialog> {
  String _type = 'amount';
  final _value = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    return _PosDialog(maxWidth: 420, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('🏷️ Apply Discount', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c.text)),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          _seg(c, '\$ Amount', _type == 'amount', () => setState(() => _type = 'amount')),
          const SizedBox(width: 6),
          _seg(c, '% Percent', _type == 'percent', () => setState(() => _type = 'percent')),
        ]),
      ),
      const SizedBox(height: 14),
      PField(label: _type == 'amount' ? 'Discount Amount (\$)' : 'Discount Percentage (%)',
          child: PInput(controller: _value, hintText: _type == 'amount' ? '0.00' : '10', keyboardType: TextInputType.number)),
      Row(children: [
        Expanded(flex: 1, child: PButton(const Text('Remove'), variant: PBtnVariant.ghost, expand: true,
            onPressed: () => Navigator.of(context).pop((value: 0.0, type: 'amount')))),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: PButton(const Text('Apply'), expand: true,
            onPressed: () => Navigator.of(context).pop((value: double.tryParse(_value.text) ?? 0, type: _type)))),
      ]),
    ]));
  }
}

// ============================================================================
// NOTE DIALOG — port of NoteModal.
// ============================================================================
class _NoteDialog extends StatefulWidget {
  final String initial;
  const _NoteDialog({required this.initial});
  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _note = TextEditingController(text: widget.initial);
  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    return _PosDialog(maxWidth: 420, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('📝 Order Note', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c.text)),
      const SizedBox(height: 14),
      Text('NOTE (VISIBLE ON RECEIPT)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c.textMute, letterSpacing: .5)),
      const SizedBox(height: 6),
      TextField(
        controller: _note, maxLines: 4, autofocus: true,
        style: TextStyle(color: c.text, fontSize: 14, fontWeight: FontWeight.w700), cursorColor: c.primary,
        decoration: InputDecoration(
          hintText: 'e.g., No straw, customer allergic to dairy...',
          hintStyle: TextStyle(color: c.textDim, fontWeight: FontWeight.w700),
          filled: true, fillColor: c.card,
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.primary)),
        ),
      ),
      const SizedBox(height: 14),
      PButton(const Text('Save Note'), expand: true, onPressed: () => Navigator.of(context).pop(_note.text)),
    ]));
  }
}

// ============================================================================
// POS DIALOG SHELL — centered dark card + close button. Port of Modal/ModalClose.
// ============================================================================
class _PosDialog extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;
  const _PosDialog({required this.child, this.maxWidth = 540, this.padding = const EdgeInsets.all(24)});
  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    return Dialog(
      backgroundColor: Colors.transparent, insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Stack(children: [
          Container(
            decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(18),
                boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 60, offset: Offset(0, 20))]),
            clipBehavior: Clip.antiAlias,
            padding: padding,
            child: child,
          ),
          Positioned(top: 14, right: 14, child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(width: 34, height: 34, alignment: Alignment.center,
                decoration: BoxDecoration(color: c.card, shape: BoxShape.circle),
                child: Icon(Icons.close, size: 18, color: c.text)),
          )),
        ]),
      ),
    );
  }
}

// ============================================================================
// PAYMENT SHEET — method select → Cash / Card(PAX) / Gift Card. Port of PaymentModal.
// Returns a result map {method, tip, cashReceived, changeGiven, cardLast4, cardType, authCode} on success.
// ============================================================================
class _PaymentSheet extends StatefulWidget {
  final Order order;
  const _PaymentSheet({required this.order});
  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  String? _method; // null=select, 'cash','card','giftcard'
  // terminal config (for card)
  String _termIp = '';
  int _termPort = 10009;
  String _termMode = 'tcp'; // tcp | usb | serial
  String _termSerial = '';

  @override
  void initState() {
    super.initState();
    Api.instance.getSettings().then((s) {
      final pay = Map<String, dynamic>.from(Map<String, dynamic>.from(s['settings'] ?? {})['payment'] ?? {});
      if (mounted) {
        setState(() {
        _termIp = (pay['ip'] ?? '').toString();
        _termPort = int.tryParse('${pay['port'] ?? 10009}') ?? 10009;
        _termMode = (pay['connectionMode'] ?? 'tcp').toString();
        _termSerial = (pay['terminalSerial'] ?? '').toString();
        });
      }
    });
  }

  bool _removingGift = false;

  Future<void> _removeGift() async {
    final o = widget.order;
    if (o.giftApplied <= 0 || o.giftCode == null || o.giftRef == null || _removingGift) return;
    setState(() => _removingGift = true);
    // Hoàn redeem (idempotent theo giftRef) rồi mới gỡ thẻ khỏi đơn — fail thì giữ nguyên.
    final r = await Api.instance.giftRefund(o.giftCode!, o.giftRef!);
    if (!mounted) return;
    if (r['ok'] == true) {
      setState(() { o.clearGift(); _removingGift = false; });
    } else {
      setState(() => _removingGift = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not remove the gift card — check the connection and try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    final o = widget.order;
    final hasGift = o.giftApplied > 0;
    return _PosDialog(maxWidth: 540, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_method == null) ...[
        Text('Payment', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c.text)),
        Padding(padding: const EdgeInsets.only(top: 4),
            child: Text('Order #${o.number}', style: TextStyle(fontSize: 13, color: c.textMute, fontWeight: FontWeight.w700))),
        _payTotalBox(c, hasGift ? 'Remaining due' : 'Total due', hasGift ? o.due : o.totals.total),
        if (hasGift) GiftAppliedLine(
          maskedCode: o.giftCodeMasked ?? '', applied: o.giftApplied, due: o.due,
          removing: _removingGift, onRemove: _removeGift,
        ),
        const SizedBox(height: 18),
        Row(children: [
          _payCard(c, Icons.attach_money, 'Cash', false, () => setState(() => _method = 'cash')),
          const SizedBox(width: 10),
          _payCard(c, Icons.credit_card, 'Card Payment', true, () => setState(() => _method = 'card')),
          const SizedBox(width: 10),
          // 1 thẻ / đơn trong D4 — thẻ đã áp thì nút mờ (Remove rồi mới đổi thẻ khác).
          hasGift
              ? Expanded(child: Opacity(opacity: .45, child: AbsorbPointer(child:
                  _payCardBox(c, Icons.smartphone, 'Gift Card applied'))))
              : _payCard(c, Icons.smartphone, 'Gift Card', false, () => setState(() => _method = 'giftcard')),
        ]),
      ] else if (_method == 'cash')
        _CashFlow(order: o, due: o.due, onBack: () => setState(() => _method = null), onDone: (r) => Navigator.of(context).pop(r))
      else if (_method == 'card')
        _PaxFlow(order: o, due: o.due, mode: _termMode, host: _termIp, port: _termPort, serial: _termSerial,
            onBack: () => setState(() => _method = null), onDone: (r) => Navigator.of(context).pop(r))
      else
        _GiftCardFlow(order: o,
            onBack: () => setState(() => _method = null),
            onDone: (r) => Navigator.of(context).pop(r),
            onPartial: () => setState(() => _method = null)),
    ]));
  }

  Widget _payCardBox(PosColors c, IconData icon, String label) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Icon(icon, size: 28, color: c.text),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: c.text)),
        ]),
      );

  Widget _payCard(PosColors c, IconData icon, String label, bool highlight, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: highlight ? c.primary : c.card, borderRadius: BorderRadius.circular(14),
              boxShadow: highlight ? [BoxShadow(color: c.primaryD, offset: const Offset(0, 4))] : null,
            ),
            child: Column(children: [
              Icon(icon, size: 28, color: highlight ? c.bg : c.text),
              const SizedBox(height: 8),
              Text(label, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: highlight ? c.bg : c.text)),
            ]),
          ),
        ),
      );
}

Widget _payTotalBox(PosColors c, String label, double total) => Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: c.text)),
        Text(money(total), style: TextStyle(fontSize: 28, color: c.primary, fontWeight: FontWeight.w900)),
      ]),
    );

Widget _backBtn(PosColors c, VoidCallback onBack, {bool enabled = true}) => Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: enabled ? onBack : null,
        icon: Icon(Icons.arrow_back, size: 14, color: c.textMute),
        label: Text('Back', style: TextStyle(color: c.textMute, fontWeight: FontWeight.w800)),
        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      ),
    );

// === CASH FLOW ===
class _CashFlow extends StatefulWidget {
  final Order order;
  final double? due; // D4: phần còn phải thu (sau gift) — null = tổng đơn như cũ
  final VoidCallback onBack;
  final ValueChanged<Map<String, dynamic>> onDone;
  const _CashFlow({required this.order, this.due, required this.onBack, required this.onDone});
  @override
  State<_CashFlow> createState() => _CashFlowState();
}

class _CashFlowState extends State<_CashFlow> {
  final _recv = TextEditingController();
  double get _r => double.tryParse(_recv.text) ?? 0;
  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    final total = widget.due ?? widget.order.totals.total;
    final change = (_r - total).clamp(0, double.infinity).toDouble();
    final ok = _r >= total;
    final quick = <int>{total.ceil(), (total / 5).ceil() * 5, (total / 10).ceil() * 10, (total / 20).ceil() * 20}
        .where((v) => v >= total).take(4).toList()..sort();
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _backBtn(c, widget.onBack),
      Padding(padding: const EdgeInsets.only(top: 10),
          child: Text('💵 Cash Payment', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c.text))),
      _payTotalBox(c, 'Total due', total),
      const SizedBox(height: 14),
      PField(label: 'Amount Received', child: TextField(
        controller: _recv, keyboardType: const TextInputType.numberWithOptions(decimal: true), autofocus: true,
        textAlign: TextAlign.right, onChanged: (_) => setState(() {}),
        style: TextStyle(color: c.text, fontSize: 24, fontWeight: FontWeight.w800), cursorColor: c.primary,
        decoration: InputDecoration(hintText: '0.00', filled: true, fillColor: c.card,
          hintStyle: TextStyle(color: c.textDim),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.primary))),
      )),
      Row(children: [for (final a in quick) ...[Expanded(child: GestureDetector(
        onTap: () => setState(() => _recv.text = '$a'),
        child: Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(vertical: 8), alignment: Alignment.center,
            decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(8)),
            child: Text('\$$a', style: TextStyle(color: c.text, fontSize: 13, fontWeight: FontWeight.w800))),
      ))]]),
      const SizedBox(height: 14),
      if (_r > 0) Container(
        padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(color: ok ? c.primaryA : c.redA, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(ok ? 'Change' : 'Short by', style: TextStyle(fontWeight: FontWeight.w800, color: ok ? c.primary : c.red)),
          Text(money(ok ? change : total - _r), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: ok ? c.primary : c.red)),
        ]),
      ),
      PButton(const Text('Complete Sale'), expand: true,
          onPressed: ok ? () => widget.onDone({'method': 'cash', 'cashReceived': _r, 'changeGiven': change, 'tip': 0.0}) : null),
    ]);
  }
}

// === GIFT CARD FLOW ===
class _GiftCardFlow extends StatelessWidget {
  final Order order;
  final VoidCallback onBack;
  final ValueChanged<Map<String, dynamic>> onDone;
  final VoidCallback onPartial; // partial apply → quay lại chọn cash/card cho phần còn thiếu
  const _GiftCardFlow({required this.order, required this.onBack, required this.onDone, required this.onPartial});
  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _backBtn(c, onBack),
      Padding(padding: const EdgeInsets.only(top: 10),
          child: Text('Gift Card', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c.text))),
      _payTotalBox(c, 'Amount due', order.due),
      const SizedBox(height: 14),
      // D4: apply = min(balance, due). Đủ → đơn paid bằng thẻ; thiếu → ghi thẻ
      // vào đơn rồi quay lại chọn cash/card thu phần còn lại.
      GiftCardCheckPanel(
        check: (code) => Api.instance.giftCheck(code),
        redeem: (code, amount, ref) => Api.instance.giftRedeem(code, amount, ref),
        due: order.due,
        redeemRef: 'POS-${order.number}-${order.id}',
        onApplied: (a) {
          order.giftCode = a['code'].toString();           // RAM only — cho refund
          order.giftCodeMasked = maskGiftCode(order.giftCode!);
          order.giftApplied = (a['applied'] as num).toDouble();
          order.giftRemaining = (a['remaining'] as num).toDouble();
          order.giftRef = a['ref'].toString();
          if (order.due <= 0.005) {
            onDone({'method': 'giftcard', 'tip': 0.0});     // full-cover → đơn xong
          } else {
            onPartial();                                    // partial → chọn cash/card
          }
        },
      ),
      const SizedBox(height: 14),
      Text('Confirm the gift card was processed, then mark complete.', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: c.textMute, fontWeight: FontWeight.w700)),
      const SizedBox(height: 18),
      PButton(const Text('Mark as Paid'), expand: true, onPressed: () => onDone({'method': 'giftcard', 'tip': 0.0})),
    ]);
  }
}

// === PAX (card) FLOW ===
class _PaxFlow extends StatefulWidget {
  final Order order;
  final double? due; // D4: phần còn phải thu (sau gift)
  final String mode, host, serial;
  final int port;
  final VoidCallback onBack;
  final ValueChanged<Map<String, dynamic>> onDone;
  const _PaxFlow({required this.order, this.due, required this.mode, required this.host, required this.port, required this.serial, required this.onBack, required this.onDone});
  @override
  State<_PaxFlow> createState() => _PaxFlowState();
}

class _PaxFlowState extends State<_PaxFlow> {
  bool _busy = true;
  PaxResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() { _busy = true; _result = null; _error = null; });
    try {
      final r = await Pax.sale(amount: widget.due ?? widget.order.totals.total, connectionMode: widget.mode,
          host: widget.host.isEmpty ? null : widget.host, port: widget.port, terminalSerial: widget.serial,
          refNum: 'BB${widget.order.number}');
      if (!mounted) return;
      setState(() { _busy = false; _result = r; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    final t = widget.order.totals;
    final approved = _result?.approved == true;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _backBtn(c, widget.onBack, enabled: !_busy),
      Padding(padding: const EdgeInsets.only(top: 10),
          child: Text('Card Payment', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c.text))),
      Padding(padding: const EdgeInsets.only(top: 4),
          child: Text((widget.mode == 'tcp' && widget.host.isEmpty)
                  ? 'No terminal — simulated card payment'
                  : 'Customer is using the card terminal (${widget.mode.toUpperCase()})',
              style: TextStyle(fontSize: 13, color: c.textMute, fontWeight: FontWeight.w700))),
      _payTotalBox(c, 'Amount due', t.total),
      if (_busy) _statusCard(c, '💳', 'Waiting for card', 'Customer: insert, tap, or swipe', animated: true),
      if (!_busy && approved) _verifyTicket(c),
      if (!_busy && _result != null && !approved) _declineBox(c, 'Declined', _result!.message),
      if (!_busy && _error != null) _declineBox(c, 'Error', _error!),
      const SizedBox(height: 12),
      if (_busy) PButton(const Text('Cancel'), variant: PBtnVariant.ghost, expand: true, onPressed: widget.onBack)
      else if (approved) Row(children: [
        Expanded(child: PButton(const Text('Back'), variant: PBtnVariant.ghost, expand: true, onPressed: widget.onBack)),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: PButton(const Text('Complete Sale'), expand: true, onPressed: () => widget.onDone({
          'method': 'card', 'tip': 0.0,
          'cardLast4': _result!.cardLast4, 'cardType': _result!.cardType, 'authCode': _result!.authCode,
        }))),
      ])
      else PButton(const Text('Try Again'), expand: true, onPressed: _run),
    ]);
  }

  Widget _statusCard(PosColors c, String icon, String title, String msg, {bool animated = false}) => Container(
        margin: const EdgeInsets.symmetric(vertical: 12), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.yellow.withValues(alpha: 0.13), c.card])),
        child: Column(children: [
          Container(width: 64, height: 64, alignment: Alignment.center,
              decoration: BoxDecoration(color: c.yellow, shape: BoxShape.circle),
              child: Text(icon, style: const TextStyle(fontSize: 28))),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c.text)),
          if (msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
              child: Text(msg, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.textMute, fontWeight: FontWeight.w700))),
        ]),
      );

  Widget _declineBox(PosColors c, String title, String msg) => Container(
        margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.redA, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.error_outline, color: c.red),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: c.red)),
            if (msg.isNotEmpty) Text(msg, style: TextStyle(fontSize: 12, color: c.red)),
          ])),
        ]),
      );

  Widget _verifyTicket(PosColors c) {
    final o = widget.order; final t = o.totals; final r = _result!;
    Widget row(String a, String b, {Color? color, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(a, style: TextStyle(color: color ?? c.textMute, fontWeight: bold ? FontWeight.w900 : FontWeight.w700, fontSize: bold ? 16 : 13)),
          Text(b, style: TextStyle(color: color ?? c.text, fontWeight: bold ? FontWeight.w900 : FontWeight.w800, fontSize: bold ? 16 : 13)),
        ]));
    Widget dashed() => Padding(padding: const EdgeInsets.symmetric(vertical: 8),
        child: DecoratedBox(decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))), child: const SizedBox(width: double.infinity)));
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Text('PLEASE VERIFY TICKET', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, color: c.text))),
        dashed(),
        for (final l in o.items) row('${l.qty}× ${l.name}', money(l.lineTotal)),
        dashed(),
        row('Subtotal', money(t.sub)),
        if (t.discount > 0) row('Discount', '−${money(t.discount)}'),
        row('Tax (${(ShopConfig.tax * 100).toStringAsFixed(2)}%)', money(t.tax)),
        dashed(),
        row('TOTAL DUE', money(t.total), color: c.primary, bold: true),
        dashed(),
        row('Card', '•• ${r.cardLast4}'),
        row('Auth Code', r.authCode),
        row('Status', r.simulated ? 'APPROVED (test) ✓' : 'APPROVED ✓', color: c.primary),
      ]),
    );
  }
}

// ============================================================================
// RECEIPT DIALOG — Sale complete. Port of ReceiptModal.
// ============================================================================
class _ReceiptDialog extends StatelessWidget {
  final Order order;
  final Map<String, dynamic> pay;
  final String storeName;
  const _ReceiptDialog({required this.order, required this.pay, required this.storeName});

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    final t = order.totals;
    final tip = (pay['tip'] ?? 0.0) as double;
    final grand = t.total + tip;
    final isCard = pay['method'] == 'card';
    final cash = (pay['cashReceived'] ?? 0.0) as double;
    final change = (pay['changeGiven'] ?? 0.0) as double;
    Widget row(String a, String b, {Color? color, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(a, style: TextStyle(color: color ?? c.textMute, fontWeight: bold ? FontWeight.w900 : FontWeight.w700, fontSize: bold ? 16 : 13)),
          Text(b, style: TextStyle(color: color ?? c.text, fontWeight: bold ? FontWeight.w900 : FontWeight.w800, fontSize: bold ? 16 : 13)),
        ]));
    return _PosDialog(maxWidth: 440, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(child: Container(width: 64, height: 64, alignment: Alignment.center,
          decoration: BoxDecoration(color: c.cyan, shape: BoxShape.circle, boxShadow: [BoxShadow(color: c.cyanD, offset: const Offset(0, 5))]),
          child: const Text('✓', style: TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.w900)))),
      const SizedBox(height: 12),
      Center(child: Text('Sale Complete!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c.text))),
      Center(child: Padding(padding: const EdgeInsets.only(top: 4),
          child: Text('Order #${order.officialNumber}', style: TextStyle(fontSize: 12, color: c.textMute, fontWeight: FontWeight.w700)))),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          for (final l in order.items) row('${l.qty}× ${l.name}', money(l.lineTotal)),
          Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: DecoratedBox(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))), child: const SizedBox(width: double.infinity))),
          row('Subtotal', money(t.sub)),
          if (t.discount > 0) row('Discount', '−${money(t.discount)}'),
          row('Tax', money(t.tax)),
          if (tip > 0) row('Tip', money(tip)),
          row('TOTAL', money(grand), color: c.primary, bold: true),
          if (order.giftApplied > 0) ...[
            // D5: dòng gift dùng CHUNG composer với bản in → màn hình = giấy in.
            for (final r in receiptPaymentLines(
              paymentMethod: (pay['method'] ?? '').toString(), total: grand,
              cashReceived: cash, change: change,
              giftCodeMasked: order.giftCodeMasked ?? '', giftApplied: order.giftApplied,
              giftRemaining: order.giftRemaining,
            )) row(r[0], r[1]),
            if (isCard) row('Card', '${pay['cardType'] ?? 'CARD'} •• ${pay['cardLast4'] ?? ''}'),
          ] else ...[
            if (isCard) row('Card', '${pay['cardType'] ?? 'CARD'} •• ${pay['cardLast4'] ?? ''}')
            else if (cash > 0) ...[row('Cash', money(cash)), row('Change', money(change))],
            row('Paid', (pay['method'] ?? '').toString().toUpperCase()),
          ],
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: PButton(const Text('🖨️ Print'), variant: PBtnVariant.ghost, expand: true, onPressed: () async {
          try {
            await printReceipt(storeName: storeName.isEmpty ? 'Vido Food' : storeName, number: order.officialNumber,
              type: orderTypeOf(order.type).label,
              items: order.items.map((l) => {'qty': l.qty, 'name': l.name, 'lineTotal': l.lineTotal}).toList(),
              subtotal: t.sub, tax: t.tax, tip: tip, total: grand,
              paymentMethod: (pay['method'] ?? '').toString(), cashReceived: cash, change: change,
              giftCodeMasked: order.giftCodeMasked ?? '', giftApplied: order.giftApplied,
              giftRemaining: order.giftRemaining);
          } catch (_) {}
        })),
        const SizedBox(width: 10),
        Expanded(child: PButton(const Text('New Order'), expand: true, onPressed: () => Navigator.of(context).pop())),
      ]),
    ]));
  }
}
