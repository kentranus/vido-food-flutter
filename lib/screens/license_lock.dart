import 'package:flutter/material.dart';
import '../ui/pos_theme.dart';
import '../ui/pos_widgets.dart';

/// License Lock — faithful port of React LicenseLockScreen (OnlineOrders.jsx).
/// Shown when the subscription/license is not allowed (offline grace handled upstream).
const Map<String, String> _licenseMessages = {
  'expired': 'Your subscription has expired.',
  'past_due': 'Your subscription payment is past due.',
  'tenant_suspended': 'This account has been suspended.',
  'tenant_cancelled': 'This account has been cancelled.',
  'tenant_pending': 'This account is not active yet.',
  'session_expired': 'Session expired — please sign in again.',
  'offline_no_cache': 'No internet and the offline period has ended.',
  'not_linked': 'This device is not linked to a restaurant.',
};

class LicenseLockScreen extends StatefulWidget {
  final String reason;
  final Future<void> Function() onRecheck;
  final VoidCallback onSwitch;
  const LicenseLockScreen({super.key, required this.reason, required this.onRecheck, required this.onSwitch});
  @override
  State<LicenseLockScreen> createState() => _LicenseLockScreenState();
}

class _LicenseLockScreenState extends State<LicenseLockScreen> {
  bool _busy = false;

  Future<void> _recheck() async {
    setState(() => _busy = true);
    await widget.onRecheck();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    final msg = _licenseMessages[widget.reason] ?? 'Access is locked.';
    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Container(
            width: 420,
            decoration: BoxDecoration(
              color: c.panel,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: c.shadow, blurRadius: 60, offset: const Offset(0, 20))],
            ),
            padding: const EdgeInsets.all(26),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              // lock icon circle
              Container(
                width: 60, height: 60, margin: const EdgeInsets.only(bottom: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.redA, shape: BoxShape.circle),
                child: Icon(Icons.wifi_off, color: c.red, size: 26),
              ),
              Text('POS locked', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: c.text)),
              const SizedBox(height: 6),
              Text(msg, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.textMute)),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 14, 0, 16),
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Please contact '),
                    TextSpan(text: 'Vido', style: TextStyle(fontWeight: FontWeight.w900, color: c.text)),
                    const TextSpan(text: ' to reactivate your account, then re-check.'),
                  ]),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textMute, height: 1.5),
                ),
              ),
              PButton(
                _busy
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.bg)),
                        const SizedBox(width: 8), const Text('Checking…'),
                      ])
                    : const Text('Re-check now'),
                expand: true, onPressed: _busy ? null : _recheck,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: GestureDetector(
                  onTap: widget.onSwitch,
                  child: Text('Switch / unlink account', textAlign: TextAlign.center,
                      style: TextStyle(color: c.textMute, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
