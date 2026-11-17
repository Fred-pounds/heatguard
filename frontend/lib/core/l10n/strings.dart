/// Worker-facing strings. Architecture for future Twi / other Ghanaian languages:
/// add a map per language code. Missing keys fall back to English.
///
/// IMPORTANT: Twi ('tw') entries are intentionally left empty. Safety messages
/// must be translated and reviewed by qualified native speakers and tested with
/// workers before use; machine or ad-hoc translations are not acceptable here.
class L10n {
  static const supported = {'en': 'English', 'tw': 'Twi (translation pending review)'};

  static const Map<String, Map<String, String>> _strings = {
    'en': {
      'title': 'Heat safety',
      'select_crew': 'Select your crew',
      'notice.routine': 'Conditions are within safe working guidance. Keep drinking water regularly.',
      'notice.caution': 'It is getting hot. Drink water often and tell your supervisor if you feel unwell.',
      'notice.elevated': 'Heat risk is raised. Take your scheduled rest breaks in the shade and drink water every 15-20 minutes.',
      'notice.high': 'High heat risk. Follow the work-rest schedule from your supervisor. Rest in shade or a cool area.',
      'notice.critical': 'Very high heat risk. Strenuous work should stop. Follow your supervisor\'s instructions now.',
      'notice.unavailable': 'Heat conditions cannot be checked right now. This does NOT mean it is safe. Keep drinking water and take breaks.',
      'level.routine': 'Normal',
      'level.caution': 'Caution',
      'level.elevated': 'Raised',
      'level.high': 'High',
      'level.critical': 'Very high',
      'level.unavailable': 'Not available',
      'water': 'Drink water: about 1 cup every 15-20 minutes',
      'what_to_do': 'What to do now',
      'protective_actions': 'Protective actions in place',
      'work_rest': 'Work-rest schedule',
      'emergency': 'Emergency - act fast',
      'updated': 'Updated',
      'privacy': 'This screen shows crew-level heat information only. It does not track you.',
      'simulated': 'SIMULATED DATA - demonstration only',
      'offline': 'Cannot reach HeatGuard. Information shown may be out of date - do not assume it is safe.',
    },
    'tw': {},
  };

  final String lang;
  const L10n(this.lang);

  String t(String key) => _strings[lang]?[key] ?? _strings['en']![key] ?? key;
}
