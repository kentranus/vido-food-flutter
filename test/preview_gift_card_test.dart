// Off-device PREVIEW + behavior test for the Phase D2 Gift Card panel.
// Renders the REAL GiftCardCheckPanel to PNG in every state and asserts the
// displayed copy, driving the injected `check` callback (no network needed).
// Run: flutter test test/preview_gift_card_test.dart
// Output: /tmp/vido_pos_preview/giftcard_*.png
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vido_food_app/pos/gift_card_panel.dart';

Future<void> _loadRealFont() async {
  final f = File('/System/Library/Fonts/Supplemental/Arial.ttf');
  if (!f.existsSync()) return;
  final bytes = f.readAsBytesSync();
  for (final fam in ['Roboto', 'Arial', '.SF UI Text', '.SF UI Display']) {
    final loader = FontLoader(fam)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
  final icons = File('/Users/kennytran/development/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final ib = icons.readAsBytesSync();
    final il = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(ib.buffer)));
    await il.load();
  }
}

const _shotKey = Key('shot-boundary');
Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(fontFamily: 'Arial', brightness: Brightness.dark),
  home: RepaintBoundary(
    key: _shotKey,
    child: Material(
      color: const Color(0xFF14161B),
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(padding: const EdgeInsets.all(24), child: child),
      )),
    ),
  ),
);

Future<void> _snap(WidgetTester tester, String name) async {
  final el = tester.element(find.byKey(_shotKey));
  final ro = el.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final img = await ro.toImage(pixelRatio: 2);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory('/tmp/vido_pos_preview').createSync(recursive: true);
    File('/tmp/vido_pos_preview/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<void> _enterAndCheck(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(TextField), code);
  await tester.tap(find.text('Check Balance'));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(_loadRealFont);

  testWidgets('mask helper', (tester) async {
    expect(maskGiftCode('VG-8RWN-H4B3'), 'VG-****-H4B3');
    expect(maskGiftCode('BADCODE'), 'BADCODE');
  });

  testWidgets('initial state — input + disabled Apply placeholder', (tester) async {
    await tester.pumpWidget(_host(GiftCardCheckPanel(check: (_) async => {'ok': true})));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('GIFT CARD CODE'), findsOneWidget);
    expect(find.text('Check Balance'), findsOneWidget);
    expect(find.text('Apply — coming next'), findsOneWidget);
    await _snap(tester, 'giftcard_1_initial');
  });

  testWidgets('active balance', (tester) async {
    await tester.pumpWidget(_host(GiftCardCheckPanel(
        check: (code) async => {'status': 200, 'ok': true, 'code': code, 'balance': 25.0, 'initial': 25.0})));
    await _enterAndCheck(tester, 'VG-8RWN-H4B3');
    expect(find.text('VG-****-H4B3'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('\$25.00'), findsOneWidget);
    await _snap(tester, 'giftcard_2_active');
  });

  testWidgets('zero balance', (tester) async {
    await tester.pumpWidget(_host(GiftCardCheckPanel(
        check: (code) async => {'status': 200, 'ok': true, 'code': code, 'balance': 0.0, 'initial': 25.0})));
    await _enterAndCheck(tester, 'VG-A9BA-DBHD');
    expect(find.text('This gift card has no remaining balance.'), findsOneWidget);
    expect(find.text('\$0.00'), findsOneWidget);
    await _snap(tester, 'giftcard_3_zero');
  });

  testWidgets('invalid / wrong store — safe generic message', (tester) async {
    await tester.pumpWidget(_host(GiftCardCheckPanel(
        check: (_) async => {'status': 404, 'ok': false, 'error': 'Gift card not found'})));
    await _enterAndCheck(tester, 'VG-0000-0000');
    expect(find.text('Gift card not found or not valid for this store.'), findsOneWidget);
    await _snap(tester, 'giftcard_4_invalid');
  });

  testWidgets('offline', (tester) async {
    await tester.pumpWidget(_host(GiftCardCheckPanel(
        check: (_) async => {'status': 0, 'ok': false, 'offline': true, 'error': 'socket'})));
    await _enterAndCheck(tester, 'VG-8RWN-H4B3');
    expect(find.text('GIFT CARD REQUIRES INTERNET CONNECTION'), findsOneWidget);
    await _snap(tester, 'giftcard_5_offline');
  });

  testWidgets('server error (5xx) — generic retry message', (tester) async {
    await tester.pumpWidget(_host(GiftCardCheckPanel(
        check: (_) async => {'status': 500, 'ok': false, 'error': 'boom'})));
    await _enterAndCheck(tester, 'VG-8RWN-H4B3');
    expect(find.text('Unable to check gift card right now. Please try again.'), findsOneWidget);
    await _snap(tester, 'giftcard_6_error');
  });
}
