# HeatGuard dashboard (Flutter Web)

```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000/api
flutter build web --release --no-web-resources-cdn   # offline-capable build, served by the backend
```

* State: `lib/providers/app_state.dart` (Provider) polls the REST API every 2 s. All figures come from the backend.
* Routes: `/` supervisor dashboard, `/#/worker` worker view.
* Severity colours (`lib/core/severity.dart`) are used everywhere: green routine, yellow caution, orange
  elevated, red high, dark red critical, purple **assessment unavailable** (deliberately never green or grey).
* Worker strings: `lib/core/l10n/strings.dart` (English; Twi slots intentionally empty pending qualified review).
* Uses `package:material_ui` (Material 3 library for Flutter ≥ 3.47).
* Bundled fonts: Roboto (Apache-2.0, from the Flutter SDK), see `assets/fonts/Roboto_LICENSE.txt`.
