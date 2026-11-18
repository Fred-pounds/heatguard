/// Device alerts. On the web this uses browser notifications; on Android and iOS the app shows an
/// in-app alert with a vibration (native push via Firebase Cloud Messaging is planned for the pilot).
library;

export 'notify_stub.dart' if (dart.library.js_interop) 'notify_web.dart';
