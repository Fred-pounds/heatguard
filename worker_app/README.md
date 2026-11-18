# HeatGuard Worker app

The app workers carry with them. It is separate from the supervisor / OHS dashboard (`../frontend`) and talks to
the same HeatGuard API with the `worker` role. It runs on the web and builds for Android and iOS from one code base.

| Screen | What it does |
|---|---|
| Onboarding | Language (English, Arabic, Urdu, Hindi), crew, optional wearable badge. Remembered on the device. |
| Today | Heat level with a 5-step scale, plain-language notice, midday break, what to do now, protective actions in place, "I feel unwell / report a co-worker". |
| My health | Opt-in wearable sharing with informed consent: own heart rate, body-temperature estimate and badge battery; stop sharing deletes the data; who sees what. |
| Emergency | One-tap 998 call, warning signs of heat stroke, first steps, report to the first aider. |
| Settings | Language, crew, badge, device alerts, server address (mobile), about. |

Arabic and Urdu use a right-to-left layout. The Arabic, Urdu and Hindi texts are **draft translations** that must be
reviewed by native speakers before real use. All heat data in the prototype are simulated.

## Run

The HeatGuard server serves a prebuilt copy at **http://localhost:8000/worker/** (see the main README).

```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000/api
```

## Build

```bash
flutter build web --release --no-web-resources-cdn --base-href /worker/
```

```bash
flutter build apk --dart-define=API_BASE_URL=http://<server-ip>:8000/api
```

```bash
flutter build ios --dart-define=API_BASE_URL=http://<server-ip>:8000/api
```

`../scripts/build_web.sh` rebuilds the web version and refreshes `dist/`, which the server uses.

## Code

```
lib/
├── main.dart            app entry, RTL handling, onboarding vs home
├── core/                api client and server address, persisted state and polling, theme and heat levels,
│                        device alerts (browser notifications on web, vibration + in-app alert on mobile)
├── l10n/                worker strings (shared safety messages + app screens) in 4 languages
└── ui/                  onboarding, home (tabs), today, health, help (emergency), report sheet, settings
```

Native push notifications (Firebase Cloud Messaging) and SMS fallback are planned for the pilot.
