// Off-device PREVIEW renderer for the new Kiosk Setup screens.
// Renders real widgets to PNG (tablet landscape) so the UI can be reviewed
// without a device: flutter test test/preview_kiosk_setup_test.dart
// Output: /tmp/vido_pos_preview/*.png
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vido_food_app/pos/kiosk_setup.dart';
import 'package:vido_food_app/pos/settings_screen.dart';

Future<void> _loadRealFont() async {
  // Map Arial onto the families Material resolves in tests so text is readable.
  final f = File('/System/Library/Fonts/Supplemental/Arial.ttf');
  if (!f.existsSync()) return;
  final bytes = f.readAsBytesSync();
  for (final fam in ['Roboto', 'Arial', '.SF UI Text', '.SF UI Display']) {
    final loader = FontLoader(fam)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
  // Material icons (squares otherwise) — from the local Flutter SDK cache.
  final icons = File('/Users/kennytran/development/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final ib = icons.readAsBytesSync();
    final il = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(ib.buffer)));
    await il.load();
  }
}

Future<void> _shoot(WidgetTester tester, Widget home, String name,
    {bool scrollDown = false, int? tapSwitchIndex}) async {
  await tester.pumpWidget(RepaintBoundary(child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Arial', brightness: Brightness.dark),
      home: Material(color: Colors.transparent, child: home))));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
  if (tapSwitchIndex != null) {
    await tester.tap(find.byType(Switch).at(tapSwitchIndex));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  if (scrollDown) {
    final listView = find.byType(ListView).last;
    await tester.drag(listView, const Offset(0, -640), warnIfMissed: false);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  final boundary = tester.renderObject(find.byType(RepaintBoundary).first) as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 1);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final out = File('/tmp/vido_pos_preview/$name.png')..createSync(recursive: true);
    out.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadRealFont);

  testWidgets('render kiosk setup previews', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(_loadRealFont); // ensure fonts registered in this zone

    // Preview-only: ignore RenderFlex overflow noise (block-font width artifact).
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (d) {
      if ('${d.exception}'.contains('RenderFlex overflowed')) return;
      prevOnError?.call(d);
    };
    addTearDown(() => FlutterError.onError = prevOnError);

    // 1) POS Settings → new "Kiosk Setup" tab (rail + panel top)
    await _shoot(tester, SettingsScreen(initialTab: 'kiosk', onEnterKiosk: () {}),
        'settings_kiosk_setup_tab_top');

    // 2) Same tab — separate kiosk PAX ENABLED (TCP/IP fields visible) + scrolled
    await _shoot(tester, SettingsScreen(initialTab: 'kiosk', onEnterKiosk: () {}),
        'settings_kiosk_setup_pax_enabled', scrollDown: true, tapSwitchIndex: 6);

    // 3) Kiosk Settings screen (what the hidden PIN now opens)
    await _shoot(tester, const KioskSettingsScreen(), 'kiosk_settings_after_pin');
  });
}
