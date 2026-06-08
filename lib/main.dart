import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'screens.dart' hide LicenseLockScreen;
import 'orders.dart';
import 'pos_sell.dart';
import 'reports.dart';
import 'kiosk.dart';
import 'push.dart';
import 'services/staff_store.dart';
import 'screens/cloud_login.dart';
import 'screens/license_lock.dart';
import 'screens/pin_lock.dart';
import 'screens/pos_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initPush(); // FCM (Android) — safe no-op on web/iOS
  runApp(const VidoFoodApp());
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
        onLogout: () {}, onUnlink: () {});
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
    );
  }
}

/// Manage home — live online orders board + full-screen new-order takeover.
class HomeShell extends StatefulWidget {
  final VoidCallback onUnlink;
  final VoidCallback onEnterKiosk;
  const HomeShell({super.key, required this.onUnlink, required this.onEnterKiosk});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final ctrl = OnlineOrdersController();
  int _tab = 0; // 0 = Orders board, 1 = Sell (POS)
  @override
  void initState() {
    super.initState();
    const tabMap = {'orders': 0, 'sell': 1, 'reports': 2, 'more': 3};
    _tab = tabMap[Uri.base.queryParameters['tab']] ?? 0; // preview/deep-link
    ctrl.start();
  }

  @override
  void dispose() { ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.panel,
      appBar: AppBar(
        backgroundColor: C.panel,
        elevation: 0,
        titleSpacing: 16,
        title: Row(children: [
          const BrandMark(size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(Api.instance.storeName.isEmpty ? 'Vido Food' : Api.instance.storeName,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: C.ink)),
              Text(const ['Online orders', 'Sell · counter', 'Reports', 'More'][_tab], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.textMute)),
            ]),
          ),
        ]),
        actions: [
          if (_tab == 0) IconButton(tooltip: 'Refresh', onPressed: () => ctrl.refresh(), icon: const Icon(Icons.refresh, color: C.ink)),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: C.ink),
            onSelected: (v) { if (v == 'unlink') widget.onUnlink(); },
            itemBuilder: (_) => [const PopupMenuItem(value: 'unlink', child: Text('Unlink device'))],
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: ctrl,
        builder: (_, _) {
          final takeover = ctrl.queue.isNotEmpty ? ctrl.queue.first : null;
          return Stack(children: [
            IndexedStack(index: _tab, children: [
              OrdersBoard(ctrl: ctrl),
              const SellScreen(),
              const ReportsScreen(),
              MoreScreen(onUnlink: widget.onUnlink, onEnterKiosk: widget.onEnterKiosk),
            ]),
            // Incoming online order takes over the whole screen, any tab.
            if (takeover != null)
              Positioned.fill(child: NewOrderTakeover(key: ValueKey(takeover.id), order: takeover, ctrl: ctrl)),
          ]);
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: Badge(isLabelVisible: ctrl.queue.isNotEmpty, label: Text('${ctrl.queue.length}'), child: const Icon(Icons.receipt_long_outlined)),
            selectedIcon: const Icon(Icons.receipt_long),
            label: 'Orders',
          ),
          const NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale), label: 'Sell'),
          const NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Reports'),
          const NavigationDestination(icon: Icon(Icons.more_horiz), selectedIcon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
