import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';

/// Brand mark — a rounded yellow tile with the Vido "F"/logo feel.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 56});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFE066), C.brand, Color(0xFFFF9500)]),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [BoxShadow(color: C.brand.withValues(alpha: .4), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      alignment: Alignment.center,
      child: Text('F', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: size * 0.5)),
    );
  }
}

/// CLOUD LOGIN — links the device to a restaurant account (mirrors React).
class LoginScreen extends StatefulWidget {
  final VoidCallback onDone;
  const LoginScreen({super.key, required this.onDone});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _base = TextEditingController(text: Api.instance.baseUrl);
  bool _advanced = false, _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your restaurant email and password.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    final r = await Api.instance.login(_email.text, _password.text, base: _advanced ? _base.text : null);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['ok'] != true) { setState(() => _error = (r['error'] ?? 'Sign in failed').toString()); return; }
    widget.onDone();
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF3F4F6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );
  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 12),
        child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: C.textMute, letterSpacing: .5)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: C.panel,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: C.border),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .08), blurRadius: 40, offset: const Offset(0, 20))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const BrandMark(size: 56),
                  const SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: const [
                    Text('Vido Food', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: C.ink)),
                    SizedBox(height: 2),
                    Text('Sign in with your restaurant account', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.textMute)),
                  ]),
                ]),
                const Padding(
                  padding: EdgeInsets.only(top: 12, bottom: 6),
                  child: Text('This links the device to your restaurant so online orders arrive here. You only do this once.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.textMute, height: 1.4)),
                ),
                _label('Restaurant email'),
                TextField(controller: _email, decoration: _dec('owner@restaurant.com'), keyboardType: TextInputType.emailAddress,
                    autocorrect: false, textInputAction: TextInputAction.next),
                _label('Password'),
                TextField(controller: _password, decoration: _dec('••••••••'), obscureText: true, onSubmitted: (_) => _submit()),
                if (_advanced) ...[
                  _label('Server URL (advanced)'),
                  TextField(controller: _base, decoration: _dec(kDefaultBaseUrl), autocorrect: false),
                ],
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: C.redA, borderRadius: BorderRadius.circular(10)),
                    child: Text(_error!, style: const TextStyle(color: C.red, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                const SizedBox(height: 14),
                _YellowButton(
                  busy: _busy,
                  label: 'Sign in & link device',
                  onTap: _submit,
                ),
                TextButton(
                  onPressed: () => setState(() => _advanced = !_advanced),
                  child: Text('${_advanced ? 'Hide' : 'Advanced'} settings',
                      style: const TextStyle(color: C.textMute, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _YellowButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback onTap;
  const _YellowButton({required this.label, required this.onTap, this.busy = false});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: busy ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: C.brand,
          foregroundColor: C.ink,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.ink))
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
      ),
    );
  }
}

const _licenseMessages = {
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
  @override
  Widget build(BuildContext context) {
    final msg = _licenseMessages[widget.reason] ?? 'Access is locked.';
    return Scaffold(
      backgroundColor: C.bg,
      body: Center(
        child: Container(
          width: 420,
          margin: const EdgeInsets.all(18),
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.border)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 60, height: 60,
              decoration: const BoxDecoration(color: C.redA, shape: BoxShape.circle),
              child: const Icon(Icons.wifi_off_rounded, color: C.red, size: 26),
            ),
            const SizedBox(height: 12),
            const Text('App locked', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: C.ink)),
            const SizedBox(height: 6),
            Text(msg, style: const TextStyle(fontSize: 13, color: C.textMute, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            const Text('Please contact Vido to reactivate your account, then re-check.',
                style: TextStyle(fontSize: 12, color: C.textMute, height: 1.5), textAlign: TextAlign.center),
            const SizedBox(height: 14),
            _YellowButton(
              busy: _busy,
              label: 'Re-check now',
              onTap: () async { setState(() => _busy = true); await widget.onRecheck(); if (mounted) setState(() => _busy = false); },
            ),
            TextButton(onPressed: widget.onSwitch, child: const Text('Switch / unlink account',
                style: TextStyle(color: C.textMute, fontWeight: FontWeight.w800, fontSize: 12))),
          ]),
        ),
      ),
    );
  }
}
