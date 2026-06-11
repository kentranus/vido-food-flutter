import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api.dart';
import '../pax.dart';
import '../ui/pos_theme.dart';
import '../ui/pos_widgets.dart';

/// Kiosk Setup — restores the React-era "Kiosk / Online" settings (SettingsView
/// Kiosk tab + the kiosk-side settings modal) into the Flutter app.
///
/// Three sections, all stored under settings key `kiosk`:
///  • hub      — POS Hub connection fields (saved for LAN mode; kiosk orders
///               currently flow through the cloud exactly as before).
///  • auto     — per-source auto-handling toggles (kiosk vs online). Defaults
///               preserve current behavior: kiosk kitchen-ticket auto-print ON
///               (it was hardcoded on), everything else OFF.
///  • kioskPax — separate PAX terminal for kiosk Pay Now (TCP/IP / Serial
///               Number / USB). When disabled the kiosk keeps using the POS
///               payment settings, exactly as before.
///
/// `KioskSetupPanel` is the reusable form (embedded in POS Settings → Kiosk
/// Setup tab). `KioskSettingsScreen` wraps it full-screen for the kiosk hidden
/// PIN flow and adds the Exit Kiosk button (previous behavior preserved).

Map<String, dynamic> _asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Reads the kiosk auto-handling flags with behavior-preserving defaults.
/// kioskKitchen defaults TRUE (auto-print was previously hardcoded on for
/// kiosk orders); every other flag defaults FALSE.
bool kioskAutoFlag(Map<String, dynamic> auto, String key) {
  final v = auto[key];
  if (v is bool) return v;
  return key == 'kioskKitchen';
}

class KioskSetupPanel extends StatefulWidget {
  /// Hidden inside the kiosk PIN screen (hub test etc. still available).
  const KioskSetupPanel({super.key});
  @override
  State<KioskSetupPanel> createState() => _KioskSetupPanelState();
}

class _KioskSetupPanelState extends State<KioskSetupPanel> {
  bool _loading = true, _busy = false;
  String _hubStatus = '', _paxStatus = '';

  // hub
  bool _hubEnabled = false;
  final _hubUrl = TextEditingController();
  final _storeId = TextEditingController();
  final _stationId = TextEditingController();

  // auto-handling (kiosk / online)
  bool _kioskAccept = false, _kioskKitchen = true, _kioskReceipt = false;
  bool _onlineAccept = false, _onlineKitchen = false, _onlineReceipt = false;

  // kiosk PAX
  bool _paxEnabled = false;
  String _paxMode = 'tcp';
  final _paxIp = TextEditingController();
  final _paxPort = TextEditingController(text: '10009');
  final _paxTimeout = TextEditingController(text: '60000');
  final _paxSerial = TextEditingController();
  bool _paxTip = true, _paxSdk = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final s = await Api.instance.getSettings();
    if (!mounted) return;
    final kiosk = _asMap(_asMap(s['settings'])['kiosk']);
    final hub = _asMap(kiosk['hub']);
    final auto = _asMap(kiosk['auto']);
    final pax = _asMap(kiosk['kioskPax']);
    setState(() {
      _hubEnabled = hub['enabled'] == true;
      _hubUrl.text = '${hub['hubUrl'] ?? ''}';
      _storeId.text = '${hub['storeId'] ?? ''}';
      _stationId.text = '${hub['stationId'] ?? ''}';
      _kioskAccept = kioskAutoFlag(auto, 'kioskAccept');
      _kioskKitchen = kioskAutoFlag(auto, 'kioskKitchen');
      _kioskReceipt = kioskAutoFlag(auto, 'kioskReceipt');
      _onlineAccept = kioskAutoFlag(auto, 'onlineAccept');
      _onlineKitchen = kioskAutoFlag(auto, 'onlineKitchen');
      _onlineReceipt = kioskAutoFlag(auto, 'onlineReceipt');
      _paxEnabled = pax['enabled'] == true;
      _paxMode = (pax['connectionMode'] ?? 'tcp').toString();
      _paxIp.text = '${pax['ip'] ?? ''}';
      _paxPort.text = '${pax['port'] ?? 10009}';
      _paxTimeout.text = '${pax['timeoutMs'] ?? 60000}';
      _paxSerial.text = '${pax['terminalSerial'] ?? ''}';
      _paxTip = pax['tipRequest'] != false;
      _paxSdk = pax['usePosLinkSdk'] != false;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final r = await Api.instance.saveSettings({'kiosk': {
      'hub': {
        'enabled': _hubEnabled, 'hubUrl': _hubUrl.text.trim(),
        'storeId': _storeId.text.trim(), 'stationId': _stationId.text.trim(),
      },
      'auto': {
        'kioskAccept': _kioskAccept, 'kioskKitchen': _kioskKitchen, 'kioskReceipt': _kioskReceipt,
        'onlineAccept': _onlineAccept, 'onlineKitchen': _onlineKitchen, 'onlineReceipt': _onlineReceipt,
      },
      'kioskPax': {
        'enabled': _paxEnabled, 'connectionMode': _paxMode, 'ip': _paxIp.text.trim(),
        'port': int.tryParse(_paxPort.text) ?? 10009, 'timeoutMs': int.tryParse(_paxTimeout.text) ?? 60000,
        'terminalSerial': _paxSerial.text.trim(), 'tipRequest': _paxTip, 'usePosLinkSdk': _paxSdk,
      },
    }});
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r['ok'] == true ? 'Kiosk settings saved' : 'Save failed'),
        backgroundColor: r['ok'] == true ? const Color(0xFF16A34A) : const Color(0xFFDC2626)));
  }

  Future<void> _testHub() async {
    final url = _hubUrl.text.trim();
    if (url.isEmpty) { setState(() => _hubStatus = 'Enter the POS Hub URL first'); return; }
    setState(() { _busy = true; _hubStatus = 'Testing…'; });
    try {
      final r = await http.get(Uri.parse('${url.replaceAll(RegExp(r'/+$'), '')}/health'))
          .timeout(const Duration(seconds: 6));
      setState(() => _hubStatus = r.statusCode == 200 ? 'Hub reachable ✓' : 'Hub responded ${r.statusCode}');
    } catch (e) { setState(() => _hubStatus = 'Not reachable: $e'); }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _testPax() async {
    setState(() { _busy = true; _paxStatus = 'Testing…'; });
    try {
      final r = await Pax.init();
      setState(() => _paxStatus = r['skipped'] == true
          ? 'Terminal bridge only on the POS device (mock here)'
          : 'Terminal SDK ready · ${r['sdk'] ?? ''}');
    } catch (e) { setState(() => _paxStatus = 'Failed: $e'); }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    if (_loading) return Center(child: CircularProgressIndicator(color: c.primary));
    return ListView(padding: const EdgeInsets.all(24), children: [
      Padding(padding: const EdgeInsets.only(bottom: 16),
          child: Text('Kiosk Setup', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c.text))),
      Text('Kiosk orders post to the cloud and appear on the POS board automatically — these options control how the POS handles them.',
          style: TextStyle(color: c.textMute, fontWeight: FontWeight.w600, fontSize: 13, height: 1.5)),

      _sect(c, 'Auto-handling — Kiosk orders'),
      _tg(c, 'Auto accept paid kiosk orders', _kioskAccept, (v) => setState(() => _kioskAccept = v)),
      _tg(c, 'Auto print kitchen ticket', _kioskKitchen, (v) => setState(() => _kioskKitchen = v)),
      _tg(c, 'Auto print customer receipt', _kioskReceipt, (v) => setState(() => _kioskReceipt = v)),

      _sect(c, 'Auto-handling — Online orders'),
      _tg(c, 'Auto accept new online orders (skips the takeover popup)', _onlineAccept, (v) => setState(() => _onlineAccept = v)),
      _tg(c, 'Auto print kitchen ticket (when auto-accepted)', _onlineKitchen, (v) => setState(() => _onlineKitchen = v)),
      _tg(c, 'Auto print customer receipt (when auto-accepted)', _onlineReceipt, (v) => setState(() => _onlineReceipt = v)),

      _sect(c, 'Kiosk payment terminal'),
      _tg(c, 'Use a separate PAX terminal for kiosk Pay Now', _paxEnabled, (v) => setState(() => _paxEnabled = v)),
      if (_paxEnabled) ...[
        PField(label: 'Connection Type', child: _dd(c, _paxMode, const {
          'tcp': 'TCP / IP', 'serial': 'Serial Number', 'usb': 'USB',
        }, (v) => setState(() => _paxMode = v))),
        if (_paxMode == 'tcp') ...[
          PField(label: 'PAX terminal IP', child: PInput(controller: _paxIp, hintText: '192.168.68.59')),
          Row(children: [
            Expanded(child: PField(label: 'Port', child: PInput(controller: _paxPort, keyboardType: TextInputType.number))),
            const SizedBox(width: 12),
            Expanded(child: PField(label: 'Timeout (ms)', child: PInput(controller: _paxTimeout, keyboardType: TextInputType.number))),
          ]),
        ],
        if (_paxMode == 'serial')
          PField(label: 'Terminal Serial Number', child: PInput(controller: _paxSerial, hintText: 'Enter terminal serial number')),
        if (_paxMode == 'usb') Container(
          padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(color: c.primaryA, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.primary)),
          child: Row(children: [Icon(Icons.usb, color: c.primary, size: 18), const SizedBox(width: 10),
            Expanded(child: Text('USB connection selected — plug the terminal into the kiosk over USB (PAX PosLink).',
                style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 13)))]),
        ),
        _tg(c, 'Show tip on PAX terminal when kiosk uses Pay Now', _paxTip, (v) => setState(() => _paxTip = v)),
        _tg(c, 'Use PosLink SDK', _paxSdk, (v) => setState(() => _paxSdk = v)),
        PButton(const Text('Test Kiosk PAX'), variant: PBtnVariant.ghost, expand: true, onPressed: _busy ? null : _testPax),
        if (_paxStatus.isNotEmpty) _status(c, _paxStatus),
      ] else
        Padding(padding: const EdgeInsets.only(top: 4),
            child: Text('Off — the kiosk uses the POS Payment Settings terminal (current behavior).',
                style: TextStyle(color: c.textDim, fontWeight: FontWeight.w600, fontSize: 12))),

      _sect(c, 'POS Hub connection (LAN)'),
      Text('For pairing kiosks to this POS over local Wi-Fi. Settings are saved now; kiosk orders continue to flow through the cloud.',
          style: TextStyle(color: c.textDim, fontWeight: FontWeight.w600, fontSize: 12, height: 1.5)),
      const SizedBox(height: 6),
      _tg(c, 'Enable POS Hub connection', _hubEnabled, (v) => setState(() => _hubEnabled = v)),
      PField(label: 'POS Hub URL', child: PInput(controller: _hubUrl, hintText: 'http://192.168.68.55:8787')),
      Row(children: [
        Expanded(child: PField(label: 'Store ID', child: PInput(controller: _storeId, hintText: 'shared across devices'))),
        const SizedBox(width: 12),
        Expanded(child: PField(label: 'This Device ID', child: PInput(controller: _stationId, hintText: 'kiosk-1'))),
      ]),
      PButton(const Text('Test POS Hub'), variant: PBtnVariant.ghost, expand: true, onPressed: _busy ? null : _testHub),
      if (_hubStatus.isNotEmpty) _status(c, _hubStatus),

      const SizedBox(height: 18),
      PButton(_busy ? const Text('…') : const Text('Save Kiosk Settings'), expand: true, onPressed: _busy ? null : _save),
      const SizedBox(height: 30),
    ]);
  }

  Widget _sect(PosColors c, String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Text(t.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: c.textMute, letterSpacing: .5)));

  Widget _tg(PosColors c, String label, bool value, ValueChanged<bool> onChanged) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: c.text, fontSize: 13))),
          Switch(value: value, activeThumbColor: c.primary, onChanged: onChanged),
        ]));

  Widget _dd(PosColors c, String value, Map<String, String> options, ValueChanged<String> onChanged) => Container(
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonHideUnderline(child: DropdownButton<String>(
          value: options.containsKey(value) ? value : options.keys.first, isExpanded: true, dropdownColor: c.panel,
          style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 14),
          items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) { if (v != null) onChanged(v); },
        )),
      );

  Widget _status(PosColors c, String s) => Padding(padding: const EdgeInsets.only(top: 10),
      child: Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(10)),
          child: Text(s, style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 13))));
}

/// Full-screen Kiosk Settings opened by the kiosk hidden PIN flow
/// (tap top-left 5× → Manager PIN → this screen). Pops `true` when the manager
/// chooses Exit Kiosk Mode — the caller then switches the device back to POS,
/// exactly like the previous exit dialog did.
class KioskSettingsScreen extends StatelessWidget {
  const KioskSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: c.panel, border: Border(bottom: BorderSide(color: c.border))),
          child: Row(children: [
            Text('Kiosk Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c.text)),
            const Spacer(),
            PButton(const Text('Exit Kiosk Mode'), variant: PBtnVariant.danger, onPressed: () async {
              final exit = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
                backgroundColor: c.panel,
                title: Text('Exit Kiosk?', style: TextStyle(color: c.text)),
                content: Text('Exit Kiosk mode and return to POS?', style: TextStyle(color: c.textMute)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text('Cancel', style: TextStyle(color: c.textMute))),
                  TextButton(onPressed: () => Navigator.pop(dctx, true), child: Text('Exit Kiosk', style: TextStyle(color: c.primary, fontWeight: FontWeight.w900))),
                ]));
              if (exit == true && context.mounted) Navigator.of(context).pop(true);
            }),
            const SizedBox(width: 10),
            PButton(const Text('Done'), variant: PBtnVariant.ghost, onPressed: () => Navigator.of(context).pop(false)),
          ]),
        ),
        const Expanded(child: KioskSetupPanel()),
      ])),
    );
  }
}
