import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api.dart';
import 'pos/online_orders.dart';

/// FCM "new order" push so the POS rings even when the app is closed / locked.
/// Android (google-services.json) + iOS (GoogleService-Info.plist + APNs key).
/// No-ops on web.
///
/// The backend (fcm.js) sends a `notification` payload + android channel_id
/// `orders_v2` with sound `order_alert`, so Android auto-displays the heads-up
/// alert when the app is in the background/terminated. iOS shows the APNs alert
/// natively. In the foreground we surface the alert + refresh the board.

const _channelId = 'orders_v2';

bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

/// Background/terminated message handler. Android auto-displays the server's
/// `notification` payload on the orders_v2 channel, so this only needs to exist
/// (FCM requires a registered handler). Must be a top-level entry point.
@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage message) async {}

final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

bool get _supported => !kIsWeb && (_isAndroid || _isIOS);

bool _inited = false;

/// Called once at app startup (before runApp). Initializes Firebase + (Android)
/// the high-importance "orders_v2" channel, and registers the background handler.
Future<void> initPush() async {
  if (!_supported || _inited) return;
  _inited = true;
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_bgHandler);

    if (_isAndroid) {
      // High-importance channel with the custom bell. A channel's sound is locked
      // once created, so the id matches the server's (orders_v2) — never reuse an
      // old default-sound id. sound = raw resource name (res/raw/order_alert.wav).
      const channel = AndroidNotificationChannel(
        _channelId, 'New orders',
        description: 'Incoming online & kiosk orders',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('order_alert'),
        enableVibration: true,
      );
      final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(channel);
      await _local.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
    }
  } catch (e) {
    if (kDebugMode) print('[push] init failed: $e');
  }
}

/// Called after the store is signed in — asks permission, gets the token and
/// registers it with the backend, then wires the foreground listener.
Future<void> registerPushForStore() async {
  if (!_supported || !_inited) return;
  try {
    final fm = FirebaseMessaging.instance;
    final settings = await fm.requestPermission(alert: true, badge: true, sound: true);
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    // iOS: show the alert as a heads-up even while the app is foregrounded
    // (iOS suppresses notifications in foreground by default).
    if (_isIOS) {
      await fm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
    }

    final token = await fm.getToken();
    if (token != null && token.isNotEmpty) {
      await Api.instance.registerFcmToken(token);
    }
    fm.onTokenRefresh.listen((t) {
      if (t.isNotEmpty && Api.instance.isLoggedIn) Api.instance.registerFcmToken(t);
    });

    // Foreground push → show the heads-up alert + refresh the board now.
    FirebaseMessaging.onMessage.listen((msg) {
      final n = msg.notification;
      if (n != null && _isAndroid) {
        _local.show(
          n.hashCode,
          n.title ?? '🔔 New online order',
          n.body ?? 'Tap to open',
          const NotificationDetails(android: AndroidNotificationDetails(
            _channelId, 'New orders',
            channelDescription: 'Incoming online & kiosk orders',
            importance: Importance.max, priority: Priority.max,
            sound: RawResourceAndroidNotificationSound('order_alert'),
            playSound: true,
          )),
        );
      }
      OnlineOrdersController.active?.refresh();
    });

    // Tapped a notification (background → opened): refresh the board.
    FirebaseMessaging.onMessageOpenedApp.listen((_) => OnlineOrdersController.active?.refresh());
  } catch (e) {
    if (kDebugMode) print('[push] register failed: $e');
  }
}
