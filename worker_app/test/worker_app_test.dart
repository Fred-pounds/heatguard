import 'package:flutter_test/flutter_test.dart';
import 'package:heatguard_worker/core/api.dart';
import 'package:heatguard_worker/core/theme.dart';
import 'package:heatguard_worker/l10n/app_strings.dart';
import 'package:heatguard_worker/l10n/strings.dart';

void main() {
  test('server address is normalised to the API base', () {
    expect(ApiConfig.normalise('192.168.1.20:8000'), 'http://192.168.1.20:8000/api');
    expect(ApiConfig.normalise('https://heatguard.example/'), 'https://heatguard.example/api');
    expect(ApiConfig.normalise('http://host:8000/api'), 'http://host:8000/api');
  });

  test('heat levels are ordered and unknown values are never shown as safe', () {
    final ranks = Level.scale.map((c) => Level.of(c).rank).toList();
    expect(ranks, [0, 1, 2, 3, 4]);
    expect(Level.of(null).id, 'unavailable');
    expect(Level.of('something-else').id, 'unavailable');
  });

  test('every language has every app string, and safety texts fall back to English', () {
    final keys = appStrings['en']!.keys.toSet()..remove('app_name');
    for (final lang in ['ar', 'ur', 'hi']) {
      expect(appStrings[lang]!.keys.toSet().containsAll(keys), isTrue, reason: 'missing keys in $lang');
    }
    expect(const L10n('ar').isRtl, isTrue);
    expect(const L10n('hi').isRtl, isFalse);
    expect(const L10n('ur').t('app_name'), 'HeatGuard');
    for (final lang in L10n.supported.keys) {
      expect(L10n(lang).t('notice.unavailable'), isNot('notice.unavailable'));
    }
  });
}
