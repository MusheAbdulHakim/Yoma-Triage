import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/referral.dart';

class ApiException implements Exception {
  final int statusCode;
  final String body;

  ApiException(this.statusCode, this.body);

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
