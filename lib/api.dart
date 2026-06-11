import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Talks to the SAME Node backend the React POS uses (api.vidofood.com).
/// Mirrors cloudService.js so every feature/logic is preserved.
const String kDefaultBaseUrl = 'https://api.vidofood.com';

class Store {
  final String id;
  final String slug;
  final String name;
  final String businessType;
  Store({required this.id, required this.slug, required this.name, required this.businessType});
  factory Store.fromJson(Map<String, dynamic> j) => Store(
        id: (j['id'] ?? '').toString(),
        slug: (j['slug'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        businessType: (j['businessType'] ?? 'quick_service').toString(),
      );
  Map<String, dynamic> toJson() => {'id': id, 'slug': slug, 'name': name, 'businessType': businessType};
}

class OrderItem {
  final String name;
  final int quantity;
  final List<String> modifiers;
  final String notes;
  final double lineTotal;
  OrderItem({required this.name, required this.quantity, required this.modifiers, required this.notes, this.lineTotal = 0});
  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
        name: (j['nameSnapshot'] ?? j['name'] ?? 'Item').toString(),
        quantity: (j['quantity'] ?? 1) is int ? (j['quantity'] ?? 1) : int.tryParse('${j['quantity']}') ?? 1,
        modifiers: ((j['modifiers'] ?? []) as List)
            .map((m) => (m is Map ? (m['optionName'] ?? m['name'] ?? '') : m).toString())
            .where((s) => s.isNotEmpty)
            .toList(),
        notes: (j['notes'] ?? '').toString(),
        lineTotal: (j['lineTotal'] is num) ? (j['lineTotal'] as num).toDouble() : double.tryParse('${j['lineTotal'] ?? ''}') ?? 0,
      );
}

class OnlineOrder {
  final String id;
  final String? number;
  final String status;
  final String source;
  final String orderType;
  final String customer;
  final String customerPhone;
  final List<OrderItem> items;
  final double subtotal, tax, tip, total;
  final int? etaMinutes;
  final String paymentStatus;
  final String createdAt;
  OnlineOrder({
    required this.id,
    this.number,
    required this.status,
    required this.source,
    required this.orderType,
    required this.customer,
    required this.customerPhone,
    required this.items,
    required this.subtotal,
    required this.tax,
    required this.tip,
    required this.total,
    this.etaMinutes,
    required this.paymentStatus,
    required this.createdAt,
  });
  static double _d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
  factory OnlineOrder.fromJson(Map<String, dynamic> j) => OnlineOrder(
        id: (j['id'] ?? '').toString(),
        number: j['number']?.toString(),
        status: (j['status'] ?? '').toString(),
        source: (j['source'] ?? '').toString(),
        orderType: (j['orderType'] ?? 'PICKUP').toString(),
        customer: (j['customer'] ?? j['customerName'] ?? 'Customer').toString(),
        customerPhone: (j['customerPhone'] ?? '').toString(),
        items: ((j['items'] ?? []) as List).map((e) => OrderItem.fromJson(Map<String, dynamic>.from(e))).toList(),
        subtotal: _d(j['subtotal']),
        tax: _d(j['tax']),
        tip: _d(j['tip']),
        total: _d(j['total']),
        etaMinutes: j['etaMinutes'] == null ? null : int.tryParse('${j['etaMinutes']}'),
        paymentStatus: (j['paymentStatus'] ?? '').toString(),
        createdAt: (j['createdAt'] ?? '').toString(),
      );
  bool get isCard => paymentStatus == 'authorized' || paymentStatus == 'captured' || paymentStatus == 'card';
}

class LicenseResult {
  final bool allowed;
  final String reason;
  final bool offline;
  LicenseResult(this.allowed, this.reason, {this.offline = false});
}

class Api {
  Api._();
  static final Api instance = Api._();

  String baseUrl = kDefaultBaseUrl;
  String token = '';
  Store? store;
  Map<String, dynamic>? lastLicense; // cached for offline grace
  String deviceMode = 'manage'; // 'manage' (POS/board) | 'kiosk'

  static const _kKey = 'vido_cloud_session';

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_kKey);
      if (raw != null && raw.isNotEmpty) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        baseUrl = (j['baseUrl'] ?? kDefaultBaseUrl).toString();
        token = (j['token'] ?? '').toString();
        store = j['store'] != null ? Store.fromJson(Map<String, dynamic>.from(j['store'])) : null;
        lastLicense = j['lastLicense'] != null ? Map<String, dynamic>.from(j['lastLicense']) : null;
        deviceMode = (j['deviceMode'] ?? 'manage').toString();
      }
    } catch (_) {
      // Corrupt/unreadable session → treat as logged out.
      token = '';
      store = null;
    }
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kKey, jsonEncode({
      'baseUrl': baseUrl,
      'token': token,
      'store': store?.toJson(),
      'lastLicense': lastLicense,
      'deviceMode': deviceMode,
    }));
  }

  Future<void> setDeviceMode(String m) async { deviceMode = m; await _persist(); }

  /// Create a customer kiosk order (counts as a paid online order, source Kiosk).
  Future<Map<String, dynamic>> createKioskOrder(Map<String, dynamic> order) =>
      _post('/api/online-orders', {...order, 'source': 'Kiosk', 'status': 'new', 'paymentStatus': 'paid'});

  bool get isLoggedIn => token.isNotEmpty && store != null;
  String get storeName => store?.name ?? '';
  String get storeSlug => store?.slug ?? '';
  bool get isFullService => store?.businessType == 'full_service';

  Uri _u(String path) => Uri.parse('${baseUrl.replaceAll(RegExp(r"/+$"), "")}$path');

  Future<Map<String, dynamic>> _get(String path) async {
    try {
      final r = await http.get(_u(path), headers: {'authorization': 'Bearer $token'}).timeout(const Duration(seconds: 12));
      final j = jsonDecode(r.body);
      return {'status': r.statusCode, ...(j is Map ? Map<String, dynamic>.from(j) : {})};
    } catch (e) {
      return {'status': 0, 'ok': false, 'offline': true, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body, {bool auth = true}) async {
    try {
      final r = await http
          .post(_u(path),
              headers: {'content-type': 'application/json', if (auth) 'authorization': 'Bearer $token'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
      final j = jsonDecode(r.body);
      return {'status': r.statusCode, ...(j is Map ? Map<String, dynamic>.from(j) : {})};
    } catch (e) {
      return {'status': 0, 'ok': false, 'offline': true, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> login(String email, String password, {String? base}) async {
    if (base != null && base.trim().isNotEmpty) baseUrl = base.trim();
    final j = await _post('/api/auth/login',
        {'email': email.trim(), 'password': password, 'deviceId': 'manage'}, auth: false);
    if (j['ok'] != true) return {'ok': false, 'error': j['error'] ?? 'Sign in failed'};
    if (j['account']?['role'] == 'SUPER_ADMIN' || j['store'] == null) {
      return {'ok': false, 'error': 'Use your restaurant (owner) account, not the Vido admin account.'};
    }
    token = (j['token'] ?? '').toString();
    store = Store.fromJson(Map<String, dynamic>.from(j['store']));
    await _persist();
    return {'ok': true};
  }

  /// Forgot password — server emails a new temp password. Generic response.
  Future<Map<String, dynamic>> forgotPassword(String email) =>
      _post('/api/auth/forgot-password', {'email': email.trim()}, auth: false);

  Future<void> logout() async {
    try { await _post('/api/auth/logout', {}); } catch (_) {}
    token = '';
    store = null;
    await _persist();
  }

  Future<LicenseResult> checkLicense() async {
    if (!isLoggedIn) return LicenseResult(false, 'not_linked');
    final j = await _get('/api/license/check');
    if (j['offline'] == true || j['status'] == 0) {
      final c = lastLicense;
      final graceH = (c?['offlineGraceHours'] ?? 48) as int;
      final at = c?['at'] as int?;
      if (c?['allowed'] == true && at != null && DateTime.now().millisecondsSinceEpoch - at < graceH * 3600 * 1000) {
        return LicenseResult(true, 'offline_grace', offline: true);
      }
      return LicenseResult(false, 'offline_no_cache', offline: true);
    }
    if (j['status'] == 401) return LicenseResult(false, 'session_expired');
    if (j['ok'] == true) {
      lastLicense = {
        'allowed': j['allowed'] == true,
        'reason': j['reason'] ?? '',
        'offlineGraceHours': j['offlineGraceHours'] ?? 48,
        'at': DateTime.now().millisecondsSinceEpoch,
      };
      await _persist();
      return LicenseResult(j['allowed'] == true, (j['reason'] ?? '').toString());
    }
    return LicenseResult(false, (j['error'] ?? 'unknown').toString());
  }

  Future<List<OnlineOrder>> fetchOnlineOrders() async {
    if (!isLoggedIn) return [];
    final j = await _get('/api/online-orders');
    if (j['ok'] != true) return [];
    final list = (j['orders'] ?? []) as List;
    return list.map((e) => OnlineOrder.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<Map<String, dynamic>> accept(String id, int? eta) =>
      _post('/api/online-orders/$id/accept', {'etaMinutes': eta});
  Future<Map<String, dynamic>> reject(String id, String reason) =>
      _post('/api/online-orders/$id/reject', {'reason': reason});
  Future<Map<String, dynamic>> markReady(String id) => _post('/api/online-orders/$id/ready', {});
  Future<Map<String, dynamic>> setStatus(String id, String status) =>
      _post('/api/online-orders/$id/update', {'status': status});
  Future<Map<String, dynamic>> markPrinted(String id) =>
      _post('/api/online-orders/$id/print', {'status': 'accepted'});
  Future<Map<String, dynamic>> registerFcmToken(String t) =>
      _post('/api/devices/fcm-token', {'token': t, 'platform': 'flutter'});

  // ---- Menu + counter orders (POS sell mode) ----
  Future<Map<String, dynamic>> getMenu() => _get('/api/menu');
  Future<Map<String, dynamic>> getSettings() => _get('/api/settings');
  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> order) => _post('/api/orders', order);
  Future<Map<String, dynamic>> saveMenu(Map<String, dynamic> menu) => _post('/api/menu', menu);

  // ---- Gift cards (Phase D2: check balance only; redeem/refund come in D3) ----
  Future<Map<String, dynamic>> giftCheck(String code) => _post('/api/gift-cards/check', {'code': code});

  // ---- Reports + history ----
  Future<Map<String, dynamic>> getReports() => _get('/api/reports/summary');
  Future<Map<String, dynamic>> getOrders() => _get('/api/orders');
  Future<Map<String, dynamic>> refundOrder(String id, {double? amount, String reason = ''}) =>
      _post('/api/orders/$id/refund', {'amount': ?amount, 'reason': reason});
  Future<Map<String, dynamic>> voidOrder(String id, {String reason = ''}) =>
      _post('/api/orders/$id/void', {'reason': reason});

  // ---- Settings (shop info / payment / customer display / kiosks) ----
  Future<Map<String, dynamic>> saveSettings(Map<String, dynamic> patch) => _post('/api/settings', patch);

  // ---- Staff & PINs ----
  Future<Map<String, dynamic>> getStaff() => _get('/api/staff');
  Future<Map<String, dynamic>> addStaff(String name, String email, String password) =>
      _post('/api/staff', {'name': name, 'email': email, 'password': password});

  // ---- Customise own online-order link slug ----
  Future<Map<String, dynamic>> setSlug(String slug) => _post('/api/me/slug', {'slug': slug});
}
