/// Runtime configuration. By default the dashboard talks to the server that served it (one port for the
/// API, the dashboard and the worker app). Override for development:
/// flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000/api
class AppConfig {
  static const _defined = String.fromEnvironment('API_BASE_URL');
  static String get apiBaseUrl => _defined.isNotEmpty ? _defined : '${Uri.base.origin}/api';
  static const pollInterval = Duration(seconds: 2);
  static const requestTimeout = Duration(seconds: 6);
}
