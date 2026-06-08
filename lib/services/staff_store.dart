import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Local staff + PINs — faithful port of React services/staffStorage.js.
/// Default Manager: 1234, Cashier: 0000. Stored on-device (not in the cloud).
/// Manager role required for: refunds, voids, discounts, settings changes.
class Staff {
  final String id, name, role; // role: 'manager' | 'cashier'
  final String pin;
  final bool active;
  Staff({required this.id, required this.name, required this.role, required this.pin, this.active = true});
  bool get isManager => role == 'manager';
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'role': role, 'pin': pin, 'active': active};
  factory Staff.fromJson(Map<String, dynamic> j) => Staff(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        role: (j['role'] ?? 'cashier').toString(),
        pin: (j['pin'] ?? '').toString(),
        active: j['active'] != false,
      );
}

class StaffStore {
  static const _key = 'vido_staff';
  static final List<Staff> _defaults = [
    Staff(id: 's1', name: 'Manager', role: 'manager', pin: '1234'),
    Staff(id: 's2', name: 'Cashier 1', role: 'cashier', pin: '0000'),
  ];

  /// Current signed-in staff (in-memory session), like getCurrentStaff().
  static Staff? current;

  static Future<List<Staff>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return List.of(_defaults);
    try {
      return (jsonDecode(raw) as List).map((e) => Staff.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return List.of(_defaults);
    }
  }

  static Future<void> save(List<Staff> staff) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(staff.map((s) => s.toJson()).toList()));
  }

  static Future<Staff?> verifyPin(String pin) async {
    final staff = await load();
    for (final s in staff) {
      if (s.active && s.pin == pin) return s;
    }
    return null;
  }

  static Future<Staff?> verifyManagerPin(String pin) async {
    final s = await verifyPin(pin);
    return (s != null && s.isManager) ? s : null;
  }

  static Future<List<Staff>> add(Staff member) async {
    final all = await load();
    all.add(Staff(id: 's${DateTime.now().millisecondsSinceEpoch}', name: member.name, role: member.role, pin: member.pin, active: true));
    await save(all);
    return all;
  }

  static Future<List<Staff>> update(String id, {String? name, String? role, String? pin, bool? active}) async {
    final all = await load();
    final next = all.map((s) => s.id == id
        ? Staff(id: s.id, name: name ?? s.name, role: role ?? s.role, pin: pin ?? s.pin, active: active ?? s.active)
        : s).toList();
    await save(next);
    return next;
  }

  /// Never delete the last manager (mirrors React deleteStaff).
  static Future<List<Staff>> remove(String id) async {
    final all = await load();
    final target = all.where((s) => s.id == id).firstOrNull;
    final otherManagers = all.where((s) => s.role == 'manager' && s.id != id).length;
    if (target?.role == 'manager' && otherManagers == 0) {
      throw Exception('Cannot delete the last manager');
    }
    final next = all.where((s) => s.id != id).toList();
    await save(next);
    return next;
  }
}
