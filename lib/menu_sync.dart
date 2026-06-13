import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api.dart';

/// Live menu sync. Holds an SSE connection to /api/events and fires
/// [onMenuChanged] whenever the store's menu changes ANYWHERE — an edit,
/// an 86-toggle, or a photo getting approved (server broadcasts `menu.updated`
/// / `menu.item.86`). This keeps POS + Kiosk in step with the online order
/// page and the Manager app: change it in one place, every screen updates.
/// Auto-reconnects with a 10s backoff (same pattern as online_orders.dart).
class MenuSyncListener {
  final void Function() onMenuChanged;
  MenuSyncListener(this.onMenuChanged);

  http.Client? _client;
  StreamSubscription<String>? _sub;
  bool _stopped = false;

  void start() {
    _stopped = false;
    _connect();
  }

  void stop() {
    _stopped = true;
    _sub?.cancel();
    _client?.close();
    _client = null;
  }

  Future<void> _connect() async {
    if (_stopped || !Api.instance.isLoggedIn) return;
    try {
      final uri = Uri.parse('${Api.instance.baseUrl}/api/events?token=${Uri.encodeComponent(Api.instance.token)}');
      _client = http.Client();
      final req = http.Request('GET', uri)..headers['accept'] = 'text/event-stream';
      final resp = await _client!.send(req);
      _sub = resp.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) {
          // Only react to menu events (event: menu.updated / menu.item.86),
          // never to order events — avoids needless menu reloads.
          if (line.startsWith('event:') && line.contains('menu')) onMenuChanged();
        },
        onDone: _reconnect, onError: (_) => _reconnect(), cancelOnError: true,
      );
    } catch (_) {
      _reconnect();
    }
  }

  void _reconnect() {
    _sub?.cancel();
    _client?.close();
    _client = null;
    if (_stopped) return;
    Future.delayed(const Duration(seconds: 10), _connect);
  }
}
