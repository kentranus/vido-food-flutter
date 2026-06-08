import 'package:flutter/material.dart';
import 'api.dart';
import 'hardware.dart';
import 'pax.dart';
import 'theme.dart';

/// Settings — Shop Info / Payment terminal / Customer Display / Staff / Device / About.
/// Mirrors the React SettingsView tabs, cloud-backed via /api/settings + /api/staff.
class SettingsScreen extends StatefulWidget {
  final VoidCallback onEnterKiosk;
  const SettingsScreen({super.key, required this.onEnterKiosk});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic> _settings = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await Api.instance.getSettings();
    if (!mounted) return;
    setState(() {
      _settings = Map<String, dynamic>.from(s['settings'] ?? {});
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(backgroundColor: C.panel, elevation: 0, foregroundColor: C.ink,
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w900))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.brand))
          : ListView(padding: const EdgeInsets.all(12), children: [
              _ShopInfoSection(shop: Map<String, dynamic>.from(_settings['shop'] ?? {}), onSaved: _load),
              _PaymentSection(payment: Map<String, dynamic>.from(_settings['payment'] ?? {}), onSaved: _load),
              _HardwareSection(hardware: Map<String, dynamic>.from(_settings['hardware'] ?? {}), onSaved: _load),
              _DisplaySection(display: Map<String, dynamic>.from(_settings['customerDisplay'] ?? {}), onSaved: _load),
              const _StaffSection(),
              _DeviceSection(onEnterKiosk: widget.onEnterKiosk),
              const _AboutSection(),
              const SizedBox(height: 24),
            ]),
    );
  }
}

/// Reusable collapsible card shell.
class _Section extends StatelessWidget {
  final IconData icon;
  final Color tone;
  final String title, subtitle;
  final List<Widget> children;
  final bool initiallyExpanded;
  const _Section({required this.icon, required this.tone, required this.title, required this.subtitle, required this.children, this.initiallyExpanded = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: tone.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: tone, size: 20)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: C.ink)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: C.textMute, fontWeight: FontWeight.w600)),
          children: children,
        ),
      ),
    );
  }
}

Widget _field(String label, TextEditingController c, {String? hint, TextInputType? kb, String? prefix}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: C.textMute, letterSpacing: .4)),
        const SizedBox(height: 5),
        TextField(controller: c, keyboardType: kb, decoration: InputDecoration(
          hintText: hint, prefixText: prefix, isDense: true, filled: true, fillColor: C.bg,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none))),
      ]),
    );

Widget _saveBtn(bool busy, VoidCallback onTap, {String label = 'Save'}) => SizedBox(height: 48, width: double.infinity, child: ElevatedButton(
      onPressed: busy ? null : onTap,
      style: ElevatedButton.styleFrom(backgroundColor: C.brand, foregroundColor: C.ink, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      child: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
    ));

void _toast(BuildContext ctx, bool ok, [String? msg]) =>
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg ?? (ok ? 'Saved' : 'Save failed')), backgroundColor: ok ? C.green : C.red));

// ============================================================ Shop Info
class _ShopInfoSection extends StatefulWidget {
  final Map<String, dynamic> shop;
  final Future<void> Function() onSaved;
  const _ShopInfoSection({required this.shop, required this.onSaved});
  @override
  State<_ShopInfoSection> createState() => _ShopInfoSectionState();
}

class _ShopInfoSectionState extends State<_ShopInfoSection> {
  late final _name = TextEditingController(text: '${widget.shop['name'] ?? ''}');
  late final _branch = TextEditingController(text: '${widget.shop['branch'] ?? ''}');
  late final _tax = TextEditingController(text: ((((widget.shop['taxRate'] ?? 0) as num) * 100)).toStringAsFixed(2));
  late final _currency = TextEditingController(text: '${widget.shop['currencySymbol'] ?? '\$'}');
  late final _footer = TextEditingController(text: '${widget.shop['receiptFooter'] ?? ''}');
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    final r = await Api.instance.saveSettings({'shop': {
      'name': _name.text.trim(),
      'branch': _branch.text.trim(),
      'taxRate': (double.tryParse(_tax.text) ?? 0) / 100,
      'currencySymbol': _currency.text.trim().isEmpty ? '\$' : _currency.text.trim(),
      'receiptFooter': _footer.text.trim(),
    }});
    if (!mounted) return;
    setState(() => _busy = false);
    final ok = r['ok'] == true;
    _toast(context, ok);
    if (ok) await widget.onSaved();
  }

  @override
  Widget build(BuildContext context) => _Section(
        icon: Icons.store, tone: C.brandDark, title: 'Shop Info', subtitle: 'Receipt header, tax, branch',
        initiallyExpanded: true,
        children: [
          _field('Shop name', _name, hint: 'e.g. Boba Bliss'),
          _field('Branch / location', _branch, hint: 'e.g. Main Street'),
          Row(children: [
            Expanded(child: _field('Tax rate (%)', _tax, kb: const TextInputType.numberWithOptions(decimal: true), hint: '8.75')),
            const SizedBox(width: 10),
            Expanded(child: _field('Currency', _currency, hint: '\$')),
          ]),
          _field('Receipt footer', _footer, hint: 'Thank you! Visit us again'),
          _saveBtn(_busy, _save),
        ],
      );
}

// ============================================================ Payment terminal
class _PaymentSection extends StatefulWidget {
  final Map<String, dynamic> payment;
  final Future<void> Function() onSaved;
  const _PaymentSection({required this.payment, required this.onSaved});
  @override
  State<_PaymentSection> createState() => _PaymentSectionState();
}

class _PaymentSectionState extends State<_PaymentSection> {
  late final _ip = TextEditingController(text: '${widget.payment['ip'] ?? ''}');
  late final _port = TextEditingController(text: '${widget.payment['port'] ?? 10009}');
  late bool _askTip = widget.payment['askTip'] == true;
  late bool _autoSettle = widget.payment['autoSettlement'] != false;
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    final r = await Api.instance.saveSettings({'payment': {
      'connectionMode': 'tcp',
      'ip': _ip.text.trim(),
      'port': int.tryParse(_port.text) ?? 10009,
      'askTip': _askTip,
      'autoSettlement': _autoSettle,
    }});
    if (!mounted) return;
    setState(() => _busy = false);
    final ok = r['ok'] == true;
    _toast(context, ok);
    if (ok) await widget.onSaved();
  }

  Future<void> _testSale() async {
    final go = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Run test sale?'),
      content: const Text('Sends a \$0.01 test to the card terminal at the configured IP. The card holder can cancel on the terminal.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Run')),
      ]));
    if (go != true || !mounted) return;
    final ip = _ip.text.trim();
    _toast(context, true, ip.isEmpty ? 'Running test approval…' : 'Sending \$0.01 to $ip…');
    try {
      final res = await Pax.sale(amount: 0.01, host: ip.isEmpty ? null : ip, port: int.tryParse(_port.text) ?? 10009);
      if (!mounted) return;
      if (res.approved) {
        _toast(context, true, res.simulated
            ? 'Test approved (no terminal — simulated)'
            : 'Approved · ${res.cardType} ••${res.cardLast4} · auth ${res.authCode}');
      } else {
        _toast(context, false, 'Declined${res.message.isNotEmpty ? ': ${res.message}' : ''}');
      }
    } catch (e) {
      if (mounted) _toast(context, false, 'Terminal error: $e');
    }
  }

  @override
  Widget build(BuildContext context) => _Section(
        icon: Icons.credit_card, tone: C.kiosk, title: 'Payment Settings', subtitle: 'Card terminal connection',
        children: [
          _field('Terminal IP', _ip, hint: '192.168.x.x'),
          _field('Port', _port, kb: TextInputType.number, hint: '10009'),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _askTip, activeThumbColor: C.brandDark, onChanged: (v) => setState(() => _askTip = v),
            title: const Text('Ask for tip on terminal', style: TextStyle(fontWeight: FontWeight.w700))),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _autoSettle, activeThumbColor: C.green, onChanged: (v) => setState(() => _autoSettle = v),
            title: const Text('Auto batch settlement (3:00 AM)', style: TextStyle(fontWeight: FontWeight.w700))),
          const SizedBox(height: 6),
          _saveBtn(_busy, _save),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _testSale, icon: const Icon(Icons.bolt), label: const Text('Run test sale (\$0.01)'),
            style: OutlinedButton.styleFrom(foregroundColor: C.ink, side: const BorderSide(color: C.border), minimumSize: const Size.fromHeight(46))),
        ],
      );
}

// ============================================================ Hardware (cash drawer)
class _HardwareSection extends StatefulWidget {
  final Map<String, dynamic> hardware;
  final Future<void> Function() onSaved;
  const _HardwareSection({required this.hardware, required this.onSaved});
  @override
  State<_HardwareSection> createState() => _HardwareSectionState();
}

class _HardwareSectionState extends State<_HardwareSection> {
  late String _mode = (widget.hardware['cashDrawerMode'] ?? 'android_intent').toString();
  late final _host = TextEditingController(text: '${widget.hardware['printerHost'] ?? ''}');
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    final r = await Api.instance.saveSettings({'hardware': {
      'cashDrawerMode': _mode,
      'printerHost': _host.text.trim(),
    }});
    if (!mounted) return;
    setState(() => _busy = false);
    final ok = r['ok'] == true;
    _toast(context, ok);
    if (ok) await widget.onSaved();
  }

  Future<void> _test() async {
    _toast(context, true, 'Opening cash drawer…');
    try {
      final r = await CashDrawer.open(mode: _mode, printerHost: _host.text.trim().isEmpty ? null : _host.text.trim());
      if (!mounted) return;
      if (r['skipped'] == true) {
        _toast(context, false, 'Cash drawer only works on the Android POS device');
      } else {
        _toast(context, r['ok'] == true, r['ok'] == true ? 'Drawer pulse sent' : 'Drawer did not respond');
      }
    } catch (e) {
      if (mounted) _toast(context, false, 'Drawer error: $e');
    }
  }

  @override
  Widget build(BuildContext context) => _Section(
        icon: Icons.point_of_sale, tone: C.brandDark, title: 'Cash Drawer', subtitle: 'Drawer / printer hardware',
        children: [
          const Text('How the drawer opens after a cash sale.', style: TextStyle(fontSize: 12, color: C.textMute, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _mode,
            decoration: InputDecoration(labelText: 'Drawer mode', isDense: true, filled: true, fillColor: C.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
            items: const [
              DropdownMenuItem(value: 'android_intent', child: Text('Built-in POS drawer')),
              DropdownMenuItem(value: 'network_escpos', child: Text('Network receipt printer')),
              DropdownMenuItem(value: 'usb_escpos', child: Text('USB receipt printer')),
            ],
            onChanged: (v) => setState(() => _mode = v ?? _mode),
          ),
          const SizedBox(height: 12),
          if (_mode == 'network_escpos') _field('Printer IP', _host, hint: '192.168.x.x'),
          _saveBtn(_busy, _save),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _test, icon: const Icon(Icons.outbox), label: const Text('Test open drawer'),
            style: OutlinedButton.styleFrom(foregroundColor: C.ink, side: const BorderSide(color: C.border), minimumSize: const Size.fromHeight(46))),
        ],
      );
}

// ============================================================ Customer Display
class _DisplaySection extends StatefulWidget {
  final Map<String, dynamic> display;
  final Future<void> Function() onSaved;
  const _DisplaySection({required this.display, required this.onSaved});
  @override
  State<_DisplaySection> createState() => _DisplaySectionState();
}

class _DisplaySectionState extends State<_DisplaySection> {
  late bool _enabled = widget.display['enabled'] == true;
  late final _brand = TextEditingController(text: '${widget.display['brandName'] ?? ''}');
  late final _title = TextEditingController(text: '${widget.display['welcomeTitle'] ?? ''}');
  late final _subtitle = TextEditingController(text: '${widget.display['welcomeSubtitle'] ?? ''}');
  late final _footer = TextEditingController(text: '${widget.display['footerText'] ?? ''}');
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    final r = await Api.instance.saveSettings({'customerDisplay': {
      'enabled': _enabled,
      'brandName': _brand.text.trim(),
      'welcomeTitle': _title.text.trim(),
      'welcomeSubtitle': _subtitle.text.trim(),
      'footerText': _footer.text.trim(),
    }});
    if (!mounted) return;
    setState(() => _busy = false);
    final ok = r['ok'] == true;
    // Reflect the toggle on the attached second screen immediately.
    if (_enabled) {
      await CustomerDisplay.show();
      await CustomerDisplay.update({'state': 'idle', 'shop': {'name': _brand.text.trim()}});
    } else {
      await CustomerDisplay.hide();
    }
    if (!mounted) return;
    _toast(context, ok);
    if (ok) await widget.onSaved();
  }

  Future<void> _test() async {
    final shown = await CustomerDisplay.show();
    if (!mounted) return;
    if (!shown) { _toast(context, false, 'No second screen detected (connect an HDMI/USB-C display)'); return; }
    await CustomerDisplay.update({'state': 'idle', 'shop': {'name': _brand.text.trim()}});
    if (mounted) _toast(context, true, 'Showing on second screen');
  }

  @override
  Widget build(BuildContext context) => _Section(
        icon: Icons.tv, tone: C.online, title: 'Customer Display', subtitle: 'Second-screen welcome text',
        children: [
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _enabled, activeThumbColor: C.online, onChanged: (v) => setState(() => _enabled = v),
            title: const Text('Enable customer display', style: TextStyle(fontWeight: FontWeight.w700))),
          _field('Brand name', _brand, hint: 'Vido Food'),
          _field('Welcome title', _title, hint: 'Welcome'),
          _field('Welcome subtitle', _subtitle, hint: 'Order when you are ready'),
          _field('Footer text', _footer, hint: 'Thank you for supporting us'),
          _saveBtn(_busy, _save),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _test, icon: const Icon(Icons.cast), label: const Text('Test on second screen'),
            style: OutlinedButton.styleFrom(foregroundColor: C.ink, side: const BorderSide(color: C.border), minimumSize: const Size.fromHeight(46))),
        ],
      );
}

// ============================================================ Staff & PINs
class _StaffSection extends StatefulWidget {
  const _StaffSection();
  @override
  State<_StaffSection> createState() => _StaffSectionState();
}

class _StaffSectionState extends State<_StaffSection> {
  List<Map<String, dynamic>> _staff = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Api.instance.getStaff();
    if (!mounted) return;
    setState(() {
      _staff = ((r['staff'] ?? []) as List).map((e) => Map<String, dynamic>.from(e)).toList();
      _loading = false;
    });
  }

  Future<void> _add() async {
    final res = await showModalBottomSheet<Map<String, String>>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => const _StaffEditor());
    if (res == null) return;
    final r = await Api.instance.addStaff(res['name']!, res['email']!, res['password']!);
    if (!mounted) return;
    if (r['ok'] == true) { _toast(context, true, 'Staff added'); await _load(); }
    else { _toast(context, false, (r['error'] ?? 'Could not add').toString()); }
  }

  @override
  Widget build(BuildContext context) => _Section(
        icon: Icons.people, tone: C.green, title: 'Staff & PINs', subtitle: 'Cashier and manager access',
        children: [
          if (_loading) const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: C.brand))
          else if (_staff.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No staff yet.', style: TextStyle(color: C.textMute, fontWeight: FontWeight.w700)))
          else for (final m in _staff) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
            CircleAvatar(radius: 16, backgroundColor: C.brand.withValues(alpha: .25), child: Text('${m['name'] ?? '?'}'.isNotEmpty ? '${m['name']}'[0].toUpperCase() : '?', style: const TextStyle(fontWeight: FontWeight.w900, color: C.ink))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('${m['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink)),
                if (m['status'] == 'inactive') const Padding(padding: EdgeInsets.only(left: 6), child: Text('INACTIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: C.red))),
              ]),
              Text('${m['role'] ?? 'STAFF'} · ${m['email'] ?? ''}', style: const TextStyle(fontSize: 11, color: C.textMute, fontWeight: FontWeight.w700)),
            ])),
          ])),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: _add, icon: const Icon(Icons.person_add), label: const Text('Add staff'),
            style: OutlinedButton.styleFrom(foregroundColor: C.ink, side: const BorderSide(color: C.border), minimumSize: const Size.fromHeight(46))),
          const Padding(padding: EdgeInsets.only(top: 10), child: Text('Manager role required for: refunds, discounts, payment settings.', style: TextStyle(fontSize: 11, color: C.textMute, fontWeight: FontWeight.w600))),
        ],
      );
}

class _StaffEditor extends StatefulWidget {
  const _StaffEditor();
  @override
  State<_StaffEditor> createState() => _StaffEditorState();
}

class _StaffEditorState extends State<_StaffEditor> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pw = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(color: C.panel, borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Add staff', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: C.ink)),
          const SizedBox(height: 14),
          _field('Name', _name, hint: 'e.g. Mai'),
          _field('Email', _email, kb: TextInputType.emailAddress, hint: 'staff@shop.com'),
          _field('Password', _pw, hint: 'min 4 characters'),
          const SizedBox(height: 6),
          _saveBtn(false, () {
            final n = _name.text.trim(), e = _email.text.trim(), p = _pw.text;
            if (n.isEmpty || e.isEmpty || p.length < 4) { _toast(context, false, 'Name, email and a 4+ char password required'); return; }
            Navigator.pop(context, {'name': n, 'email': e, 'password': p});
          }, label: 'Add staff'),
        ]),
      ),
    );
  }
}

// ============================================================ Device mode
class _DeviceSection extends StatelessWidget {
  final VoidCallback onEnterKiosk;
  const _DeviceSection({required this.onEnterKiosk});
  @override
  Widget build(BuildContext context) => _Section(
        icon: Icons.tablet_mac, tone: C.kiosk, title: 'Device Mode', subtitle: 'Run this tablet as POS or Kiosk',
        children: [
          const Text('This device is in POS mode. Switch it to a customer-facing kiosk that takes self-orders. Long-press the store name inside kiosk to return.',
              style: TextStyle(fontSize: 13, color: C.textMute, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ElevatedButton.icon(onPressed: () async {
            final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
              title: const Text('Switch to Kiosk mode?'),
              content: const Text('Customers will self-order. Long-press the store name in kiosk to exit.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Switch')),
              ]));
            if (ok == true) onEnterKiosk();
          }, icon: const Icon(Icons.tablet_mac), label: const Text('Switch to Kiosk mode'),
            style: ElevatedButton.styleFrom(backgroundColor: C.kiosk, foregroundColor: Colors.white, elevation: 0, minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
        ],
      );
}

// ============================================================ About
class _AboutSection extends StatelessWidget {
  const _AboutSection();
  @override
  Widget build(BuildContext context) => _Section(
        icon: Icons.info_outline, tone: C.pos, title: 'About', subtitle: 'Version and diagnostics',
        children: [
          _info('App', 'Vido Food — POS + Kiosk'),
          _info('Account', Api.instance.storeName),
          _info('Store ID', Api.instance.store?.id ?? '—'),
          _info('Business type', Api.instance.isFullService ? 'Full-service' : 'Quick-service'),
          _info('Backend', Api.instance.baseUrl),
          _info('Build', 'Flutter native'),
        ],
      );

  Widget _info(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(k, style: const TextStyle(fontSize: 12, color: C.textMute, fontWeight: FontWeight.w700)),
        Flexible(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: C.ink, fontWeight: FontWeight.w800))),
      ]));
}
