/// Runtime configuration. Override at build time:
/// flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000/api
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000/api');
  static const pollInterval = Duration(seconds: 2);
  static const requestTimeout = Duration(seconds: 6);
}
