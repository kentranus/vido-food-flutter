import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api.dart';
import '../printer.dart';
import '../ui/pos_theme.dart';
import '../ui/pos_widgets.dart';
import 'kiosk_setup.dart' show kioskAutoFlag;
import 'order_models.dart' show money;

/// Online/Kiosk orders — faithful port of React views/OnlineOrders.jsx
/// (OnlineOrdersProvider + NewOrderTakeover + OrdersBoard). Realtime via SSE
/// (/api/events) with a 15s poll fallback, looping chime for new ONLINE orders,
/// and KIOSK orders (already paid) auto-print + light chime (no takeover).

({String label, Color color}) sourceMeta(String source) {
  final s = source.toLowerCase();
  if (s.contains('online') || s.contains('web')) return (label: 'ONLINE', color: const Color(0xFFFF6A00));
  if (s.contains('kiosk')) return (label: 'KIOSK', color: const Color(0xFF8B5CF6));
  return (label: 'POS', color: const Color(0xFF64748B));
}

/// new / preparing / ready (kiosk pre-paid skips NEW → preparing). null = hidden.
String? columnOf(String status, String source) {
  final src = source.toLowerCase();
  if (status == 'ready') return 'ready';
  if (status == 'accepted' || status == 'preparing') return 'preparing';
  if (status == 'pending_accept' || status == 'new') return src.contains('kiosk') ? 'preparing' : 'new';
  return null;
}

/// OM4 — server-side Auto Confirm: an ONLINE order that shows up ALREADY
/// accepted (server captured the card at order time). Staff still get a light
/// ting so they know to start cooking — there's just nothing to confirm.
bool isServerConfirmedOnline(String status, String source, {required bool seen}) =>
    !seen && status == 'accepted' && !source.toLowerCase().contains('kiosk');

String minsAgo(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  final m = DateTime.now().difference(d.toLocal()).inMinutes;
  if (m <= 0) return 'just now';
  if (m < 60) return '${m}m ago';
  return '${(m / 60).floor()}h ago';
}

class OnlineOrdersController extends ChangeNotifier {
  static OnlineOrdersController? active;

  List<OnlineOrder> orders = [];
  List<OnlineOrder> queue = []; // NEW online orders awaiting accept (drives takeover)
  bool online = true;

  final _seen = <String>{};       // ids we've already alerted on
  final _kioskPrinted = <String>{}; // ids already kitchen-printed (kiosk/auto)
  final _receiptPrinted = <String>{}; // ids already receipt-printed (auto)
  final _autoAccepted = <String>{};   // ids already auto-accepted
  bool _first = true;
  Timer? _poll;
  Timer? _cfgPoll;
  http.Client? _sseClient;
  StreamSubscription? _sseSub;
  final _player = AudioPlayer();
  final _ting = AudioPlayer();
  bool _chiming = false;

  // Kiosk Setup → auto-handling flags (kioskKitchen defaults ON — it was
  // previously hardcoded; everything else defaults OFF = previous behavior).
  Map<String, dynamic> _auto = {};
  int _prepDefault = 15;
  bool _flag(String k) => kioskAutoFlag(_auto, k);

  void start() {
    active = this;
    _loadAutoConfig();
    refresh();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => refresh());
    _cfgPoll = Timer.periodic(const Duration(minutes: 5), (_) => _loadAutoConfig());
    _connectSse();
  }

  Future<void> _loadAutoConfig() async {
    if (!Api.instance.isLoggedIn) return;
    try {
      final s = await Api.instance.getSettings();
      final settings = Map<String, dynamic>.from(s['settings'] ?? {});
      _auto = Map<String, dynamic>.from(Map<String, dynamic>.from(settings['kiosk'] ?? {})['auto'] ?? {});
      final sf = Map<String, dynamic>.from(settings['storefront'] ?? {});
      _prepDefault = int.tryParse('${sf['prepMinutes'] ?? 15}') ?? 15;
    } catch (_) {}
  }

  @override
  void dispose() {
    if (active == this) active = null;
    _poll?.cancel();
    _cfgPoll?.cancel();
    _sseSub?.cancel();
    _sseClient?.close();
    _player.dispose();
    _ting.dispose();
    super.dispose();
  }

  Future<void> _connectSse() async {
    if (!Api.instance.isLoggedIn) return;
    try {
      final uri = Uri.parse('${Api.instance.baseUrl}/api/events?token=${Uri.encodeComponent(Api.instance.token)}');
      _sseClient = http.Client();
      final req = http.Request('GET', uri)..headers['accept'] = 'text/event-stream';
      final resp = await _sseClient!.send(req);
      _sseSub = resp.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) { if (line.startsWith('data:') || line.startsWith('event:')) refresh(); },
        onDone: _reconnectSse, onError: (_) => _reconnectSse(), cancelOnError: true,
      );
    } catch (_) { _reconnectSse(); }
  }

  void _reconnectSse() {
    _sseSub?.cancel(); _sseClient?.close(); _sseClient = null;
    // back off then retry (poll keeps data fresh meanwhile)
    Future.delayed(const Duration(seconds: 10), () { if (active == this) _connectSse(); });
  }

  Future<void> refresh() async {
    if (!Api.instance.isLoggedIn) return;
    final list = await Api.instance.fetchOnlineOrders();
    // fetchOnlineOrders returns [] on offline/error; treat empty-after-data as offline blip only if it errored.
    final activeOrders = list.where((o) => columnOf(o.status, o.source) != null).toList()
      ..sort((a, b) => (b.createdAt).compareTo(a.createdAt));
    orders = activeOrders;
    online = true;

    final fresh = activeOrders.where((o) => columnOf(o.status, o.source) == 'new').toList();
    var hasNewOnline = false;
    final autoOnline = _flag('onlineAccept');
    for (final o in fresh) {
      if (autoOnline) {
        // Kiosk Setup → auto-accept online orders: same accept flow as tapping
        // Accept, no takeover/chime. Prints obey the per-source toggles.
        _seen.add(o.id);
        if (!_autoAccepted.contains(o.id)) { _autoAccepted.add(o.id); _autoAcceptOnline(o); }
      } else if (!_seen.contains(o.id)) { _seen.add(o.id); if (!_first) hasNewOnline = true; }
    }
    // Kiosk orders (already paid) → light ting once, prints per Kiosk Setup
    // (kitchen ticket defaults ON — same as the old hardcoded behavior).
    for (final o in activeOrders) {
      final isKiosk = o.source.toLowerCase().contains('kiosk');
      if (isKiosk && !_kioskPrinted.contains(o.id)) {
        _kioskPrinted.add(o.id);
        if (!_first) {
          _ting.play(AssetSource('sounds/order_alert.wav'));
          if (_flag('kioskKitchen')) _printTicket(o);
          if (_flag('kioskReceipt') && !_receiptPrinted.contains(o.id)) { _receiptPrinted.add(o.id); _printCustomerReceipt(o); }
        }
      }
      // Optional: also mark paid kiosk orders accepted on the backend.
      if (isKiosk && _flag('kioskAccept') && !_first
          && (o.status == 'new' || o.status == 'pending_accept') && !_autoAccepted.contains(o.id)) {
        _autoAccepted.add(o.id);
        Api.instance.accept(o.id, null);
      }
    }
    // OM4 — server-side Auto Confirm: online orders can arrive ALREADY accepted
    // (store toggle in Settings → Online Ordering; card was captured at order
    // time). Light ting — no takeover, nothing to confirm. Prints reuse the
    // existing online auto-print toggles; markPrinted clears the server flag so
    // other devices (Order Manager app) don't double-print.
    for (final o in activeOrders) {
      if (isServerConfirmedOnline(o.status, o.source, seen: _seen.contains(o.id))) {
        _seen.add(o.id);
        if (_first) continue;
        _ting.play(AssetSource('sounds/order_alert.wav'));
        if (o.shouldPrint) {
          var printedAny = false;
          if (_flag('onlineKitchen') && !_kioskPrinted.contains(o.id)) { _kioskPrinted.add(o.id); _printTicket(o); printedAny = true; }
          if (_flag('onlineReceipt') && !_receiptPrinted.contains(o.id)) { _receiptPrinted.add(o.id); _printCustomerReceipt(o); printedAny = true; }
          if (printedAny) Api.instance.markPrinted(o.id);
        }
      }
    }
    _first = false;
    queue = autoOnline ? [] : fresh;
    if (hasNewOnline) _startChime();
    if (queue.isEmpty) _stopChime();
    notifyListeners();
  }

  /// Auto-accept an ONLINE order (Kiosk Setup toggle). Card capture happens on
  /// the backend exactly like a manual Accept; kitchen/receipt prints follow
  /// the online auto-print toggles.
  Future<void> _autoAcceptOnline(OnlineOrder o) async {
    final r = await Api.instance.accept(o.id, _prepDefault);
    if (r['ok'] != true) { _autoAccepted.remove(o.id); return; } // retry next poll
    if (_flag('onlineKitchen') && !_kioskPrinted.contains(o.id)) { _kioskPrinted.add(o.id); await _printTicket(o); }
    if (_flag('onlineReceipt') && !_receiptPrinted.contains(o.id)) { _receiptPrinted.add(o.id); await _printCustomerReceipt(o); }
    try { await Api.instance.markPrinted(o.id); } catch (_) {}
    await refresh();
  }

  Future<void> _printCustomerReceipt(OnlineOrder o) async {
    try {
      await printReceipt(
        storeName: Api.instance.storeName, number: o.number ?? o.id, type: o.orderType,
        items: o.items.map((it) => {'qty': it.quantity, 'name': it.name, 'lineTotal': it.lineTotal}).toList(),
        subtotal: o.subtotal, tax: o.tax, tip: o.tip, total: o.total,
        paymentMethod: o.isCard || o.paymentStatus == 'paid' ? 'card' : '');
    } catch (e) { if (kDebugMode) print('print receipt failed: $e'); }
  }

  void _startChime() async {
    if (_chiming) return;
    _chiming = true;
    try { await _player.setReleaseMode(ReleaseMode.loop); await _player.play(AssetSource('sounds/order_alert.wav')); } catch (_) {}
  }

  void _stopChime() async {
    if (!_chiming) return;
    _chiming = false;
    try { await _player.stop(); } catch (_) {}
  }

  void stopChime() => _stopChime();

  Future<void> _printTicket(OnlineOrder o, {int? eta}) async {
    try {
      await printKitchenTicket(
        source: o.source, number: o.number ?? o.id, type: o.orderType,
        customer: o.customer, phone: o.customerPhone,
        items: o.items.map((it) => {'qty': it.quantity, 'name': it.name, 'mods': it.modifiers, 'notes': it.notes}).toList());
    } catch (e) { if (kDebugMode) print('print ticket failed: $e'); }
  }

  /// Accept an ONLINE order: backend captures the card, then print + mark
  /// printed — printing is gated by the 'acceptPrint' toggle (Kiosk Setup,
  /// default ON = original behavior). When OFF we also skip markPrinted so the
  /// server flag stays for another device (e.g. Order Manager) to print.
  Future<({bool ok, String error})> accept(OnlineOrder o, int eta) async {
    final r = await Api.instance.accept(o.id, eta);
    if (r['ok'] != true) return (ok: false, error: (r['error'] ?? 'Confirm failed — card not charged.').toString());
    if (_flag('acceptPrint')) {
      await _printTicket(o, eta: eta);
      try { await Api.instance.markPrinted(o.id); } catch (_) {}
    }
    await refresh();
    return (ok: true, error: '');
  }

  Future<({bool ok, String error})> reject(OnlineOrder o, String reason) async {
    final r = await Api.instance.reject(o.id, reason);
    if (r['ok'] != true) return (ok: false, error: (r['error'] ?? 'Reject failed').toString());
    await refresh();
    return (ok: true, error: '');
  }

  Future<void> markReady(OnlineOrder o) async { await Api.instance.markReady(o.id); await refresh(); }
  Future<void> complete(OnlineOrder o) async { await Api.instance.setStatus(o.id, 'completed'); await refresh(); }
}

// ===========================================================================
// NEW ORDER TAKEOVER — full-screen, unmissable popup for the front NEW order.
// ===========================================================================
const _prepTimes = [10, 15, 20, 30, 45];
const _rejectReasons = ['Too busy', 'Item unavailable', 'Closing soon', 'Other'];

class NewOrderTakeover extends StatefulWidget {
  final OnlineOrdersController ctrl;
  final OnlineOrder order;
  const NewOrderTakeover({super.key, required this.ctrl, required this.order});
  @override
  State<NewOrderTakeover> createState() => _NewOrderTakeoverState();
}

class _NewOrderTakeoverState extends State<NewOrderTakeover> {
  String _step = 'main'; // main | prep | reason
  bool _busy = false;
  String _err = '';
  final _customEta = TextEditingController();

  Future<void> _accept(int eta) async {
    setState(() { _busy = true; _err = ''; });
    final r = await widget.ctrl.accept(widget.order, eta);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) setState(() { _err = r.error; _step = 'main'; });
  }

  Future<void> _reject(String reason) async {
    setState(() { _busy = true; _err = ''; });
    final r = await widget.ctrl.reject(widget.order, reason);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) setState(() { _err = r.error; _step = 'main'; });
  }

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    final o = widget.order;
    final sm = sourceMeta(o.source);
    return Container(
      color: const Color(0xB8080A0E),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.of(context).size.height * 0.94),
        child: Container(
          decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 80, offset: Offset(0, 30))]),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // banner
            Container(
              color: sm.color, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${sm.label} ORDER', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.schedule, size: 14, color: Colors.white),
                  const SizedBox(width: 5),
                  Text(minsAgo(o.createdAt), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
                ]),
              ]),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('#${o.number ?? o.id}', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: c.text)),
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: c.border)),
                  child: Text(o.orderType.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: c.text))),
            ])),
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 10), child: Row(children: [
              Text(o.customer, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: c.text)),
              if (o.customerPhone.isNotEmpty) ...[
                const SizedBox(width: 12),
                Icon(Icons.phone, size: 13, color: c.textMute), const SizedBox(width: 4),
                Text(o.customerPhone, style: TextStyle(color: c.textMute, fontWeight: FontWeight.w700, fontSize: 13)),
              ],
            ])),
            // items
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border), bottom: BorderSide(color: c.border))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final it in o.items) Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 38, child: Text('${it.quantity}×', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c.primary))),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(it.name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.text)),
                    if (it.modifiers.isNotEmpty) Text(it.modifiers.join(', '), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textMute)),
                    if (it.notes.isNotEmpty) Text('"${it.notes}"', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFFF6A00))),
                  ])),
                ])),
              ]),
            ),
            // totals
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), child: Column(children: [
              _row(c, 'Subtotal', money(o.subtotal)),
              if (o.tax > 0) _row(c, 'Tax', money(o.tax)),
              if (o.tip > 0) _row(c, 'Tip', money(o.tip)),
              _row(c, 'Total', money(o.total), big: true),
              Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 8),
                  child: Text(o.isCard ? '💳 Card on hold — charged on accept' : '🏪 Pay at store',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.textMute)))),
            ])),
            if (_err.isNotEmpty) Container(margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: c.redA, borderRadius: BorderRadius.circular(10)),
                child: Text(_err, style: TextStyle(color: c.red, fontWeight: FontWeight.w800, fontSize: 13))),
            _footer(c, o),
          ])),
        ),
      ),
    );
  }

  Widget _footer(PosColors c, OnlineOrder o) {
    if (_step == 'main') {
      return Padding(padding: const EdgeInsets.all(20), child: Row(children: [
        Expanded(child: GestureDetector(
          onTap: _busy ? null : () { widget.ctrl.stopChime(); setState(() => _step = 'reason'); },
          child: Container(padding: const EdgeInsets.all(18), alignment: Alignment.center,
              decoration: BoxDecoration(color: c.redA, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.red, width: 2)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.cancel, color: c.red), const SizedBox(width: 8),
                Text('Reject', style: TextStyle(color: c.red, fontWeight: FontWeight.w900, fontSize: 17))])),
        )),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: GestureDetector(
          onTap: _busy ? null : () { widget.ctrl.stopChime(); setState(() => _step = 'prep'); },
          child: Container(padding: const EdgeInsets.all(18), alignment: Alignment.center,
              decoration: BoxDecoration(color: c.green, borderRadius: BorderRadius.circular(14)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.check_circle, color: Color(0xFF06210F)), const SizedBox(width: 8),
                const Text('Accept', style: TextStyle(color: Color(0xFF06210F), fontWeight: FontWeight.w900, fontSize: 20))])),
        )),
      ]));
    }
    if (_step == 'prep') {
      return Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _backBtn(c, () => setState(() => _step = 'main')),
        Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('Prep time — when will it be ready?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: c.text))),
        Row(children: [for (final m in _prepTimes) ...[Expanded(child: GestureDetector(
          onTap: _busy ? null : () => _accept(m),
          child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(vertical: 16), alignment: Alignment.center,
              decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border, width: 2)),
              child: Column(children: [Text('$m', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c.text)),
                Text('min', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c.textMute))])),
        ))]]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: PInput(controller: _customEta, hintText: 'Custom min', keyboardType: TextInputType.number)),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _busy ? null : () { final v = int.tryParse(_customEta.text); if (v != null) _accept(v); },
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(color: c.green, borderRadius: BorderRadius.circular(12)),
                child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF06210F)))
                    : const Text('Confirm', style: TextStyle(color: Color(0xFF06210F), fontWeight: FontWeight.w900))),
          ),
        ]),
        if (o.isCard) Padding(padding: const EdgeInsets.only(top: 14), child: Center(child: Text("Accepting charges the customer's card now.", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.textMute)))),
      ]));
    }
    // reason
    return Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _backBtn(c, () => setState(() => _step = 'main')),
      Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('Reject reason — the customer is told this', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: c.text))),
      GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 3.4,
          children: [for (final r in _rejectReasons) GestureDetector(
            onTap: _busy ? null : () => _reject(r),
            child: Container(alignment: Alignment.center,
                decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border, width: 2)),
                child: Text(r, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: c.text))),
          )]),
      Padding(padding: const EdgeInsets.only(top: 14), child: Center(child: Text('Rejecting voids the authorization — the customer is NOT charged.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.textMute)))),
    ]));
  }

  Widget _backBtn(PosColors c, VoidCallback onTap) => GestureDetector(
        onTap: onTap, child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.chevron_left, size: 16, color: c.textMute),
          Text('Back', style: TextStyle(color: c.textMute, fontWeight: FontWeight.w800, fontSize: 13)),
        ]),
      );

  Widget _row(PosColors c, String k, String v, {bool big = false}) => Padding(
        padding: EdgeInsets.symmetric(vertical: big ? 4 : 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: TextStyle(fontWeight: big ? FontWeight.w900 : FontWeight.w700, fontSize: big ? 18 : 13, color: big ? c.text : c.textMute)),
          Text(v, style: TextStyle(fontWeight: big ? FontWeight.w900 : FontWeight.w700, fontSize: big ? 18 : 13, color: big ? c.text : c.textMute)),
        ]),
      );
}

// ===========================================================================
// ORDERS BOARD — kanban (NEW / PREPARING / READY).
// ===========================================================================
class OrdersBoard extends StatelessWidget {
  final OnlineOrdersController ctrl;
  const OrdersBoard({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    return AnimatedBuilder(animation: ctrl, builder: (context, _) {
      final grouped = <String, List<OnlineOrder>>{'new': [], 'preparing': [], 'ready': []};
      for (final o in ctrl.orders) { final col = columnOf(o.status, o.source); if (col != null) grouped[col]!.add(o); }
      final cols = [
        (key: 'new', title: 'New', icon: Icons.notifications, tone: const Color(0xFFFF6A00)),
        (key: 'preparing', title: 'Preparing', icon: Icons.local_fire_department, tone: c.primary),
        (key: 'ready', title: 'Ready', icon: Icons.inventory_2, tone: c.green),
      ];
      return Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Online Orders', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: c.text)),
            Text('${Api.instance.storeName} · live board', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.textMute)),
          ]),
          Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: ctrl.online ? const Color(0x1F4ADE80) : c.redA, borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(ctrl.online ? Icons.wifi : Icons.wifi_off, size: 13, color: ctrl.online ? c.green : c.red),
                const SizedBox(width: 6),
                Text(ctrl.online ? 'Live' : 'Offline', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: ctrl.online ? c.green : c.red)),
              ])),
        ]),
        const SizedBox(height: 16),
        Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < cols.length; i++) ...[
            Expanded(child: _column(c, cols[i].key, cols[i].title, cols[i].icon, cols[i].tone, grouped[cols[i].key]!)),
            if (i < cols.length - 1) const SizedBox(width: 14),
          ],
        ])),
      ]));
    });
  }

  Widget _column(PosColors c, String key, String title, IconData icon, Color tone, List<OnlineOrder> list) {
    return Container(
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: Row(children: [
          Icon(icon, size: 16, color: tone), const SizedBox(width: 8),
          Text(title.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: tone, letterSpacing: 0.4)),
          const Spacer(),
          Container(constraints: const BoxConstraints(minWidth: 24), height: 24, alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(999)),
              child: Text('${list.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))),
        ])),
        Expanded(child: list.isEmpty
            ? Center(child: Text('—', style: TextStyle(color: c.textDim, fontWeight: FontWeight.w800)))
            : ListView(padding: const EdgeInsets.all(12), children: [for (final o in list) _card(c, key, o)])),
      ]),
    );
  }

  Widget _card(PosColors c, String col, OnlineOrder o) {
    final sm = sourceMeta(o.source);
    return Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border),
          boxShadow: [BoxShadow(color: c.shadow, blurRadius: 2, offset: const Offset(0, 1))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: sm.color, borderRadius: BorderRadius.circular(6)),
              child: Text(sm.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.4))),
          const SizedBox(width: 8),
          Text('#${o.number ?? o.id}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: c.text)),
          const Spacer(),
          Text(minsAgo(o.createdAt), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.textMute)),
        ]),
        const SizedBox(height: 8),
        for (final it in o.items.take(3)) Text('${it.quantity}× ${it.name}', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.text, height: 1.5)),
        if (o.items.length > 3) Text('+${o.items.length - 3} more', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.textMute)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Text('${o.customer} · ${o.orderType.toLowerCase()}', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.textMute))),
          Text(money(o.total), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c.text)),
        ]),
        if (col == 'new') Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [
          Icon(Icons.notifications, size: 12, color: const Color(0xFFFF6A00)), const SizedBox(width: 5),
          Text('Awaiting confirmation', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFFFF6A00))),
        ])),
        if (col == 'preparing') Padding(padding: const EdgeInsets.only(top: 10), child: _actBtn(c, Icons.inventory_2, 'Mark ready', c.primary, () => ctrl.markReady(o))),
        if (col == 'ready') Padding(padding: const EdgeInsets.only(top: 10), child: _actBtn(c, Icons.check_circle, 'Complete', c.green, () => ctrl.complete(o))),
      ]),
    );
  }

  Widget _actBtn(PosColors c, IconData icon, String label, Color color, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(padding: const EdgeInsets.symmetric(vertical: 10), alignment: Alignment.center,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: c.bg), const SizedBox(width: 6),
              Text(label, style: TextStyle(color: c.bg, fontWeight: FontWeight.w900, fontSize: 13))])),
      );
}
