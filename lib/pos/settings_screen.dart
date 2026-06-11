import 'package:flutter/material.dart';
import '../api.dart';
import '../hardware.dart';
import '../menu.dart' hide CartLine;
import '../pax.dart';
import '../services/staff_store.dart';
import '../ui/pos_theme.dart';
import '../ui/pos_widgets.dart';
import 'default_menu.dart';
import 'kiosk_setup.dart';
import 'order_models.dart' show money;

/// Settings — faithful port of React SettingsView (dark, left tab rail).
/// Tabs: Payment (PAX TCP/USB/Serial + test), Hardware (cash drawer multi-port),
/// Displays (2nd screen), Menu, Staff & PINs (local), Shop Info, Device Mode, About.
class SettingsScreen extends StatefulWidget {
  final String initialTab;
  final VoidCallback onEnterKiosk;
  const SettingsScreen({super.key, this.initialTab = 'pax', required this.onEnterKiosk});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _tab = widget.initialTab;
  Map<String, dynamic> _settings = {};
  bool _loading = true;

  static const _tabs = [
    (id: 'pax', label: 'Payment Settings', icon: Icons.credit_card),
    (id: 'hardware', label: 'Cash Drawer', icon: Icons.point_of_sale),
    (id: 'display', label: 'Customer Display', icon: Icons.tv),
    (id: 'menu', label: 'Menu Items', icon: Icons.restaurant),
    (id: 'staff', label: 'Staff & PINs', icon: Icons.people),
    (id: 'shop', label: 'Shop Info', icon: Icons.store),
    (id: 'ordering', label: 'Online Ordering', icon: Icons.schedule),
    (id: 'kiosk', label: 'Kiosk Setup', icon: Icons.storefront),
    (id: 'device', label: 'Device Mode', icon: Icons.devices),
    (id: 'about', label: 'About', icon: Icons.info_outline),
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final s = await Api.instance.getSettings();
    if (!mounted) return;
    setState(() { _settings = Map<String, dynamic>.from(s['settings'] ?? {}); _loading = false; });
  }

  Map<String, dynamic> _sec(String k) => Map<String, dynamic>.from(_settings[k] ?? {});

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    if (_loading) return Center(child: CircularProgressIndicator(color: c.primary));
    return Row(children: [
      // left tab rail
      Container(
        width: 230,
        decoration: BoxDecoration(color: c.panel, border: Border(right: BorderSide(color: c.border))),
        child: ListView(padding: const EdgeInsets.all(10), children: [
          for (final t in _tabs) _tabBtn(c, t.id, t.label, t.icon),
        ]),
      ),
      Expanded(child: _body(c)),
    ]);
  }

  Widget _tabBtn(PosColors c, String id, String label, IconData icon) {
    final active = _tab == id;
    return GestureDetector(
      onTap: () => setState(() => _tab = id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(color: active ? c.primaryA : Colors.transparent, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? c.primary : Colors.transparent)),
        child: Row(children: [
          Icon(icon, size: 18, color: active ? c.primary : c.textMute),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: active ? c.text : c.textMute)),
        ]),
      ),
    );
  }

  Widget _body(PosColors c) {
    final child = switch (_tab) {
      'pax' => _PaymentTab(payment: _sec('payment'), onSaved: _load),
      'hardware' => _HardwareTab(hardware: _sec('hardware'), onSaved: _load),
      'display' => _DisplayTab(display: _sec('customerDisplay'), onSaved: _load),
      'menu' => const _MenuTab(),
      'staff' => const _StaffTab(),
      'shop' => _ShopTab(shop: _sec('shop'), onSaved: _load),
      'ordering' => _OrderingTab(storefront: _sec('storefront'), onSaved: _load),
      'kiosk' => const KioskSetupPanel(),
      'device' => _DeviceTab(onEnterKiosk: widget.onEnterKiosk),
      _ => const _AboutTab(),
    };
    return Container(color: c.bg, child: child);
  }
}

// shared form helpers --------------------------------------------------------
Widget _h(PosColors c, String t) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(t, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c.text)));

Widget _section(PosColors c, String t) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Text(t.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: c.textMute, letterSpacing: .5)));

void _toast(BuildContext ctx, bool ok, String msg) => ScaffoldMessenger.of(ctx).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: ok ? const Color(0xFF16A34A) : const Color(0xFFDC2626)));

Widget _toggle(PosColors c, String label, bool value, ValueChanged<bool> onChanged) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: c.text, fontSize: 13))),
        Switch(value: value, activeThumbColor: c.primary, onChanged: onChanged),
      ]));

// ============================================================ Payment tab
class _PaymentTab extends StatefulWidget {
  final Map<String, dynamic> payment;
  final Future<void> Function() onSaved;
  const _PaymentTab({required this.payment, required this.onSaved});
  @override
  State<_PaymentTab> createState() => _PaymentTabState();
}

class _PaymentTabState extends State<_PaymentTab> {
  late String _mode = (widget.payment['connectionMode'] ?? 'tcp').toString();
  late final _ip = TextEditingController(text: '${widget.payment['ip'] ?? ''}');
  late final _port = TextEditingController(text: '${widget.payment['port'] ?? 10009}');
  late final _timeout = TextEditingController(text: '${widget.payment['timeoutMs'] ?? 60000}');
  late final _serial = TextEditingController(text: '${widget.payment['terminalSerial'] ?? ''}');
  late bool _askTip = widget.payment['askTip'] == true;
  late bool _sdk = widget.payment['usePosLinkSdk'] != false;
  late bool _autoSettle = widget.payment['autoSettlement'] != false;
  bool _busy = false;
  String _status = '';

  Future<void> _save() async {
    setState(() => _busy = true);
    final r = await Api.instance.saveSettings({'payment': {
      'connectionMode': _mode, 'ip': _ip.text.trim(), 'port': int.tryParse(_port.text) ?? 10009,
      'timeoutMs': int.tryParse(_timeout.text) ?? 60000, 'terminalSerial': _serial.text.trim(),
      'askTip': _askTip, 'usePosLinkSdk': _sdk, 'autoSettlement': _autoSettle,
    }});
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(context, r['ok'] == true, r['ok'] == true ? 'Saved' : 'Save failed');
    if (r['ok'] == true) await widget.onSaved();
  }

  Future<void> _test() async {
    setState(() { _busy = true; _status = 'Testing…'; });
    try {
      final r = await Pax.init();
      setState(() => _status = r['skipped'] == true ? 'Terminal bridge only on the POS device (mock here)' : 'Terminal SDK ready · ${r['sdk'] ?? ''}');
    } catch (e) { setState(() => _status = 'Failed: $e'); }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _testSale() async {
    setState(() { _busy = true; _status = 'Running \$0.01 test sale…'; });
    try {
      final r = await Pax.sale(amount: 0.01, connectionMode: _mode, host: _ip.text.trim().isEmpty ? null : _ip.text.trim(),
          port: int.tryParse(_port.text) ?? 10009, terminalSerial: _serial.text.trim());
      setState(() => _status = r.approved
          ? (r.simulated ? 'Test approved (simulated)' : 'Approved · ${r.cardType} ••${r.cardLast4} · auth ${r.authCode}')
          : 'Declined: ${r.message}');
    } catch (e) { setState(() => _status = 'Error: $e'); }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    return ListView(padding: const EdgeInsets.all(24), children: [
      _h(c, 'Payment Settings'),
      _section(c, 'Payment Connection'),
      PField(label: 'Connection Type', child: _dropdown(c, _mode, const {
        'tcp': 'TCP / IP', 'serial': 'Serial Number', 'usb': 'USB',
      }, (v) => setState(() => _mode = v))),
      if (_mode == 'tcp') ...[
        PField(label: 'Terminal IP Address', child: PInput(controller: _ip, hintText: '192.168.68.59')),
        Row(children: [
          Expanded(child: PField(label: 'Port', child: PInput(controller: _port, keyboardType: TextInputType.number))),
          const SizedBox(width: 12),
          Expanded(child: PField(label: 'Timeout (ms)', child: PInput(controller: _timeout, keyboardType: TextInputType.number))),
        ]),
      ],
      if (_mode == 'serial') PField(label: 'Terminal Serial Number', child: PInput(controller: _serial, hintText: 'Enter terminal serial number')),
      if (_mode == 'usb') Container(
        padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(color: c.primaryA, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.primary)),
        child: Row(children: [Icon(Icons.usb, color: c.primary, size: 18), const SizedBox(width: 10),
          Expanded(child: Text('USB connection selected — plug the terminal into the POS over USB (PAX PosLink).', style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 13)))]),
      ),
      _section(c, 'Options'),
      _toggle(c, 'Ask for tip on terminal', _askTip, (v) => setState(() => _askTip = v)),
      _toggle(c, 'Use PosLink SDK', _sdk, (v) => setState(() => _sdk = v)),
      _toggle(c, 'Auto batch settlement (3:00 AM)', _autoSettle, (v) => setState(() => _autoSettle = v)),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: PButton(const Text('Test Connection'), variant: PBtnVariant.ghost, expand: true, onPressed: _busy ? null : _test)),
        const SizedBox(width: 10),
        Expanded(child: PButton(_busy ? const Text('…') : const Text('Save'), expand: true, onPressed: _busy ? null : _save)),
      ]),
      const SizedBox(height: 10),
      PButton(const Text('Run test sale (\$0.01)'), variant: PBtnVariant.ghost, expand: true, onPressed: _busy ? null : _testSale),
      if (_status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14),
          child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(10)),
              child: Text(_status, style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 13)))),
    ]);
  }
}

Widget _dropdown(PosColors c, String value, Map<String, String> options, ValueChanged<String> onChanged) => Container(
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(child: DropdownButton<String>(
        value: options.containsKey(value) ? value : options.keys.first, isExpanded: true, dropdownColor: c.panel,
        style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 14),
        items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (v) { if (v != null) onChanged(v); },
      )),
    );

// ============================================================ Hardware tab
class _HardwareTab extends StatefulWidget {
  final Map<String, dynamic> hardware;
  final Future<void> Function() onSaved;
  const _HardwareTab({required this.hardware, required this.onSaved});
  @override
  State<_HardwareTab> createState() => _HardwareTabState();
}

class _HardwareTabState extends State<_HardwareTab> {
  late String _mode = (widget.hardware['cashDrawerMode'] ?? 'android_intent').toString();
  late final _host = TextEditingController(text: '${widget.hardware['printerHost'] ?? ''}');
  late final _port = TextEditingController(text: '${widget.hardware['printerPort'] ?? 9100}');
  bool _busy = false;
  String _status = '';

  Future<void> _save() async {
    setState(() => _busy = true);
    final r = await Api.instance.saveSettings({'hardware': {
      'cashDrawerMode': _mode, 'printerHost': _host.text.trim(), 'printerPort': int.tryParse(_port.text) ?? 9100,
    }});
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(context, r['ok'] == true, r['ok'] == true ? 'Saved' : 'Save failed');
    if (r['ok'] == true) await widget.onSaved();
  }

  Future<void> _test() async {
    setState(() { _busy = true; _status = 'Opening drawer…'; });
    try {
      final r = await CashDrawer.open(mode: _mode, printerHost: _host.text.trim().isEmpty ? null : _host.text.trim(), printerPort: int.tryParse(_port.text) ?? 9100);
      setState(() => _status = r['skipped'] == true ? 'Cash drawer only on the Android POS device' : (r['ok'] == true ? 'Drawer pulse sent ✓' : 'No response'));
    } catch (e) { setState(() => _status = 'Error: $e'); }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    return ListView(padding: const EdgeInsets.all(24), children: [
      _h(c, 'Cash Drawer & Printer'),
      Text('How the drawer opens after a cash sale + which port the receipt printer uses.', style: TextStyle(color: c.textMute, fontWeight: FontWeight.w600, fontSize: 13)),
      _section(c, 'Cash Drawer'),
      PField(label: 'Drawer / printer port', child: _dropdown(c, _mode, const {
        'android_intent': 'Built-in POS drawer', 'network_escpos': 'Network receipt printer (TCP/ESC-POS)', 'usb_escpos': 'USB receipt printer (ESC-POS)',
      }, (v) => setState(() => _mode = v))),
      if (_mode == 'network_escpos') Row(children: [
        Expanded(flex: 2, child: PField(label: 'Printer IP', child: PInput(controller: _host, hintText: '192.168.x.x'))),
        const SizedBox(width: 12),
        Expanded(child: PField(label: 'Port', child: PInput(controller: _port, keyboardType: TextInputType.number))),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: PButton(const Text('Save'), expand: true, onPressed: _busy ? null : _save)),
        const SizedBox(width: 10),
        Expanded(child: PButton(const Text('Test open drawer'), variant: PBtnVariant.ghost, expand: true, onPressed: _busy ? null : _test)),
      ]),
      if (_status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14),
          child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(10)),
              child: Text(_status, style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 13)))),
      Padding(padding: const EdgeInsets.only(top: 16),
          child: Text('Kitchen tickets & receipts also print via the system printer (AirPrint / USB / Bluetooth) from the print dialog.',
              style: TextStyle(color: c.textDim, fontWeight: FontWeight.w600, fontSize: 12))),
    ]);
  }
}

// ============================================================ Display tab
class _DisplayTab extends StatefulWidget {
  final Map<String, dynamic> display;
  final Future<void> Function() onSaved;
  const _DisplayTab({required this.display, required this.onSaved});
  @override
  State<_DisplayTab> createState() => _DisplayTabState();
}

class _DisplayTabState extends State<_DisplayTab> {
  late bool _enabled = widget.display['enabled'] == true;
  late final _brand = TextEditingController(text: '${widget.display['brandName'] ?? ''}');
  late final _title = TextEditingController(text: '${widget.display['welcomeTitle'] ?? 'Welcome'}');
  late final _subtitle = TextEditingController(text: '${widget.display['welcomeSubtitle'] ?? ''}');
  bool _busy = false;
  String _status = '';

  Future<void> _save() async {
    setState(() => _busy = true);
    final r = await Api.instance.saveSettings({'customerDisplay': {
      'enabled': _enabled, 'brandName': _brand.text.trim(), 'welcomeTitle': _title.text.trim(), 'welcomeSubtitle': _subtitle.text.trim(),
    }});
    if (_enabled) { await CustomerDisplay.show(); await CustomerDisplay.update({'state': 'idle', 'shop': {'name': _brand.text.trim()}}); }
    else { await CustomerDisplay.hide(); }
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(context, r['ok'] == true, r['ok'] == true ? 'Saved' : 'Save failed');
    if (r['ok'] == true) await widget.onSaved();
  }

  Future<void> _test() async {
    final shown = await CustomerDisplay.show();
    if (!mounted) return;
    if (!shown) { setState(() => _status = 'No second screen detected (connect HDMI/USB-C display)'); return; }
    await CustomerDisplay.update({'state': 'idle', 'shop': {'name': _brand.text.trim()}});
    setState(() => _status = 'Showing on second screen ✓');
  }

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    return ListView(padding: const EdgeInsets.all(24), children: [
      _h(c, 'Customer Display'),
      Text('Second screen facing the customer (order summary + total). Updates live from the Sell screen.', style: TextStyle(color: c.textMute, fontWeight: FontWeight.w600, fontSize: 13)),
      const SizedBox(height: 8),
      _toggle(c, 'Enable customer display', _enabled, (v) => setState(() => _enabled = v)),
      PField(label: 'Brand name', child: PInput(controller: _brand, hintText: 'Vido Food')),
      PField(label: 'Welcome title', child: PInput(controller: _title, hintText: 'Welcome')),
      PField(label: 'Welcome subtitle', child: PInput(controller: _subtitle, hintText: 'Order when you are ready')),
      Row(children: [
        Expanded(child: PButton(const Text('Save'), expand: true, onPressed: _busy ? null : _save)),
        const SizedBox(width: 10),
        Expanded(child: PButton(const Text('Test on second screen'), variant: PBtnVariant.ghost, expand: true, onPressed: _busy ? null : _test)),
      ]),
      if (_status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14),
          child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(10)),
              child: Text(_status, style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 13)))),
    ]);
  }
}

// ============================================================ Menu tab (editor)
class _MenuTab extends StatefulWidget {
  const _MenuTab();
  @override
  State<_MenuTab> createState() => _MenuTabState();
}

class _MenuTabState extends State<_MenuTab> {
  final repo = MenuRepo();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    await repo.load();
    if (repo.items.isEmpty) { repo.categories = List.of(kDefaultCategories); repo.items = List.of(kDefaultMenu); }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _edit([MenuItem? it]) async {
    final res = await showDialog<Map<String, dynamic>>(context: context, barrierColor: PT.c.overlay,
        builder: (_) => _ItemEditor(item: it, categories: repo.categories));
    if (res == null) return;
    setState(() => _saving = true);
    final ok = await repo.upsertItem(res);
    if (mounted) { setState(() => _saving = false); _toast(context, ok, ok ? 'Saved' : 'Save failed'); if (ok) await _load(); }
  }

  Future<void> _delete(MenuItem it) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _confirm(context, 'Delete "${it.name}"?'));
    if (ok != true) return;
    setState(() => _saving = true);
    await repo.deleteItem(it.id);
    if (mounted) { setState(() => _saving = false); await _load(); }
  }

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    if (_loading) return Center(child: CircularProgressIndicator(color: c.primary));
    return Stack(children: [
      ListView(padding: const EdgeInsets.all(24), children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _h(c, 'Menu Items'),
          PButton(const Text('+ Add item'), onPressed: () => _edit()),
        ]),
        for (final cat in repo.categories) ...[
          _section(c, cat.name),
          for (final it in repo.items.where((i) => i.category == cat.id)) Container(
            margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
            child: Row(children: [
              Text(it.icon, style: const TextStyle(fontSize: 24)), const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.name, style: TextStyle(fontWeight: FontWeight.w800, color: c.text)),
                Text('${money(it.price)}${it.is86d ? '  · 86 (sold out)' : !it.available ? '  · hidden' : ''}',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: it.is86d ? c.red : c.textMute)),
              ])),
              IconButton(onPressed: () => _edit(it), icon: Icon(Icons.edit, color: c.textMute, size: 20)),
              IconButton(onPressed: () => _delete(it), icon: Icon(Icons.delete_outline, color: c.red, size: 20)),
            ]),
          ),
        ],
        const SizedBox(height: 40),
      ]),
      if (_saving) Container(color: Colors.black26, child: Center(child: CircularProgressIndicator(color: c.primary))),
    ]);
  }
}

class _ItemEditor extends StatefulWidget {
  final MenuItem? item;
  final List<MenuCategory> categories;
  const _ItemEditor({required this.item, required this.categories});
  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _price = TextEditingController(text: widget.item?.price.toStringAsFixed(2) ?? '');
  late final _icon = TextEditingController(text: widget.item?.icon ?? '🧋');
  late String _cat = widget.item?.category ?? (widget.categories.isNotEmpty ? widget.categories.first.id : '');
  late bool _available = widget.item?.available ?? true;
  late bool _is86 = widget.item?.is86d ?? false;

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    final isNew = widget.item == null;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(18)),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(isNew ? 'Add item' : 'Edit item', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c.text)),
          const SizedBox(height: 14),
          Row(children: [
            SizedBox(width: 64, child: PInput(controller: _icon)),
            const SizedBox(width: 10),
            Expanded(child: PInput(controller: _name, hintText: 'Name')),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: PInput(controller: _price, hintText: 'Price', keyboardType: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(child: _dropdown(c, _cat, {for (final cat in widget.categories) cat.id: cat.name}, (v) => setState(() => _cat = v))),
          ]),
          _toggle(c, 'Available (shown on menu)', _available, (v) => setState(() => _available = v)),
          _toggle(c, '86 — sold out today', _is86, (v) => setState(() => _is86 = v)),
          const SizedBox(height: 8),
          PButton(Text(isNew ? 'Add item' : 'Save changes'), expand: true, onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            final id = widget.item?.id ?? name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
            Navigator.of(context).pop({'id': id, 'name': name, 'icon': _icon.text.trim().isEmpty ? '🧋' : _icon.text.trim(),
              'price': double.tryParse(_price.text) ?? 0, 'category': _cat, 'available': _available, 'is86d': _is86});
          }),
        ]),
      ),
    );
  }
}

// ============================================================ Staff tab (local)
class _StaffTab extends StatefulWidget {
  const _StaffTab();
  @override
  State<_StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends State<_StaffTab> {
  List<Staff> _staff = [];
  bool _loading = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { final s = await StaffStore.load(); if (mounted) setState(() { _staff = s; _loading = false; }); }

  Future<void> _edit([Staff? s]) async {
    final res = await showDialog<Staff>(context: context, barrierColor: PT.c.overlay, builder: (_) => _StaffEditor(member: s));
    if (res == null) return;
    if (s == null) { await StaffStore.add(res); } else { await StaffStore.update(s.id, name: res.name, role: res.role, pin: res.pin, active: res.active); }
    await _load();
  }

  Future<void> _delete(Staff s) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _confirm(context, 'Delete "${s.name}"?'));
    if (ok != true) return;
    try { await StaffStore.remove(s.id); await _load(); }
    catch (e) { if (mounted) _toast(context, false, '$e'.replaceAll('Exception: ', '')); }
  }

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    if (_loading) return Center(child: CircularProgressIndicator(color: c.primary));
    return ListView(padding: const EdgeInsets.all(24), children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_h(c, 'Staff & PINs'), PButton(const Text('+ Add staff'), onPressed: () => _edit())]),
      Text('Manager role required for: discounts, refunds, voids, settings. Default Manager 1234 · Cashier 0000.', style: TextStyle(color: c.textMute, fontWeight: FontWeight.w600, fontSize: 12)),
      const SizedBox(height: 12),
      for (final s in _staff) Container(
        margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
        child: Row(children: [
          CircleAvatar(radius: 16, backgroundColor: s.isManager ? c.primary : c.blue,
              child: Text(s.name.isNotEmpty ? s.name[0].toUpperCase() : '?', style: TextStyle(color: s.isManager ? c.bg : Colors.white, fontWeight: FontWeight.w900))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Text(s.name, style: TextStyle(fontWeight: FontWeight.w800, color: c.text)),
              if (!s.active) Padding(padding: const EdgeInsets.only(left: 6), child: Text('INACTIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: c.red)))]),
            Text('${s.role} · PIN ••••', style: TextStyle(fontSize: 12, color: c.textMute, fontWeight: FontWeight.w700)),
          ])),
          IconButton(onPressed: () => _edit(s), icon: Icon(Icons.edit, color: c.textMute, size: 20)),
          IconButton(onPressed: () => _delete(s), icon: Icon(Icons.delete_outline, color: c.red, size: 20)),
        ]),
      ),
    ]);
  }
}

class _StaffEditor extends StatefulWidget {
  final Staff? member;
  const _StaffEditor({this.member});
  @override
  State<_StaffEditor> createState() => _StaffEditorState();
}

class _StaffEditorState extends State<_StaffEditor> {
  late final _name = TextEditingController(text: widget.member?.name ?? '');
  late final _pin = TextEditingController(text: widget.member?.pin ?? '');
  late String _role = widget.member?.role ?? 'cashier';
  late bool _active = widget.member?.active ?? true;
  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    return Dialog(backgroundColor: Colors.transparent, child: Container(
      constraints: const BoxConstraints(maxWidth: 420), padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(18)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.member == null ? 'Add staff' : 'Edit staff', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c.text)),
        const SizedBox(height: 14),
        PField(label: 'Name', child: PInput(controller: _name)),
        PField(label: 'PIN (4 digits)', child: PInput(controller: _pin, keyboardType: TextInputType.number)),
        PField(label: 'Role', child: _dropdown(c, _role, const {'manager': 'Manager', 'cashier': 'Cashier'}, (v) => setState(() => _role = v))),
        _toggle(c, 'Active (can sign in)', _active, (v) => setState(() => _active = v)),
        const SizedBox(height: 8),
        PButton(const Text('Save'), expand: true, onPressed: () {
          if (_name.text.trim().isEmpty || _pin.text.trim().length != 4) return;
          Navigator.of(context).pop(Staff(id: widget.member?.id ?? '', name: _name.text.trim(), role: _role, pin: _pin.text.trim(), active: _active));
        }),
      ]),
    ));
  }
}

// ============================================================ Shop tab
class _ShopTab extends StatefulWidget {
  final Map<String, dynamic> shop;
  final Future<void> Function() onSaved;
  const _ShopTab({required this.shop, required this.onSaved});
  @override
  State<_ShopTab> createState() => _ShopTabState();
}

class _ShopTabState extends State<_ShopTab> {
  late final _name = TextEditingController(text: '${widget.shop['name'] ?? ''}');
  late final _branch = TextEditingController(text: '${widget.shop['branch'] ?? ''}');
  late final _address = TextEditingController(text: '${widget.shop['address'] ?? ''}');
  late final _phone = TextEditingController(text: '${widget.shop['phone'] ?? ''}');
  late final _tax = TextEditingController(text: ((((widget.shop['taxRate'] ?? 0) as num) * 100)).toStringAsFixed(2));
  late final _bonus = TextEditingController(text: '${widget.shop['sizeLargeBonus'] ?? 0.75}');
  late final _currency = TextEditingController(text: '${widget.shop['currencySymbol'] ?? '\$'}');
  late final _footer = TextEditingController(text: '${widget.shop['receiptFooter'] ?? ''}');
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    final r = await Api.instance.saveSettings({'shop': {
      'name': _name.text.trim(), 'branch': _branch.text.trim(), 'address': _address.text.trim(), 'phone': _phone.text.trim(),
      'taxRate': (double.tryParse(_tax.text) ?? 0) / 100, 'sizeLargeBonus': double.tryParse(_bonus.text) ?? 0.75,
      'currencySymbol': _currency.text.trim().isEmpty ? '\$' : _currency.text.trim(), 'receiptFooter': _footer.text.trim(),
    }});
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(context, r['ok'] == true, r['ok'] == true ? 'Saved' : 'Save failed');
    if (r['ok'] == true) await widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    return ListView(padding: const EdgeInsets.all(24), children: [
      _h(c, 'Shop Info'),
      PField(label: 'Shop name', child: PInput(controller: _name, hintText: 'e.g. Boba Bliss')),
      PField(label: 'Branch / location', child: PInput(controller: _branch)),
      PField(label: 'Address', child: PInput(controller: _address)),
      PField(label: 'Phone', child: PInput(controller: _phone)),
      Row(children: [
        Expanded(child: PField(label: 'Tax rate (%)', child: PInput(controller: _tax, keyboardType: TextInputType.number))),
        const SizedBox(width: 12),
        Expanded(child: PField(label: 'Large size upcharge', child: PInput(controller: _bonus, keyboardType: TextInputType.number))),
        const SizedBox(width: 12),
        Expanded(child: PField(label: 'Currency', child: PInput(controller: _currency))),
      ]),
      PField(label: 'Receipt footer', child: PInput(controller: _footer, hintText: 'Thank you! Visit us again')),
      PButton(const Text('Save'), expand: true, onPressed: _busy ? null : _save),
    ]);
  }
}

// ============================================================ Online Ordering tab
// Drives the customer order page: business hours (per day), timezone, ASAP prep
// estimate, schedule windows, and pickup/schedule/delivery/pause toggles.
class _OrderingTab extends StatefulWidget {
  final Map<String, dynamic> storefront;
  final Future<void> Function() onSaved;
  const _OrderingTab({required this.storefront, required this.onSaved});
  @override
  State<_OrderingTab> createState() => _OrderingTabState();
}

class _DayHours { bool open; String start, end; _DayHours(this.open, this.start, this.end); }

class _OrderingTabState extends State<_OrderingTab> {
  static const _dow = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  late final _tz = TextEditingController(text: '${widget.storefront['timezone'] ?? 'America/New_York'}');
  late final _prep = TextEditingController(text: '${widget.storefront['prepMinutes'] ?? 15}');
  late final _wake = TextEditingController(text: '${widget.storefront['scheduleWakeMinutes'] ?? 30}');
  late int _slot = (widget.storefront['scheduleSlotMinutes'] as num?)?.toInt() ?? 15;
  late bool _pickup = widget.storefront['pickupEnabled'] != false;
  late bool _schedule = widget.storefront['scheduleEnabled'] != false;
  late bool _delivery = widget.storefront['deliveryEnabled'] == true;
  late bool _paused = widget.storefront['paused'] == true;
  late final List<_DayHours> _hours = _initHours();
  bool _busy = false;

  List<_DayHours> _initHours() {
    final raw = (widget.storefront['hours'] as List?) ?? [];
    return List.generate(7, (i) {
      final h = i < raw.length ? Map<String, dynamic>.from(raw[i]) : {};
      return _DayHours(h['open'] == true, '${h['start'] ?? '09:00'}', '${h['end'] ?? '21:00'}');
    });
  }

  Future<void> _pickTime(int dayIdx, bool isStart) async {
    final cur = (isStart ? _hours[dayIdx].start : _hours[dayIdx].end).split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(cur.isNotEmpty ? cur[0] : '9') ?? 9, minute: int.tryParse(cur.length > 1 ? cur[1] : '0') ?? 0),
    );
    if (picked == null) return;
    final hhmm = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() { if (isStart) { _hours[dayIdx].start = hhmm; } else { _hours[dayIdx].end = hhmm; } });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final r = await Api.instance.saveSettings({'storefront': {
      'timezone': _tz.text.trim().isEmpty ? 'America/New_York' : _tz.text.trim(),
      'prepMinutes': int.tryParse(_prep.text) ?? 15,
      'scheduleWakeMinutes': int.tryParse(_wake.text) ?? 30,
      'scheduleSlotMinutes': _slot,
      'pickupEnabled': _pickup,
      'scheduleEnabled': _schedule,
      'deliveryEnabled': _delivery,
      'paused': _paused,
      'hours': [for (final d in _hours) {'open': d.open, 'start': d.start, 'end': d.end}],
    }});
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(context, r['ok'] == true, r['ok'] == true ? 'Saved' : 'Save failed');
    if (r['ok'] == true) await widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    return ListView(padding: const EdgeInsets.all(24), children: [
      _h(c, 'Online Ordering'),
      Text('Controls your customer order page (order.vidofood.com). Hours decide Open/Closed and which Schedule times customers can pick.',
          style: TextStyle(color: c.textMute, fontWeight: FontWeight.w600, fontSize: 13, height: 1.5)),

      _section(c, 'Availability'),
      _toggle(c, 'Accept Pickup orders', _pickup, (v) => setState(() => _pickup = v)),
      _toggle(c, 'Allow Schedule for later', _schedule, (v) => setState(() => _schedule = v)),
      _toggle(c, 'Delivery (coming soon)', _delivery, (v) => setState(() => _delivery = v)),
      Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _paused ? c.red.withValues(alpha: .12) : c.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: _paused ? c.red : c.border)),
        child: _toggle(c, _paused ? '⏸  PAUSED — not accepting new orders' : 'Pause new orders (when slammed)', _paused, (v) => setState(() => _paused = v)),
      ),

      _section(c, 'Timing'),
      Row(children: [
        Expanded(child: PField(label: 'Prep time (min)', child: PInput(controller: _prep, keyboardType: TextInputType.number, hintText: '15'))),
        const SizedBox(width: 12),
        Expanded(child: PField(label: 'Surface schedule before (min)', child: PInput(controller: _wake, keyboardType: TextInputType.number, hintText: '30'))),
      ]),
      Row(children: [
        Expanded(child: PField(label: 'Timezone (IANA)', child: PInput(controller: _tz, hintText: 'America/New_York'))),
        const SizedBox(width: 12),
        Expanded(child: PField(label: 'Schedule slot', child: _slotPicker(c))),
      ]),
      Padding(padding: const EdgeInsets.only(top: 4), child: Text('ASAP shows "~$_asapRange min". Scheduled orders appear on the POS ${_wake.text} min before pickup.',
          style: TextStyle(color: c.textDim, fontWeight: FontWeight.w600, fontSize: 12))),

      _section(c, 'Business hours'),
      for (int i = 0; i < 7; i++) _dayRow(c, i),

      const SizedBox(height: 20),
      PButton(_busy ? const Text('Saving…') : const Text('Save'), expand: true, onPressed: _busy ? null : _save),
      const SizedBox(height: 30),
    ]);
  }

  String get _asapRange { final p = int.tryParse(_prep.text) ?? 15; return '$p-${p + 5}'; }

  Widget _slotPicker(PosColors c) => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
        child: DropdownButtonHideUnderline(child: DropdownButton<int>(
          value: _slot, isExpanded: true, dropdownColor: c.panel, style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 13),
          items: const [DropdownMenuItem(value: 15, child: Text('15 minutes')), DropdownMenuItem(value: 30, child: Text('30 minutes'))],
          onChanged: (v) => setState(() => _slot = v ?? 15),
        )),
      );

  Widget _dayRow(PosColors c, int i) {
    final d = _hours[i];
    return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
      SizedBox(width: 96, child: Text(_dow[i], style: TextStyle(fontWeight: FontWeight.w800, color: c.text, fontSize: 13))),
      Switch(value: d.open, activeThumbColor: c.primary, onChanged: (v) => setState(() => d.open = v)),
      const SizedBox(width: 8),
      if (d.open) ...[
        _timeChip(c, d.start, () => _pickTime(i, true)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('–', style: TextStyle(color: c.textMute, fontWeight: FontWeight.w900))),
        _timeChip(c, d.end, () => _pickTime(i, false)),
      ] else
        Text('Closed', style: TextStyle(color: c.textDim, fontWeight: FontWeight.w700, fontSize: 13)),
    ]));
  }

  Widget _timeChip(PosColors c, String hhmm, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.border)),
          child: Text(_fmt12(hhmm), style: TextStyle(fontWeight: FontWeight.w800, color: c.text, fontSize: 13)),
        ),
      );

  static String _fmt12(String hhmm) {
    final p = hhmm.split(':'); if (p.length < 2) return hhmm;
    final h = int.tryParse(p[0]) ?? 0; final m = p[1];
    final ap = h < 12 ? 'AM' : 'PM'; final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m $ap';
  }
}

// ============================================================ Device tab
class _DeviceTab extends StatelessWidget {
  final VoidCallback onEnterKiosk;
  const _DeviceTab({required this.onEnterKiosk});
  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    return ListView(padding: const EdgeInsets.all(24), children: [
      _h(c, 'Device Mode'),
      Text('Run this tablet as a full POS or a customer self-order Kiosk. Switching to Kiosk locks the customer screen; long-press the store name in kiosk to return.',
          style: TextStyle(color: c.textMute, fontWeight: FontWeight.w600, fontSize: 13, height: 1.5)),
      const SizedBox(height: 16),
      PButton(const Text('Switch to Kiosk mode'), expand: true, onPressed: () async {
        final ok = await showDialog<bool>(context: context, builder: (_) => _confirm(context, 'Switch to Kiosk mode? Customers will self-order.'));
        if (ok == true) onEnterKiosk();
      }),
    ]);
  }
}

// ============================================================ About tab
class _AboutTab extends StatelessWidget {
  const _AboutTab();
  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    Widget row(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: TextStyle(color: c.textMute, fontWeight: FontWeight.w700, fontSize: 13)),
          Flexible(child: Text(v, textAlign: TextAlign.right, style: TextStyle(color: c.text, fontWeight: FontWeight.w800, fontSize: 13))),
        ]));
    return ListView(padding: const EdgeInsets.all(24), children: [
      _h(c, 'About'),
      row('App', 'Vido Food — POS + Kiosk'),
      row('Account', Api.instance.storeName),
      row('Store ID', Api.instance.store?.id ?? '—'),
      row('Business type', Api.instance.isFullService ? 'Full-service' : 'Quick-service'),
      row('Backend', Api.instance.baseUrl),
      row('Platform', 'Flutter (iOS + Android)'),
    ]);
  }
}

Widget _confirm(BuildContext context, String msg) {
  final c = PT.c;
  return AlertDialog(
    backgroundColor: c.panel,
    content: Text(msg, style: TextStyle(color: c.text)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: c.textMute))),
      TextButton(onPressed: () => Navigator.pop(context, true), child: Text('OK', style: TextStyle(color: c.red, fontWeight: FontWeight.w900))),
    ],
  );
}
