import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

typedef J = Map<String, dynamic>;

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Thin JSON client for the Longview backend. Amounts are pence (int); dates are "yyyy-MM-dd".
class Api {
  Api({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  /// Bumped after any write so screens know to reload.
  final changes = ValueNotifier<int>(0);
  void _changed() => changes.value++;

  Uri _u(String path, [Map<String, String?>? q]) {
    final query = {for (final e in (q ?? {}).entries) if (e.value != null && e.value!.isNotEmpty) e.key: e.value!};
    return Uri.parse('${Config.apiBaseUrl}$path').replace(queryParameters: query.isEmpty ? null : query);
  }

  Map<String, String> headers({String type = 'application/json'}) => {'Content-Type': type};

  Future<dynamic> _send(String method, String path, {Object? body, Map<String, String?>? query}) async {
    final req = http.Request(method, _u(path, query))..headers.addAll(headers());
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await _http.send(req));
    if (res.statusCode >= 400) {
      String msg = 'Something went wrong (${res.statusCode}).';
      try { msg = (jsonDecode(res.body) as J)['error'] as String? ?? msg; } catch (_) {}
      throw ApiException(res.statusCode, msg);
    }
    if (method != 'GET') _changed();
    if (res.body.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<dynamic> get(String path, [Map<String, String?>? query]) => _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body ?? {});
  Future<dynamic> put(String path, Object body) => _send('PUT', path, body: body);
  Future<dynamic> patch(String path, Object body) => _send('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<void> uploadLogo(int accountId, Uint8List bytes, String contentType) async {
    final res = await _http.put(_u('/api/accounts/$accountId/logo'), headers: headers(type: contentType), body: bytes);
    if (res.statusCode >= 400) throw ApiException(res.statusCode, 'Upload failed');
    _changed();
  }

  // Convenience calls used by several screens.
  Future<List<J>> categories() async => (await get('/api/categories') as List).cast<J>();
  Future<List<J>> accounts() async => (await get('/api/accounts') as List).cast<J>();
}
