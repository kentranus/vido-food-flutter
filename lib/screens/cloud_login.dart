import 'package:flutter/material.dart';
import '../api.dart';
import '../ui/pos_theme.dart';
import '../ui/pos_widgets.dart';

/// Cloud Login — faithful port of React CloudLoginScreen (OnlineOrders.jsx).
/// Links the device to a restaurant account (one-time). Dark card, brand row,
/// email + password, Advanced (server URL) toggle, error box.
class CloudLoginScreen extends StatefulWidget {
  final VoidCallback onDone;
  const CloudLoginScreen({super.key, required this.onDone});
  @override
  State<CloudLoginScreen> createState() => _CloudLoginScreenState();
}

class _CloudLoginScreenState extends State<CloudLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  late final _baseUrl = TextEditingController(text: Api.instance.baseUrl);
  bool _showAdvanced = false;
  bool _busy = false;
  String _error = '';

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your restaurant email and password.');
      return;
    }
    setState(() { _busy = true; _error = ''; });
    final r = await Api.instance.login(_email.text, _password.text, base: _baseUrl.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['ok'] != true) { setState(() => _error = (r['error'] ?? 'Sign in failed').toString()); return; }
    widget.onDone();
  }

  Future<void> _forgot() async {
    final c = PT.c;
    final ctrl = TextEditingController(text: _email.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.panel,
        title: Text('Reset password', style: TextStyle(color: c.text, fontWeight: FontWeight.w900)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Enter your restaurant email. We will send a new temporary password.',
              style: TextStyle(color: c.textMute, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          PInput(controller: ctrl, hintText: 'owner@restaurant.com', keyboardType: TextInputType.emailAddress),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: c.textMute))),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: Text('Send', style: TextStyle(color: c.primary, fontWeight: FontWeight.w900))),
        ],
      ),
    );
    if (email == null || email.isEmpty) return;
    await Api.instance.forgotPassword(email);
    if (!mounted) return;
    setState(() => _error = '');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: c.green,
      content: const Text('If that email is registered, a new password has been emailed.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
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
              // brand row
              Row(children: [
                const BrandMark(size: 56, radius: 16),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('Vido Food POS', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: c.text)),
                  const SizedBox(height: 2),
                  Text('Sign in with your restaurant account', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.textMute)),
                ])),
              ]),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Text('This links the device to your restaurant so online orders arrive here. You only do this once.',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textMute, height: 1.4)),
              ),
              PField(label: 'Restaurant email', child: PInput(
                controller: _email, hintText: 'owner@restaurant.com',
                keyboardType: TextInputType.emailAddress, onSubmitted: (_) => _submit())),
              PField(label: 'Password', child: PInput(
                controller: _password, hintText: '••••••••', obscure: true, onSubmitted: (_) => _submit())),
              if (_showAdvanced)
                PField(label: 'Server URL (advanced)', hint: 'Leave as default unless told otherwise.',
                    child: PInput(controller: _baseUrl)),
              if (_error.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: c.redA, borderRadius: BorderRadius.circular(10)),
                  child: Text(_error, style: TextStyle(color: c.red, fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              const SizedBox(height: 6),
              PButton(
                _busy
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.bg)),
                        const SizedBox(width: 8), const Text('Signing in…'),
                      ])
                    : const Text('Sign in & link device'),
                size: PBtnSize.lg, expand: true, onPressed: _busy ? null : _submit,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: GestureDetector(
                  onTap: _busy ? null : _forgot,
                  child: Text('Forgot password?',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.primary, fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: GestureDetector(
                  onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                  child: Text('${_showAdvanced ? 'Hide' : 'Advanced'} settings',
                      textAlign: TextAlign.center,
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
