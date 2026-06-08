import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'kiosk.dart';
import 'push.dart';
import 'services/staff_store.dart';
import 'screens/cloud_login.dart';
import 'screens/license_lock.dart';
import 'screens/pin_lock.dart';
import 'screens/pos_shell.dart';
import 'pos/online_orders.dart';
import 'pos/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initPush(); // FCM (Android) — safe no-op on web/iOS
  runApp(const VidoFoodApp());
}

/// Demo online order for the ?preview= QA hook (never used in the real flow).
OnlineOrder _demoOnline(String status, String source) {
  final n = 1040 + status.hashCode % 50;
  return OnlineOrder.fromJson({
    'id': 'demo-$source-$status', 'number': '$n', 'status': status, 'source': source, 'orderType': 'PICKUP',
    'customer': source == 'Kiosk' ? 'Walk-in' : 'Jenny Pham', 'customerPhone': source == 'Kiosk' ? '' : '(203) 555-0142',
    'items': [
      {'nameSnapshot': 'Brown Sugar Boba', 'quantity': 2, 'modifiers': [{'optionName': 'Large'}, {'optionName': '50% sugar'}], 'notes': 'less ice'},
      {'nameSnapshot': 'Mango Green Tea', 'quantity': 1, 'modifiers': []},
    ],
    'subtotal': 19.25, 'tax': 1.68, 'tip': 2.00, 'total': 22.93,
    'paymentStatus': source == 'Kiosk' ? 'paid' : 'authorized',
    'createdAt': DateTime.now().subtract(const Duration(minutes: 3)).toIso8601String(),
  });
}

class VidoFoodApp extends StatelessWidget {
  const VidoFoodApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vido Food',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const RootGate(),
    );
  }
}

/// Launch gating — mirrors the React App.jsx: cloud login → license → home.
class RootGate extends StatefulWidget {
  const RootGate({super.key});
  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _loading = true;
  bool _cloudIn = false;
  bool _licChecked = false;
  bool _licAllowed = true;
  String _licReason = '';
  Timer? _licTimer;
  Staff? _staff; // local staff signed in via PIN (POS only; kiosk runs unattended)

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await Api.instance.load();
    // Optional provisioning: open with ?email=&password= to auto-link the device.
    if (!Api.instance.isLoggedIn) {
      final q = Uri.base.queryParameters;
      if ((q['email'] ?? '').isNotEmpty && (q['password'] ?? '').isNotEmpty) {
        await Api.instance.login(q['email']!, q['password']!);
      }
    }
    if (Uri.base.queryParameters['mode'] == 'kiosk') Api.instance.deviceMode = 'kiosk';
    if (!mounted) return;
    setState(() {
      _cloudIn = Api.instance.isLoggedIn;
      _loading = false;
    });
    if (_cloudIn) _startLicense();
  }

  void _startLicense() {
    _runLicense();
    registerPushForStore(); // FCM token → backend (Android); no-op on web/iOS
    _licTimer?.cancel();
    _licTimer = Timer.periodic(const Duration(minutes: 5), (_) => _runLicense());
  }

  Future<void> _runLicense() async {
    final r = await Api.instance.checkLicense();
    if (!mounted) return;
    setState(() { _licChecked = true; _licAllowed = r.allowed; _licReason = r.reason; });
  }

  @override
  void dispose() { _licTimer?.cancel(); super.dispose(); }

  Future<void> _unlink() async {
    await Api.instance.logout();
    _licTimer?.cancel();
    StaffStore.current = null;
    setState(() { _cloudIn = false; _licChecked = false; _licAllowed = true; _staff = null; });
  }

  @override
  Widget build(BuildContext context) {
    // QA/preview hook — render a single screen by name (e.g. ?preview=pin).
    // Only active with the explicit param; never affects the real flow.
    final preview = Uri.base.queryParameters['preview'];
    if (preview == 'pin') {
      return PinLockScreen(title: 'Vido Food Demo', subtitle: 'Enter PIN to sign in', onUnlock: (_) {});
    }
    if (preview == 'license') {
      return LicenseLockScreen(reason: 'expired', onRecheck: () async {}, onSwitch: () {});
    }
    if (preview == 'shell') {
      return PosShell(
        staff: Staff(id: 's1', name: 'Manager', role: 'manager', pin: '1234'),
        onLogout: () {}, onUnlink: () {}, onEnterKiosk: () {});
    }
    if (preview == 'takeover') {
      final ctrl = OnlineOrdersController();
      return Scaffold(backgroundColor: const Color(0xFF0F1419),
          body: NewOrderTakeover(ctrl: ctrl, order: _demoOnline('new', 'Online')));
    }
    if (preview == 'board') {
      final ctrl = OnlineOrdersController()
        ..orders = [_demoOnline('preparing', 'Online'), _demoOnline('preparing', 'Kiosk'), _demoOnline('ready', 'Online'), _demoOnline('new', 'Online')];
      return Scaffold(backgroundColor: const Color(0xFF0F1419), body: SafeArea(child: OrdersBoard(ctrl: ctrl)));
    }
    if (preview == 'settings') {
      return Scaffold(backgroundColor: const Color(0xFF0F1419),
          body: SafeArea(child: SettingsScreen(initialTab: Uri.base.queryParameters['tab'] ?? 'pax', onEnterKiosk: () {})));
    }
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: C.brand)));
    }
    if (!_cloudIn) {
      return CloudLoginScreen(onDone: () { setState(() => _cloudIn = true); _startLicense(); });
    }
    if (_licChecked && !_licAllowed) {
      return LicenseLockScreen(reason: _licReason, onRecheck: _runLicense, onSwitch: _unlink);
    }
    // Kiosk runs unattended — no staff PIN.
    if (Api.instance.deviceMode == 'kiosk') {
      return KioskScreen(onExit: () async {
        await Api.instance.setDeviceMode('manage');
        if (mounted) setState(() {});
      });
    }
    // Staff PIN sign-in (POS only) — mirrors React gate 3.
    if (_staff == null) {
      return PinLockScreen(
        title: Api.instance.storeName.isEmpty ? 'Vido Food' : Api.instance.storeName,
        subtitle: 'Enter PIN to sign in',
        onUnlock: (s) => setState(() => _staff = s),
      );
    }
    return PosShell(
      staff: _staff!,
      onLogout: () { StaffStore.current = null; setState(() => _staff = null); },
      onUnlink: _unlink,
      onEnterKiosk: () async { await Api.instance.setDeviceMode('kiosk'); if (mounted) setState(() {}); },
    );
  }
}

