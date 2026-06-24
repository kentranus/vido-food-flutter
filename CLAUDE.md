# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Vido Food is a Flutter app that runs a single tablet as either a restaurant **POS** (counter / order entry) or an unattended **customer Kiosk**. It is a faithful port of an existing React POS — almost every Dart file is annotated with the React file it mirrors (e.g. `views/OrderView.jsx`, `cloudService.js`, `services/staffStorage.js`). It talks to the **same Node backend the React app uses** (`https://api.vidofood.com`, see `kDefaultBaseUrl` in `lib/api.dart`). There is no backend in this repo.

The overriding convention is **faithfulness to the React original**: when porting or fixing a screen, preserve the existing logic, status flows, and field names rather than redesigning. Comments are intentionally bilingual (English + Vietnamese); match the surrounding style.

## Commands

Flutter is not on PATH in every environment; install/activate the Flutter SDK first if `flutter` is missing. CI pins **Flutter 3.44.0 / stable** (`.github/workflows/build.yml`); the Dart SDK constraint is `^3.12.0`.

```bash
flutter pub get                      # install dependencies
flutter run                          # run on a connected device/emulator/web
flutter test                         # run all tests in test/
flutter test test/receipt_lines_test.dart   # run a single test file
flutter test --name "FULL gift-card payment"  # run tests matching a name
flutter analyze                      # static analysis / lints (flutter_lints, see analysis_options.yaml)
flutter build apk --release          # build the Android APK
dart run flutter_launcher_icons      # regenerate launcher icons from assets/brand/
```

`main` pushes trigger the CI workflow, which builds a release APK and publishes a GitHub Release. CI injects `android/app/google-services.json` from the `GOOGLE_SERVICES_JSON_B64` secret — **this file is never committed** (Firebase config).

## Launch flow (the most important thing to understand)

`lib/main.dart` → `RootGate` is a state machine that gates the app, mirroring the React `App.jsx`. Order of gates:

1. **Cloud login** (`screens/cloud_login.dart`) — sign in with the restaurant owner account; session token + store saved to `SharedPreferences` via `Api`. SUPER_ADMIN accounts are rejected.
2. **License check** (`Api.checkLicense`) — polled every 5 min; has a 48h offline-grace cache. Fails → `LicenseLockScreen`.
3. **Device mode branch**: if `Api.instance.deviceMode == 'kiosk'` → `KioskScreen` (runs unattended, no PIN). Otherwise → **staff PIN** (`screens/pin_lock.dart`) → `PosShell`.

`deviceMode` is `'manage'` (POS/board) or `'kiosk'`, persisted on-device. Switch between them from Settings → Device Mode (or `?mode=kiosk` query param).

**QA preview hooks**: `RootGate.build` short-circuits to render a single screen when the URL has `?preview=<name>` (e.g. `?preview=board`, `?preview=settings&tab=pax`, `?preview=takeover`). These never affect the real flow — keep them working when touching `main.dart`, and use them to inspect a screen in isolation.

## Architecture

### `Api` singleton (`lib/api.dart`)
The single gateway to the backend. `Api.instance` is a global; session/token/store/license cache live here and persist to `SharedPreferences` under `vido_cloud_session`. All network calls go through private `_get`/`_post` helpers that return a `{status, ...}` map and **degrade gracefully** — on any error they return `{status: 0, offline: true}` rather than throwing. This is core to the offline-tolerant design; preserve it. Model classes (`Store`, `OnlineOrder`, `OrderItem`) and their lenient `fromJson` (multiple key fallbacks, string-coerced numbers) also live here.

### Realtime: SSE + polling
Two independent long-lived SSE listeners on `/api/events`, each with auto-reconnect and a poll fallback:
- **`OnlineOrdersController`** (`pos/online_orders.dart`, a `ChangeNotifier`) — drives the incoming-orders board, the slide-in panel, and the full-screen `NewOrderTakeover`. 15s poll fallback. Plays a **looping chime** for new ONLINE orders and **auto-prints** kiosk orders. Holds the auto-handling flags loaded from Kiosk Setup. There is one `active` instance exposed statically so push handlers can call `.refresh()`.
- **`MenuSyncListener`** (`lib/menu_sync.dart`) — reloads the menu when the server broadcasts `menu.updated` / `menu.item.86`, keeping POS + Kiosk + online page in step.

Order column logic lives in `columnOf(status, source)` and source styling in `sourceMeta(source)` (`online_orders.dart`) — reuse these rather than re-deriving status→column mappings.

### `PosShell` (`screens/pos_shell.dart`)
The POS chrome: top bar (brand, Menu dropdown of ~16 nav items, payment pill, incoming-orders bell, theme toggle, user menu) + a `_view`-based content router. Some views render real screens (`OrderView`, `OrdersBoard`, `ReportsScreen`, `HistoryScreen`, `OperationsScreen`, `SettingsScreen`); the rest fall back to a placeholder. The settings nav items target `SettingsScreen` with a specific `initialTab`.

### Screens (`lib/pos/`)
Feature screens, each a faithful port: `order_view.dart` (Sell — the largest file, ~1300 lines: cart, multi-order tabs, customize/discount/payment modals), `online_orders.dart`, `kiosk_screen.dart` + `kiosk_setup.dart`, `settings_screen.dart` (~1100 lines, tabbed), `reports_screen.dart`, `history_screen.dart`, `operations_screen.dart`, `gift_card_panel.dart`. `order_models.dart` holds shared cart/order models and the `money()` formatter; `default_menu.dart` is the offline fallback menu.

### Hardware / native integration
Native features go through Flutter `MethodChannel`s, implemented in `android/app/src/main/kotlin/com/vido/food/`. Each Dart bridge has an **off-terminal simulation fallback** so the app stays usable on web/iOS/desktop or without hardware — preserve this dual path when editing:
- `lib/pax.dart` ↔ `vido/pax` (`MainActivity.kt`) — PAX PosLink card terminal. Simulates an approval when not on Android or no terminal IP is set (`PaxResult.simulated`).
- `lib/hardware.dart` ↔ `vido/cashdrawer` (`CashDrawerChannel.kt`) — cash drawer kick.
- Customer display ↔ `vido/customerdisplay` (`CustomerDisplayChannel.kt`).

### Other infrastructure
- `lib/push.dart` — FCM for "new order" alerts when the app is backgrounded/closed. Android uses the high-importance `orders_v2` channel with the `order_alert` sound; **never reuse/rename the channel id** (a channel's sound is locked at creation, and the id must match the server's). No-op on web/iOS-without-APNs.
- `lib/printer.dart` — 80mm thermal receipt + kitchen ticket via the `printing`/`pdf` packages (opens the native print sheet). `receiptPaymentLines()` is a pure, unit-tested composer reused by both the printed receipt and the on-screen dialog.
- `lib/services/staff_store.dart` — local staff + PINs (NOT in the cloud), stored under `vido_staff`. Defaults: Manager `1234`, Cashier `0000`. **Manager role gates refunds, voids, discounts, and settings changes.** The last manager can never be deleted.
- Theme: `lib/ui/pos_theme.dart` — `PT.c` returns the active `PosColors` palette (dark default, `PT.isDark` is a `ValueNotifier`, toggle with `PT.toggle()`). `lib/ui/pos_widgets.dart` has shared widgets (`PButton`, `BrandMark`, …). `lib/theme.dart` is the older MaterialApp theme used pre-`PosShell`.

## Conventions worth following

- **Gift cards / receipts never expose PII or full codes.** Callers pass an already-masked code (`VG-****-XXXX`) to printer/receipt composers; tests assert this.
- **Offline-first everywhere**: network helpers return offline markers instead of throwing, and screens fall back (cached license, default menu, simulated payment). Don't introduce uncaught network exceptions.
- **Commit messages** describe the user-facing change and often reference the porting phase and build number, e.g. `build 25 (1.1.0+3): POS Gift Card D2–D6 …` or `Phase D5: gift card lines on the printed receipt`. Bump `version:` in `pubspec.yaml` when cutting a build.
- Tests live in `test/` and focus on pure logic (receipt lines, business hours, auto-confirm) and preview/widget smoke tests — add to these rather than relying on manual checks where logic is extractable.
