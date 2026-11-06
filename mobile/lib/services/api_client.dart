import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/referral.dart';

class ApiException implements Exception {
  final int statusCode;
  final String body;

  ApiException(this.statusCode, this.body);

  /// The server refused this request, and sending it again won't change that.
  /// 408 and 429 are 4xx codes that mean "try again later".
  bool get isPermanent =>
      statusCode >= 400 &&
      statusCode < 500 &&
      statusCode != 408 &&
      statusCode != 429;

  /// The server's explanation in a form a CHO can read.
  String get reason {
    try {
      final decoded = jsonDecode(body);
      final detail = decoded is Map ? decoded['detail'] : null;
      if (detail is String && detail.isNotEmpty) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        final message = first is Map ? first['msg'] : null;
        if (message is String && message.isNotEmpty) return message;
      }
    } catch (_) {
      // Not JSON: fall through to the status code.
    }
    return 'The server refused this referral (HTTP $statusCode)';
  }

  @override
  String toString() => 'ApiException($statusCode): $body';
}

class ApiClient {
  final http.Client _client;
  final String baseUrl;
  final String apiKey;

  ApiClient({http.Client? client, String? baseUrl, String? apiKey})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? ApiConfig.baseUrl,
        apiKey = apiKey ?? ApiConfig.apiKey;

  Map<String, String> _headers({bool json = false}) {
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    if (apiKey.isNotEmpty) headers['X-API-Key'] = apiKey;
    return headers;
  }

  Future<Map<String, dynamic>> createReferral(ReferralRequest req) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/api/v1/referral'),
      headers: _headers(json: true),
      body: jsonEncode(req.toJson()),
    );
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, res.body);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// First-run setup. Throws [ApiException] if this phone isn't an active CHO.
  Future<Map<String, dynamic>> lookupCho(String phone) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/api/v1/cho/lookup'),
      headers: _headers(json: true),
      body: jsonEncode({'phone': phone}),
    );
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, res.body);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDispatch(int id) async {
    final res = await _client.get(
      Uri.parse('$baseUrl/api/v1/dispatch/$id'),
      headers: _headers(),
    );
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, res.body);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getReferralGraph({
    String region = 'northern',
    String? district,
  }) async {
    final params = <String, String>{'region': region};
    if (district != null && district.isNotEmpty) {
      params['district'] = district;
    }
    final uri = Uri.parse('$baseUrl/api/v1/catalog/referral-graph')
        .replace(queryParameters: params);
    final res = await _client.get(uri, headers: _headers());
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, res.body);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
