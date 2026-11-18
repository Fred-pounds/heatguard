import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS('speechSynthesis')
external JSAny? get _synth;

class Speaker {
  static const _tags = {'en': 'en-GB', 'ar': 'ar-AE', 'ur': 'ur-PK', 'hi': 'hi-IN', 'ml': 'ml-IN', 'bn': 'bn-BD'};
  static bool _speaking = false;

  static bool get supported => _synth != null;
  static bool get speaking => _speaking;

  /// Speaks [text] in [lang]. Returns false if the device has no voice for that language
  /// (we never read a safety message in the wrong language).
  static bool speak(String text, String lang, {void Function()? onDone}) {
    if (!supported) return false;
    final synth = web.window.speechSynthesis;
    final voices = synth.getVoices().toDart;
    web.SpeechSynthesisVoice? voice;
    for (final v in voices) {
      if (v.lang.toLowerCase().startsWith(lang)) {
        voice = v;
        if (v.lang == _tags[lang]) break;
      }
    }
    if (voice == null && lang != 'en' && voices.isNotEmpty) return false;
    synth.cancel();
    final u = web.SpeechSynthesisUtterance(text)
      ..lang = _tags[lang] ?? lang
      ..rate = 0.92;
    if (voice != null) u.voice = voice;
    void done() {
      _speaking = false;
      onDone?.call();
    }

    u.onend = ((web.Event _) => done()).toJS;
    u.onerror = ((web.Event _) => done()).toJS;
    _speaking = true;
    synth.speak(u);
    return true;
  }

  static void stop() {
    if (!supported) return;
    web.window.speechSynthesis.cancel();
    _speaking = false;
  }
}
