// lib/src/managers/json_event_tracker.dart

import '../core/interfaces/event_tracker.dart';
import '../http/json_http_client.dart';

class JsonEventTracker implements EventTracker {
  final JsonHttpClient _httpClient;
  final Map<String, String> _globalAttributes;

  JsonEventTracker(this._httpClient, this._globalAttributes);

  @override
  void trackEvent(String eventName, {Map<String, String>? attributes}) {
    final eventData = {
      'type': 'event',
      'eventName': eventName,
      'timestamp': DateTime.now().toIso8601String(),
      'attributes': {
        ..._globalAttributes,
        ...?attributes,
      },
    };

    _httpClient.sendTelemetryData(eventData);
  }

  @override
  void trackMetric(String metricName, double value,
      {Map<String, String>? attributes}) {
    final metricData = {
      'type': 'metric',
      'metricName': metricName,
      'value': value,
      'timestamp': DateTime.now().toIso8601String(),
      'attributes': {
        ..._globalAttributes,
        ...?attributes,
      },
    };

    _httpClient.sendTelemetryData(metricData);
  }

  @override
  void trackError(Object error,
      {StackTrace? stackTrace, Map<String, String>? attributes}) {
    final errorData = {
      'type': 'error',
      'error': error.toString(),
      'timestamp': DateTime.now().toIso8601String(),
      'attributes': {
        ..._globalAttributes,
        ...?attributes,
      },
    };

    _httpClient.sendTelemetryData(errorData);
  }
}
