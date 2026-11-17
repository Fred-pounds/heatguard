import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';

class ApiException implements Exception {
  final int? status;
  final String message;
  ApiException(this.message, {this.status});
  bool get isNetwork => status == null;
  @override
  String toString() => message;
}

/// Thin REST client for the HeatGuard FastAPI backend.
class ApiClient {
  ApiClient({String? baseUrl, this.role = 'supervisor'}) : baseUrl = baseUrl ?? AppConfig.apiBaseUrl;
  final String baseUrl;
  String role;
  final _client = http.Client();

  Map<String, String> get _headers => {'Content-Type': 'application/json', 'X-HeatGuard-Role': role};

  Uri _uri(String path, [Map<String, String?>? q]) {
    final params = <String, String>{};
    q?.forEach((k, v) {
      if (v != null) params[k] = v;
    });
    return Uri.parse('$baseUrl$path').replace(queryParameters: params.isEmpty ? null : params);
  }

  Future<dynamic> get(String path, [Map<String, String?>? q]) => _send(() => _client.get(_uri(path, q), headers: _headers));

  Future<dynamic> post(String path, [Object? body]) =>
      _send(() => _client.post(_uri(path), headers: _headers, body: jsonEncode(body ?? {})));

  Future<dynamic> put(String path, Object body) => _send(() => _client.put(_uri(path), headers: _headers, body: jsonEncode(body)));

  Future<dynamic> delete(String path) => _send(() => _client.delete(_uri(path), headers: _headers));

  Future<String> getText(String path, [Map<String, String?>? q]) async {
    try {
      final r = await _client.get(_uri(path, q), headers: _headers).timeout(AppConfig.requestTimeout);
      if (r.statusCode >= 400) throw ApiException(_detail(r), status: r.statusCode);
      return utf8.decode(r.bodyBytes);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Service unavailable: $e');
    }
  }

  Future<dynamic> _send(Future<http.Response> Function() fn) async {
    http.Response r;
    try {
      r = await fn().timeout(AppConfig.requestTimeout);
    } on TimeoutException {
      throw ApiException('HeatGuard service did not respond in time');
    } catch (e) {
      throw ApiException('HeatGuard service unavailable');
    }
    if (r.statusCode >= 400) throw ApiException(_detail(r), status: r.statusCode);
    if (r.body.isEmpty) return null;
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  String _detail(http.Response r) {
    try {
      final d = jsonDecode(r.body);
      final detail = d is Map ? d['detail'] : null;
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        return detail.map((e) => '${(e['loc'] as List?)?.last ?? ''}: ${e['msg']}').join('; ');
      }
    } catch (_) {}
    return 'Request failed (${r.statusCode})';
  }
}
