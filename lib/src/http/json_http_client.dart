// lib/src/http/json_http_client.dart

import 'package:http/http.dart' as http;

class JsonHttpClient {
  final String endpoint;
  final http.Client _httpClient;
  final Map<String, String>? headers;

  JsonHttpClient({required this.endpoint, this.headers,}) : _httpClient = http.Client();

  Future<bool> sendTelemetryData(Map<String, dynamic> data) async {
    try {
      final uri = Uri.parse(endpoint);
      final response = await _httpClient.post(
        uri,
        headers: {'Content-Type': 'application/json', ...?headers},
        body: data,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        print('✅ Sent telemetry data successfully');
        return true;
      } else {
        print('❌ Failed: HTTP ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Error: $e');
      return false;
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
