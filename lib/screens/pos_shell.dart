import 'package:flutter/material.dart';
import '../api.dart';
import '../services/staff_store.dart';
import '../pos/order_view.dart';
import '../pos/online_orders.dart';
import '../ui/pos_theme.dart';
import '../ui/pos_widgets.dart';

/// App Shell — faithful port of React App.jsx TopBar + content router.
/// Top bar: brand · "Menu" dropdown (16 items, 2-col grid) · Payment pill ·
/// theme toggle · user menu (Sign out / Unlink). Content switches by `view`.
/// (Content screens are rebuilt one-by-one in later steps; unbuilt views show
/// a dark placeholder so the shell chrome can be reviewed on its own.)
class PosShell extends StatefulWidget {
  final Staff staff;
  final VoidCallback onLogout;
  final VoidCallback onUnlink;
  const PosShell({super.key, required this.staff, required this.onLogout, required this.onUnlink});
  @override
  State<PosShell> createState() => _PosShellState();
}

class _NavItem {
  final String id, label, desc, view;
  final String? tab;
  final IconData icon;
  const _NavItem(this.id, this.label, this.desc, this.icon, this.view, [this.tab]);
}

const List<_NavItem> _navItems = [
  _NavItem('sell', 'Sell / Order Entry', 'Create tickets and take payment', Icons.shopping_cart, 'sell'),
  _NavItem('board', 'Online Orders', 'Incoming web & kiosk orders board', Icons.assignment, 'board'),
  _NavItem('kiosk', 'Kiosk Mode', 'Customer self-order screen', Icons.desktop_windows, 'kiosk'),
  _NavItem('operations', 'Operations', 'Queue, closeout, refunds, devices', Icons.insights, 'operations'),
  _NavItem('orders', 'Order History', 'Look up completed receipts', Icons.receipt_long, 'orders'),
  _NavItem('reports', 'Reports', 'Sales, tender mix, staff totals', Icons.bar_chart, 'reports'),
  _NavItem('menu', 'Menu Items', 'Items, categories, pricing', Icons.restaurant, 'settings', 'menu'),
  _NavItem('staff', 'Staff & PINs', 'Cashier and manager access', Icons.people, 'settings', 'staff'),
  _NavItem('pax', 'Payment Settings', 'Card payment connection', Icons.credit_card, 'settings', 'pax'),
  _NavItem('hardware', 'Cash Drawer', 'Drawer/printer hardware setup', Icons.point_of_sale, 'settings', 'hardware'),
  _NavItem('display', 'Customer Display', 'Owner/customer screen setup', Icons.tv, 'settings', 'display'),
  _NavItem('hub', 'Kiosk / Online Orders', 'Connect kiosks and website orders to POS', Icons.wifi, 'settings', 'hub'),
  _NavItem('device', 'Device Mode', 'Run this tablet as POS or Kiosk', Icons.devices, 'settings', 'device'),
  _NavItem('shop', 'Shop Info', 'Receipt header, tax, branch info', Icons.store, 'settings', 'shop'),
  _NavItem('settings', 'System Settings', 'Version and diagnostics', Icons.settings, 'settings', 'about'),
  _NavItem('support', 'Daily Ops', 'Use reports and order history for closeout', Icons.support_agent, 'reports'),
];

const Map<String, String> _viewLabels = {
  'sell': 'Sell', 'board': 'Online', 'kiosk': 'Kiosk', 'operations': 'Ops',
  'orders': 'Orders', 'reports': 'Reports', 'settings': 'Settings',
};

class _PosShellState extends State<PosShell> {
  String _view = 'sell';
  String _settingsTab = 'pax';
  bool _menuOpen = false;
  bool _userMenuOpen = false;
  final ctrl = OnlineOrdersController();

  @override
  void initState() {
    super.initState();
    ctrl.start();
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  void _openView(String view, [String? tab]) {
    setState(() { _view = view; if (tab != null) _settingsTab = tab; _menuOpen = false; });
  }

  @override
  Widget build(BuildContext context) {
    // Whole subtree rebuilds when the theme is toggled.
    return ValueListenableBuilder<bool>(
      valueListenable: PT.isDark,
      builder: (context, _, _) {
        final c = PT.c;
        return Scaffold(
          backgroundColor: c.bg,
          body: Stack(children: [
            Column(children: [
              _topBar(c),
              Expanded(child: _content(c)),
            ]),
            // click-outside overlay for open dropdowns
            if (_menuOpen || _userMenuOpen)
              Positioned.fill(child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => setState(() { _menuOpen = false; _userMenuOpen = false; }),
              )),
            if (_menuOpen) _mainMenu(c),
            if (_userMenuOpen) _userMenu(c),
            // Full-screen takeover for the front NEW online order (any view).
            AnimatedBuilder(animation: ctrl, builder: (context, _) {
              final o = ctrl.queue.isNotEmpty ? ctrl.queue.first : null;
              if (o == null) return const SizedBox.shrink();
              return Positioned.fill(child: NewOrderTakeover(key: ValueKey(o.id), ctrl: ctrl, order: o));
            }),
          ]),
        );
      },
    );
  }

  // ----------------------------------------------------------------- top bar
  Widget _topBar(PosColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(color: c.panel, border: Border(bottom: BorderSide(color: c.border))),
      child: Row(children: [
        // brand
        const BrandMark(size: 46, radius: 12),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(Api.instance.storeName.isEmpty ? 'Vido Food' : Api.instance.storeName,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c.text)),
          Text('', style: TextStyle(fontSize: 11, color: c.textMute, fontWeight: FontWeight.w700)),
        ]),
        const Spacer(),
        // Menu button (brand gradient)
        GestureDetector(
          onTap: () => setState(() { _menuOpen = !_menuOpen; _userMenuOpen = false; }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              gradient: c.primaryG, borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: const Color(0xFFFF9500).withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 4))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.menu, size: 18, color: c.bg),
              const SizedBox(width: 8),
              Text('Menu', style: TextStyle(color: c.bg, fontWeight: FontWeight.w900, fontSize: 14)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
                child: Text(_viewLabels[_view] ?? 'POS', style: TextStyle(color: c.bg, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ),
        const Spacer(),
        // payment pill (terminal status — wired with the PAX screen later)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: c.redA, borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.wifi_off, size: 12, color: c.red),
            const SizedBox(width: 5),
            Text('Payment Offline', style: TextStyle(color: c.red, fontWeight: FontWeight.w800, fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 8),
        // theme toggle
        _circleBtn(c, PT.isDark.value ? Icons.dark_mode : Icons.light_mode, () => PT.toggle()),
        const SizedBox(width: 8),
        // user button
        GestureDetector(
          onTap: () => setState(() { _userMenuOpen = !_userMenuOpen; _menuOpen = false; }),
          child: Container(
            padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
            decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: c.border)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _avatar(c, widget.staff, 30),
              const SizedBox(width: 9),
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(widget.staff.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: c.text)),
                Text(widget.staff.role, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                    color: widget.staff.isManager ? c.primary : c.textMute)),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _circleBtn(PosColors c, IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(width: 32, height: 32, alignment: Alignment.center,
            decoration: BoxDecoration(color: c.card, shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: c.text)),
      );

  Widget _avatar(PosColors c, Staff s, double size) {
    final initials = s.name.trim().split(RegExp(r'\s+')).map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();
    return Container(
      width: size, height: size, alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: s.isManager ? c.primaryG : null,
        color: s.isManager ? null : c.blue,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Text(initials.isEmpty ? '?' : initials,
          style: TextStyle(color: s.isManager ? c.bg : Colors.white, fontWeight: FontWeight.w900, fontSize: size * 0.4)),
    );
  }

  // ----------------------------------------------------------------- dropdowns
  Widget _mainMenu(PosColors c) {
    return Positioned(
      top: 70, left: 0, right: 0,
      child: Center(
        child: Container(
          width: 620, constraints: const BoxConstraints(maxWidth: double.infinity),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.panel, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: c.shadow, blurRadius: 50, offset: const Offset(0, 18))],
          ),
          child: GridView.count(
            crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 4.3,
            children: [for (final it in _navItems) _menuItem(c, it)],
          ),
        ),
      ),
    );
  }

  Widget _menuItem(PosColors c, _NavItem it) {
    final active = _view == it.view && (it.tab == null || it.tab == 'pax');
    return GestureDetector(
      onTap: () => _openView(it.view, it.tab),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active ? c.primaryA : c.card,
          border: Border.all(color: active ? c.primary : c.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Container(width: 34, height: 34, alignment: Alignment.center,
              decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(8)),
              child: Icon(it.icon, size: 18, color: c.primary)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(it.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: c.text)),
            const SizedBox(height: 2),
            Text(it.desc, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.textMute, height: 1.25)),
          ])),
        ]),
      ),
    );
  }

  Widget _userMenu(PosColors c) {
    final s = widget.staff;
    return Positioned(
      top: 64, right: 20,
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: c.panel, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: c.shadow, blurRadius: 30, offset: const Offset(0, 10))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(14), color: c.card,
            child: Row(children: [
              _avatar(c, s, 48),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(s.name, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: c.text)),
                Text(s.role, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                    color: s.isManager ? c.primary : c.textMute)),
                const SizedBox(height: 4),
                Text('Flutter build', style: TextStyle(fontSize: 10, color: c.textDim, fontWeight: FontWeight.w700)),
              ])),
            ]),
          ),
          if (Api.instance.storeName.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
              child: Row(children: [
                Icon(Icons.store, size: 12, color: c.textMute), const SizedBox(width: 6),
                Expanded(child: Text(Api.instance.storeName, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c.textMute))),
              ]),
            ),
          _userMenuItem(c, Icons.logout, 'Sign out', () { setState(() => _userMenuOpen = false); widget.onLogout(); }),
          Divider(height: 1, color: c.border),
          _userMenuItem(c, Icons.wifi_off, 'Unlink device', () async {
            setState(() => _userMenuOpen = false);
            final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
              backgroundColor: c.panel,
              title: Text('Unlink device?', style: TextStyle(color: c.text)),
              content: Text('Unlink this device from the restaurant? You will need to sign in again.', style: TextStyle(color: c.textMute)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: c.textMute))),
                TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Unlink', style: TextStyle(color: c.red, fontWeight: FontWeight.w900))),
              ],
            ));
            if (ok == true) widget.onUnlink();
          }, color: c.red),
        ]),
      ),
    );
  }

  Widget _userMenuItem(PosColors c, IconData icon, String label, VoidCallback onTap, {Color? color}) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Icon(icon, size: 14, color: color ?? c.text), const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color ?? c.text)),
          ]),
        ),
      );

  // ----------------------------------------------------------------- content
  Widget _content(PosColors c) {
    // Faithfully-rebuilt views render for real; the rest show a placeholder.
    if (_view == 'sell') return OrderView(staff: widget.staff);
    if (_view == 'board') return OrdersBoard(ctrl: ctrl);
    // Each remaining view is rebuilt in a later step. Until then, a dark
    // placeholder keeps the shell consistent and shows what's coming.
    final label = {
      'sell': 'Sell / Order Entry', 'board': 'Online Orders', 'kiosk': 'Kiosk Mode',
      'operations': 'Operations', 'orders': 'Order History', 'reports': 'Reports',
      'settings': 'Settings · $_settingsTab',
    }[_view] ?? _view;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.build_circle_outlined, size: 48, color: c.textDim),
        const SizedBox(height: 12),
        Text(label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c.text)),
        const SizedBox(height: 6),
        Text('Đang dựng lại màn này theo bản React ở bước kế tiếp.',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textMute)),
      ]),
    );
  }
}
