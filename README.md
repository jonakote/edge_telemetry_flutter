# EdgeTelemetry Flutter

A comprehensive Real User Monitoring (RUM) and telemetry package for Flutter applications.

## Features

- 🚀 **Automatic Performance Monitoring** - Frame drops, memory usage, app startup times
- 🌐 **Network Monitoring** - Connectivity changes and request tracking  
- 📊 **Local Reporting** - Generate comprehensive reports without external dependencies
- 🎯 **Navigation Tracking** - Automatic screen transitions and user flows
- 👤 **User Context Management** - Associate telemetry with user sessions
- 🔧 **OpenTelemetry Integration** - Industry-standard telemetry format
- 🛡️ **Error Tracking** - Automatic exception capture with context

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  edge_telemetry_flutter: ^1.0.0
```

## Quick Start

### Basic Setup

```dart
import 'package:edge_telemetry_flutter/edge_telemetry_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await EdgeTelemetry.initialize(
    endpoint: 'your-opentelemetry-endpoint',
    serviceName: 'my-app',
    enableLocalReporting: true,
  );

  runApp(MyApp());
}
```

### Add Navigation Tracking

```dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [EdgeTelemetry.instance.navigationObserver],
      home: HomeScreen(),
    );
  }
}
```

## Usage

### Track Events

```dart
EdgeTelemetry.instance.trackEvent('user.signup');

EdgeTelemetry.instance.trackEvent('purchase.completed', attributes: {
  'product_id': 'pro_123',
  'amount': '29.99',
});
```

### Track Metrics

```dart
EdgeTelemetry.instance.trackMetric('api.response_time', 150.0);
```

### Generate Reports

```dart
final report = await EdgeTelemetry.instance.generateSummaryReport();
await EdgeTelemetry.instance.exportReportToFile(report, '/path/to/report.json');
```

## License

MIT License
