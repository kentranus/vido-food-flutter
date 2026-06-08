import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/staff_store.dart';
import '../ui/pos_widgets.dart';

/// PIN Lock — faithful port of React PinLockScreen (Shared.jsx).
/// Glass-morphism card over a dark radial background with floating brand blobs,
/// 4-dot PIN + 3x4 keypad. Auto-submits at 4 digits. Default Manager 1234 / Cashier 0000.
/// managerOnly=true is used to gate restricted actions (returns the manager via onUnlock).
class PinLockScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool managerOnly;
  final ValueChanged<Staff> onUnlock;
  final VoidCallback? onCancel;
  const PinLockScreen({
    super.key,
    required this.title,
    this.subtitle = 'Sign in to continue',
    this.managerOnly = false,
    required this.onUnlock,
    this.onCancel,
  });
  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  String _pin = '';
  String _error = '';
  bool _busy = false;

  void _press(String d) {
    if (_busy || _pin.length >= 4) return;
    setState(() { _error = ''; _pin += d; });
    if (_pin.length == 4) _submit();
  }

  void _backspace() => setState(() { _error = ''; if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1); });

  Future<void> _submit() async {
    if (_pin.length < 4) return;
    setState(() { _busy = true; _error = ''; });
    final staff = widget.managerOnly ? await StaffStore.verifyManagerPin(_pin) : await StaffStore.verifyPin(_pin);
    if (!mounted) return;
    setState(() => _busy = false);
    if (staff != null) {
      if (!widget.managerOnly) StaffStore.current = staff;
      widget.onUnlock(staff);
    } else {
      setState(() { _error = widget.managerOnly ? 'Manager PIN required' : 'Invalid PIN'; _pin = ''; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        // dark radial background
        Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -1), radius: 1.2,
              colors: [Color(0xFF1A1F2E), Color(0xFF0B0D14), Color(0xFF07080D)], stops: [0.0, 0.55, 1.0],
            ),
          ),
        ),
        // floating brand blobs
        _blob(const Color(0xFFFF9500), 360, top: -60, left: 100, opacity: 0.55),
        _blob(const Color(0xFFFFCC00), 320, bottom: 20, right: 80, opacity: 0.55),
        _blob(const Color(0xFFFF5DA2), 260, top: 380, left: 520, opacity: 0.35),
        Center(child: SingleChildScrollView(padding: const EdgeInsets.all(18), child: _card())),
      ]),
    );
  }

  Widget _blob(Color color, double size, {double? top, double? bottom, double? left, double? right, double opacity = 0.5}) {
    return Positioned(
      top: top, bottom: bottom, left: left, right: right,
      child: IgnorePointer(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
          child: Container(width: size, height: size,
              decoration: BoxDecoration(color: color.withValues(alpha: opacity), shape: BoxShape.circle)),
        ),
      ),
    );
  }

  Widget _card() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
        child: Container(
          width: 360,
          padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 34),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            boxShadow: const [BoxShadow(color: Color(0x8C000000), blurRadius: 80, offset: Offset(0, 30))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const BrandMark(size: 76),
            const SizedBox(height: 18),
            Text(widget.title.isEmpty ? 'Enter PIN' : widget.title,
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 4),
            Text(widget.subtitle, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.6))),
            const SizedBox(height: 24),
            // dots
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < 4; i++) Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 15, height: 15,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? const Color(0xFFFFCC00) : Colors.white.withValues(alpha: 0.14),
                    boxShadow: i < _pin.length ? const [BoxShadow(color: Color(0xB3FFCC00), blurRadius: 12)] : null,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            if (_error.isNotEmpty) Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0x2EEF4444),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x59EF4444)),
                ),
                child: Text(_error, style: const TextStyle(color: Color(0xFFFFB4B4), fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ),
            // keypad 3x4
            GridView.count(
              crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.55,
              children: [
                for (var d = 1; d <= 9; d++) _key('$d', () => _press('$d')),
                widget.onCancel != null
                    ? _key('Cancel', widget.onCancel!, small: true, color: const Color(0xFFFF8A8A))
                    : const SizedBox.shrink(),
                _key('0', () => _press('0')),
                _key('⌫', _backspace, fontSize: 20),
              ],
            ),
            if (!widget.managerOnly) Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Text('Default Manager: 1234 · Cashier: 0000',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.4), fontWeight: FontWeight.w700, fontStyle: FontStyle.italic)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _key(String label, VoidCallback onTap, {double fontSize = 22, bool small = false, Color? color}) {
    return Material(
      color: Colors.white.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(color: color ?? Colors.white, fontSize: small ? 13 : fontSize, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}
