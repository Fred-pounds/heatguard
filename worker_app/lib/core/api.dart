import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

typedef J = Map<String, dynamic>;

J jMap(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<J> jList(Object? v) => v is List ? v.map(jMap).toList() : <J>[];

/// API base URL. Order: a server address saved in Settings, then `--dart-define=API_BASE_URL`,
/// then (on the web) the server that served this app, then localhost for development.
class ApiConfig {
  static const _defined = String.fromEnvironment('API_BASE_URL');

  static String resolve(String? saved) {
    final s = saved?.trim() ?? '';
    if (s.isNotEmpty) return normalise(s);
    if (_defined.isNotEmpty) return _defined;
    if (kIsWeb) return '${Uri.base.origin}/api';
    return 'http://localhost:8000/api';
  }

  /// Accepts "192.168.1.20:8000", "http://host:8000" or "http://host:8000/api".
  static String normalise(String input) {
    var s = input.trim();
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
    s = s.replaceAll(RegExp(r'/+$'), '');
    if (!s.endsWith('/api')) s = '$s/api';
    return s;
  }

  /// Whether the user should be able to change the server (native apps; web uses its own origin).
  static bool get serverEditable => !kIsWeb || _defined.isNotEmpty;
}

class ApiError implements Exception {
  ApiError(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// Minimal client for the worker-facing HeatGuard endpoints (role: worker).
class Api {
  Api(this.baseUrl);
  String baseUrl;
  final _client = http.Client();
  static const _timeout = Duration(seconds: 8);
  static const _headers = {'Content-Type': 'application/json', 'X-HeatGuard-Role': 'worker'};

  Future<dynamic> get(String path) => _send(() => _client.get(Uri.parse('$baseUrl$path'), headers: _headers));

  Future<dynamic> post(String path, Object body) =>
      _send(() => _client.post(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body)));

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    http.Response r;
    try {
      r = await call().timeout(_timeout);
    } catch (e) {
      throw ApiError('network');
    }
    final body = r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode >= 400) {
      throw ApiError(body is Map && body['detail'] != null ? '${body['detail']}' : 'HTTP ${r.statusCode}', status: r.statusCode);
    }
    return body;
  }
}
