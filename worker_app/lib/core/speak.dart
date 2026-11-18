/// Read the notice aloud with the device's own text-to-speech voices (web: Web Speech API).
/// On Android and iOS builds this is not available yet (planned: platform TTS in the pilot).
library;

export 'speak_stub.dart' if (dart.library.js_interop) 'speak_web.dart';
