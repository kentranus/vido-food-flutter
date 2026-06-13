// OM4 trên POS — Auto Confirm online orders (server-side toggle + alert rules).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vido_food_app/api.dart';
import 'package:vido_food_app/pos/kiosk_setup.dart';
import 'package:vido_food_app/pos/online_orders.dart';
import 'package:vido_food_app/pos/settings_screen.dart';

void main() {
  group('isServerConfirmedOnline — chỉ đơn ONLINE về đã-accepted, chưa thấy', () {
    test('online + accepted + chưa thấy → true (ting)', () {
      expect(isServerConfirmedOnline('accepted', 'Online', seen: false), isTrue);
    });
    test('đã thấy rồi (đã accept tay / đã báo) → false', () {
      expect(isServerConfirmedOnline('accepted', 'Online', seen: true), isFalse);
    });
    test('pending_accept → false (đường takeover/chuông lo)', () {
      expect(isServerConfirmedOnline('pending_accept', 'Online', seen: false), isFalse);
    });
    test('kiosk → false (kiosk có ting riêng sẵn)', () {
      expect(isServerConfirmedOnline('accepted', 'Kiosk-table1', seen: false), isFalse);
    });
    test('ready/completed → false', () {
      expect(isServerConfirmedOnline('ready', 'Online', seen: false), isFalse);
      expect(isServerConfirmedOnline('completed', 'Online', seen: false), isFalse);
    });
  });

  group('OnlineOrder.fromJson — shouldPrint', () {
    final base = {
      'id': 'o1', 'status': 'accepted', 'source': 'Online', 'orderType': 'PICKUP',
      'customer': 'C', 'items': [], 'subtotal': 8, 'tax': .7, 'tip': 0, 'total': 8.7,
      'paymentStatus': 'captured', 'createdAt': '2026-06-11T15:00:00.000Z',
    };
    test('shouldPrint=true parse đúng', () {
      expect(OnlineOrder.fromJson({...base, 'shouldPrint': true}).shouldPrint, isTrue);
    });
    test('thiếu field (backend cũ) → false, không vỡ', () {
      expect(OnlineOrder.fromJson(base).shouldPrint, isFalse);
    });
  });

  group('AutoConfirmTile — load/save server, revert khi lỗi', () {
    Future<void> pump(WidgetTester tester, AutoConfirmTile tile) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: [tile]))));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('load ON từ server → switch bật', (tester) async {
      await pump(tester, AutoConfirmTile(load: () async => true, save: (_) async => {'ok': true}));
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('gạt switch → gọi save với giá trị mới + giữ trạng thái', (tester) async {
      final saved = <bool>[];
      await pump(tester, AutoConfirmTile(load: () async => false,
          save: (v) async { saved.add(v); return {'ok': true}; }));
      await tester.tap(find.byType(Switch));
      await tester.pump(const Duration(milliseconds: 100));
      expect(saved, [true]);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('save FAIL → revert về giá trị cũ', (tester) async {
      await pump(tester, AutoConfirmTile(load: () async => false,
          save: (_) async => {'ok': false, 'error': 'offline'}));
      await tester.tap(find.byType(Switch));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('load lỗi mạng → default OFF, không crash', (tester) async {
      await pump(tester, AutoConfirmTile(load: () async => throw Exception('net'),
          save: (_) async => {'ok': true}));
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });
  });

  group('kioskAutoFlag acceptPrint — default ON, tắt được', () {
    test('không set → true (in như cũ)', () {
      expect(kioskAutoFlag({}, 'acceptPrint'), isTrue);
    });
    test('set false → tắt in khi Accept', () {
      expect(kioskAutoFlag({'acceptPrint': false}, 'acceptPrint'), isFalse);
    });
  });

  group('category helpers (sync với OM — SHARED_LOGIC.md)', () {
    test('reorder + canDelete + slugify tiếng Việt', () {
      final cats = [{'id': 'a', 'order': 1}, {'id': 'b', 'order': 2}];
      expect(reorderCategory(cats, 1, -1).map((c) => c['id']).toList(), ['b', 'a']);
      expect(canDeleteCategory([{'category': 'a'}], 'a'), isFalse);
      expect(canDeleteCategory([{'category': 'a'}], 'b'), isTrue);
      expect(slugifyName('Phở Đặc Biệt'), 'pho-dac-biet');
    });
  });
}
