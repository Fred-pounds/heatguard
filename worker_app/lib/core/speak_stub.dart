class Speaker {
  static bool get supported => false;
  static bool get speaking => false;

  /// Returns false when no voice for [lang] is available.
  static bool speak(String text, String lang, {void Function()? onDone}) => false;
  static void stop() {}
}
