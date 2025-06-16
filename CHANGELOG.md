# Changelog

## [1.1.1] - 2024-12-19

### Added
- JSON telemetry support as alternative to protobuf format
- `JsonHttpClient` - Simple HTTP client for sending JSON data to custom backends
- `JsonEventTracker` - Event tracker implementation that sends data as JSON instead of OpenTelemetry spans
- `useJsonFormat` parameter to `EdgeTelemetry.initialize()` method for choosing telemetry format

### Modified
- **EdgeTelemetry class**: Added JSON mode support with automatic format selection
- **Main initialization**: Updated to support custom backend endpoints (e.g., `/v1/logs`)
- **Event tracking**: Events, metrics, and errors can now be sent as structured JSON objects

### Technical Details
#### New Files:
- `lib/src/http/json_http_client.dart`
- `lib/src/managers/json_event_tracker.dart`

#### Modified Files:
- `lib/edge_telemetry_flutter.dart` - Added JSON telemetry setup and configuration
- `lib/main.dart` - Updated endpoint and enabled JSON format

#### JSON Data Structure:
```json
{
 "type": "event|metric|error",
 "eventName": "button_clicked",
 "timestamp": "2024-12-19T15:30:45.123Z",
 "attributes": {
   "device.platform": "android",
   "app.version": "1.0.0",
   "user.id": "demo-user-123"
 }
}