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

  ApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? ApiConfig.baseUrl;

  Future<Map<String, dynamic>> createReferral(ReferralRequest req) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/api/v1/referral'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(req.toJson()),
    );
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, res.body);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDispatch(int id) async {
    final res = await _client.get(Uri.parse('$baseUrl/api/v1/dispatch/$id'));
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
    final res = await _client.get(uri);
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, res.body);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
