// lib/src/telemetry/edge_telemetry.dart

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:edge_telemetry_flutter/src/collectors/flutter_device_info_collector.dart';
import 'package:edge_telemetry_flutter/src/core/config/telemetry_config.dart';
import 'package:edge_telemetry_flutter/src/core/interfaces/device_info_collector.dart';
import 'package:edge_telemetry_flutter/src/core/interfaces/event_tracker.dart';
import 'package:edge_telemetry_flutter/src/core/interfaces/network_monitor.dart';
import 'package:edge_telemetry_flutter/src/core/interfaces/performance_monitor.dart';
import 'package:edge_telemetry_flutter/src/core/interfaces/report_generator.dart';
import 'package:edge_telemetry_flutter/src/core/interfaces/report_storage.dart';
import 'package:edge_telemetry_flutter/src/core/models/generated_report.dart';
import 'package:edge_telemetry_flutter/src/core/models/report_data.dart';
import 'package:edge_telemetry_flutter/src/core/models/telemetry_session.dart';
import 'package:edge_telemetry_flutter/src/http/json_http_client.dart';
import 'package:edge_telemetry_flutter/src/managers/event_tracker_impl.dart';
import 'package:edge_telemetry_flutter/src/managers/json_event_tracker.dart';
import 'package:edge_telemetry_flutter/src/managers/span_manager.dart';
import 'package:edge_telemetry_flutter/src/monitors/flutter_network_monitor.dart'
    as network_monitor;
import 'package:edge_telemetry_flutter/src/monitors/flutter_performance_monitor.dart';
import 'package:edge_telemetry_flutter/src/reports/simple_report_generator.dart';
import 'package:edge_telemetry_flutter/src/storage/memory_report_storage.dart';
import 'package:edge_telemetry_flutter/src/widgets/edge_navigation_observer.dart'
    as nav_widget;
import 'package:opentelemetry/api.dart';
import 'package:opentelemetry/sdk.dart' as otel_sdk;

/// Main EdgeTelemetry class that orchestrates all monitoring components
///
/// This is the primary interface for users of the EdgeTelemetry package.
/// It manages the lifecycle of all monitoring components and provides
/// a simple, unified API for telemetry operations.
class EdgeTelemetry {
  static EdgeTelemetry? _instance;
  static EdgeTelemetry get instance => _instance ??= EdgeTelemetry._();

  EdgeTelemetry._();

  // Core components
  late SpanManager _spanManager;
  late EventTracker _eventTracker;
  late nav_widget.EdgeNavigationObserver _navigationObserver;

  // Monitoring components
  NetworkMonitor? _networkMonitor;
  PerformanceMonitor? _performanceMonitor;
  DeviceInfoCollector? _deviceInfoCollector;

  // NEW: Report system components
  ReportStorage? _reportStorage;
  ReportGenerator? _reportGenerator;
  TelemetrySession? _currentSession;
  String? _currentSessionId;

  // State
  bool _initialized = false;
  TelemetryConfig? _config;
  Map<String, String> _globalAttributes = {};

  // Subscriptions
  StreamSubscription<String>? _networkSubscription;

  /// Initialize EdgeTelemetry with the given configuration
  ///
  /// This is the main entry point for setting up telemetry.
  /// Call this once in your app's main() function.
  static Future<void> initialize({
    required String endpoint,
    required String serviceName,
    bool debugMode = false,
    Map<String, String>? globalAttributes,
    Duration? batchTimeout,
    int? maxBatchSize,
    bool enableNetworkMonitoring = true,
    bool enablePerformanceMonitoring = true,
    bool enableNavigationTracking = true,
    bool enableLocalReporting = false,
    String? reportStoragePath,
    Duration? dataRetentionPeriod,
    bool useJsonFormat = false,
  }) async {
    final config = TelemetryConfig(
      endpoint: endpoint,
      serviceName: serviceName,
      debugMode: debugMode,
      globalAttributes: globalAttributes ?? {},
      batchTimeout: batchTimeout ?? const Duration(seconds: 5),
      maxBatchSize: maxBatchSize ?? 512,
      enableNetworkMonitoring: enableNetworkMonitoring,
      enablePerformanceMonitoring: enablePerformanceMonitoring,
      enableNavigationTracking: enableNavigationTracking,
      enableLocalReporting: enableLocalReporting,
      reportStoragePath: reportStoragePath,
      dataRetentionPeriod: dataRetentionPeriod ?? const Duration(days: 30),
    );

    await instance._setup(config);
  }

  /// Internal setup method
  Future<void> _setup(TelemetryConfig config) async {
    if (_initialized) return;

    _config = config;

    try {
      // Collect device information
      await _collectDeviceInfo();

      // Setup OpenTelemetry
      await _setupJsonTelemetry();

      // Initialize core managers
      _initializeManagers();

      // Setup monitoring components
      await _setupMonitoring();

      // Setup navigation tracking
      _setupNavigationTracking();

      // Setup local reporting (if enabled)
      if (config.enableLocalReporting) {
        await _setupLocalReporting();
      }

      _initialized = true;

      // Track initialization
      _eventTracker.trackEvent('telemetry.initialized', attributes: {
        'service_name': config.serviceName,
        'debug_mode': config.debugMode.toString(),
        'network_monitoring': config.enableNetworkMonitoring.toString(),
        'performance_monitoring': config.enablePerformanceMonitoring.toString(),
        'navigation_tracking': config.enableNavigationTracking.toString(),
        'local_reporting': config.enableLocalReporting.toString(),
        'initialization_timestamp': DateTime.now().toIso8601String(),
      });

      if (config.debugMode) {
        print('✅ EdgeTelemetry initialized successfully');
        print('📱 Service: ${config.serviceName}');
        print('🔗 Endpoint: ${config.endpoint}');
        print(
            '📊 Device: ${_globalAttributes['device.model'] ?? 'Unknown'} (${_globalAttributes['device.platform'] ?? 'Unknown'})');
        print(
            '📦 App: ${_globalAttributes['app.name'] ?? 'Unknown'} v${_globalAttributes['app.version'] ?? 'Unknown'}');
        // NEW: Add this block
        if (config.enableLocalReporting) {
          print('📋 Local reporting: Enabled');
        }
      }
    } catch (e, stackTrace) {
      if (config.debugMode) {
        print('❌ EdgeTelemetry initialization failed: $e');
        print('Stack trace: $stackTrace');
      }
      rethrow;
    }
  }

  /// Collect device and app information
  Future<void> _collectDeviceInfo() async {
    _deviceInfoCollector = FlutterDeviceInfoCollector();
    _globalAttributes = await _deviceInfoCollector!.collectDeviceInfo();
    _globalAttributes.addAll(_config!.globalAttributes);
  }

  /// Setup OpenTelemetry SDK
  Future<void> _setupOpenTelemetry() async {
    final processors = [
      otel_sdk.BatchSpanProcessor(
        otel_sdk.CollectorExporter(Uri.parse(_config!.endpoint)),
      ),
    ];

    // Note: SimpleSpanProcessor and ConsoleExporter are not available in this OpenTelemetry version
    // Debug output will be handled through the batch processor

    final tracerProvider = otel_sdk.TracerProviderBase(processors: processors);
    registerGlobalTracerProvider(tracerProvider);

    final tracer = globalTracerProvider.getTracer(_config!.serviceName);
    _spanManager = SpanManager(tracer, _globalAttributes);
  }

  /// Setup JSON telemetry instead of OpenTelemetry
  Future<void> _setupJsonTelemetry() async {
    final jsonClient = JsonHttpClient(endpoint: _config!.endpoint);
    _eventTracker = JsonEventTracker(jsonClient, _globalAttributes);

    if (_config!.debugMode) {
      print('📡 JSON telemetry configured for endpoint: ${_config!.endpoint}');
    }
  }

  /// Initialize core managers
  void _initializeManagers() {
    _eventTracker = EventTrackerImpl(_spanManager);
  }

  /// Setup monitoring components
  Future<void> _setupMonitoring() async {
    // Network monitoring
    if (_config!.enableNetworkMonitoring) {
      _networkMonitor =
          network_monitor.FlutterNetworkMonitor(eventTracker: _eventTracker);
      await _networkMonitor!.initialize();

      // Listen to network changes and update global attributes
      _networkSubscription =
          _networkMonitor!.networkTypeChanges.listen((networkType) {
        _globalAttributes['network.type'] = networkType;
        _spanManager = SpanManager(
            globalTracerProvider.getTracer(_config!.serviceName),
            _globalAttributes);
      });
    }

    // Performance monitoring
    if (_config!.enablePerformanceMonitoring) {
      _performanceMonitor =
          FlutterPerformanceMonitor(eventTracker: _eventTracker);
      await _performanceMonitor!.initialize();
    }
  }

  /// Setup navigation tracking
  void _setupNavigationTracking() {
    if (_config!.enableNavigationTracking) {
      _navigationObserver = nav_widget.EdgeNavigationObserver(
        onEvent: _eventTracker.trackEvent,
        onMetric: _eventTracker.trackMetric,
        onSpanStart: (spanName, {attributes}) {
          final span =
              _spanManager.createSpan(spanName, attributes: attributes);
          // Extract route name from span name
          final routeName =
              spanName.startsWith('screen.') ? spanName.substring(7) : spanName;
          _navigationObserver.registerScreenSpan(routeName, span);
        },
        onSpanEnd: _spanManager.endSpan,
      );
    }
  }

  // ==================== NEW: REPORT SYSTEM METHODS ====================

  /// Setup local reporting
  Future<void> _setupLocalReporting() async {
    try {
      // Initialize storage (using memory storage for now)
      _reportStorage = MemoryReportStorage();
      await _reportStorage!.initialize();

      // Initialize report generator
      _reportGenerator = SimpleReportGenerator(_reportStorage!);

      // Start a new session
      await _startNewSession();

      if (_config!.debugMode) {
        print('📊 Local reporting initialized');
      }
    } catch (e) {
      if (_config!.debugMode) {
        print('⚠️ Local reporting setup failed: $e');
      }
      // Continue without local reporting
    }
  }

  /// Start a new telemetry session
  Future<void> _startNewSession() async {
    if (_reportStorage == null) return;

    _currentSessionId = _generateSessionId();
    _currentSession = TelemetrySession(
      sessionId: _currentSessionId!,
      startTime: DateTime.now(),
      deviceAttributes: Map.from(_globalAttributes),
      appAttributes: {
        'app.name': _globalAttributes['app.name'] ?? 'unknown',
        'app.version': _globalAttributes['app.version'] ?? 'unknown',
      },
    );

    await _reportStorage!.startSession(_currentSession!);
  }

  String _generateSessionId() {
    return 'session_${DateTime.now().millisecondsSinceEpoch}_${_globalAttributes['device.platform'] ?? 'unknown'}';
  }

  // ==================== PUBLIC API (Enhanced) ====================

  /// Set user context for all subsequent telemetry
  void setUser({
    required String userId,
    String? email,
    String? name,
    Map<String, String>? customAttributes,
  }) {
    _ensureInitialized();
    _spanManager.setUser(
      userId: userId,
      email: email,
      name: name,
      customAttributes: customAttributes,
    );

    _eventTracker.trackEvent('user.context_set', attributes: {
      'user.id': userId,
      if (email != null) 'user.has_email': 'true',
      if (name != null) 'user.has_name': 'true',
      'user.custom_attributes_count':
          (customAttributes?.length ?? 0).toString(),
    });
  }

  /// Clear user context
  void clearUser() {
    _ensureInitialized();
    _spanManager.clearUser();
    _eventTracker.trackEvent('user.context_cleared');
  }

  /// Execute a function within a span with automatic lifecycle management
  Future<T> withSpan<T>(
    String spanName,
    Future<T> Function() operation, {
    Map<String, String>? attributes,
  }) async {
    _ensureInitialized();
    return _spanManager.withSpan(spanName, operation, attributes: attributes);
  }

  /// Execute a network operation with automatic network context
  Future<T> withNetworkSpan<T>(
    String operationName,
    String url,
    String method,
    Future<T> Function() operation, {
    Map<String, String>? attributes,
  }) async {
    _ensureInitialized();

    final networkAttributes = {
      'http.url': url,
      'http.method': method,
      'network.type': _networkMonitor?.currentNetworkType ?? 'unknown',
      'network.operation': operationName,
      ...?attributes,
    };

    return withSpan('network.$operationName', operation,
        attributes: networkAttributes);
  }

  /// Track a custom event (ENHANCED - now also stores locally if reporting enabled)
  void trackEvent(String eventName, {Map<String, String>? attributes}) {
    _ensureInitialized();

    final enrichedAttributes = {
      'network.type': _networkMonitor?.currentNetworkType ?? 'unknown',
      ...?attributes,
    };

    // NEW: Store locally for reports if enabled
    if (isLocalReportingEnabled && _currentSessionId != null) {
      final event = TelemetryEvent(
        id: _generateEventId(),
        sessionId: _currentSessionId!,
        eventName: eventName,
        timestamp: DateTime.now(),
        attributes: enrichedAttributes,
        userId: _spanManager.userId,
      );

      _reportStorage!.storeEvent(event).catchError((e) {
        if (_config?.debugMode == true) {
          print('⚠️ Failed to store event locally: $e');
        }
      });
    }

    // Continue with normal tracking (unchanged)
    _eventTracker.trackEvent(eventName, attributes: enrichedAttributes);
  }

  /// Track a custom metric (ENHANCED - now also stores locally if reporting enabled)
  void trackMetric(String metricName, double value,
      {Map<String, String>? attributes}) {
    _ensureInitialized();

    final enrichedAttributes = {
      'network.type': _networkMonitor?.currentNetworkType ?? 'unknown',
      ...?attributes,
    };

    // NEW: Store locally for reports if enabled
    if (isLocalReportingEnabled && _currentSessionId != null) {
      final metric = TelemetryMetric(
        id: _generateMetricId(),
        sessionId: _currentSessionId!,
        metricName: metricName,
        value: value,
        timestamp: DateTime.now(),
        attributes: enrichedAttributes,
        userId: _spanManager.userId,
      );

      _reportStorage!.storeMetric(metric).catchError((e) {
        if (_config?.debugMode == true) {
          print('⚠️ Failed to store metric locally: $e');
        }
      });
    }

    // Continue with normal tracking (unchanged)
    _eventTracker.trackMetric(metricName, value,
        attributes: enrichedAttributes);
  }

  /// Track an error or exception
  void trackError(Object error,
      {StackTrace? stackTrace, Map<String, String>? attributes}) {
    _ensureInitialized();

    final enrichedAttributes = {
      'network.type': _networkMonitor?.currentNetworkType ?? 'unknown',
      ...?attributes,
    };

    _eventTracker.trackError(error,
        stackTrace: stackTrace, attributes: enrichedAttributes);
  }

  /// Create a span manually (for advanced use cases)
  Span startSpan(String name, {Map<String, String>? attributes}) {
    _ensureInitialized();
    return _spanManager.createSpan(name, attributes: attributes);
  }

  /// End a span manually (for advanced use cases)
  void endSpan(Span span) {
    _ensureInitialized();
    _spanManager.endSpan(span);
  }

  /// Get the navigation observer for MaterialApp
  nav_widget.EdgeNavigationObserver get navigationObserver {
    _ensureInitialized();
    return _navigationObserver;
  }

  /// Get current network type
  String get currentNetworkType {
    return _networkMonitor?.currentNetworkType ?? 'unknown';
  }

  /// Get connectivity information
  Map<String, String> getConnectivityInfo() {
    if (_networkMonitor is network_monitor.FlutterNetworkMonitor) {
      return (_networkMonitor as network_monitor.FlutterNetworkMonitor)
          .getConnectivityInfo();
    }
    return {'network.type': 'unknown'};
  }

  /// Check if telemetry is initialized
  bool get isInitialized => _initialized;

  /// Get current configuration
  TelemetryConfig? get config => _config;

  /// Get global attributes
  Map<String, String> get globalAttributes =>
      Map.unmodifiable(_globalAttributes);

  // ==================== NEW: REPORT API METHODS ====================

  /// Generate a summary report of recent activity
  Future<GeneratedReport> generateSummaryReport({
    DateTime? startTime,
    DateTime? endTime,
    String? title,
  }) async {
    _ensureReportingEnabled();
    return await _reportGenerator!.generateSummaryReport(
      startTime: startTime,
      endTime: endTime,
      title: title,
    );
  }

  /// Generate a detailed performance report
  Future<GeneratedReport> generatePerformanceReport({
    DateTime? startTime,
    DateTime? endTime,
    String? title,
  }) async {
    _ensureReportingEnabled();
    return await _reportGenerator!.generatePerformanceReport(
      startTime: startTime,
      endTime: endTime,
      title: title,
    );
  }

  /// Generate a user behavior analysis report
  Future<GeneratedReport> generateUserBehaviorReport({
    DateTime? startTime,
    DateTime? endTime,
    String? title,
  }) async {
    _ensureReportingEnabled();
    return await _reportGenerator!.generateUserBehaviorReport(
      startTime: startTime,
      endTime: endTime,
      title: title,
    );
  }

  /// Export report to file
  Future<String> exportReportToFile(
      GeneratedReport report, String filePath) async {
    _ensureReportingEnabled();

    String content;
    if (report.format == 'json') {
      content = report.toJson().toString();
    } else {
      content = report.data.toString();
    }

    final file = File(filePath);
    await file.writeAsString(content);
    return filePath;
  }

  /// Check if local reporting is enabled
  bool get isLocalReportingEnabled =>
      _reportStorage != null && _reportGenerator != null;

  /// Get current session information
  TelemetrySession? getCurrentSession() => _currentSession;

  // ==================== INTERNAL METHODS ====================

  String _generateEventId() =>
      'event_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
  String _generateMetricId() =>
      'metric_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
          'EdgeTelemetry is not initialized. Call EdgeTelemetry.initialize() first.');
    }
  }

  void _ensureReportingEnabled() {
    if (!isLocalReportingEnabled) {
      throw StateError(
        'Local reporting is not enabled. Set enableLocalReporting: true when initializing EdgeTelemetry.',
      );
    }
  }

  /// Dispose all resources (call when app is shutting down)
  void dispose() {
    // NEW: End current session if reporting is enabled
    if (isLocalReportingEnabled && _currentSessionId != null) {
      _currentSession = _currentSession?.copyWith(endTime: DateTime.now());
      _reportStorage?.endSession(_currentSessionId!).catchError((e) {
        if (_config?.debugMode == true) {
          print('⚠️ Failed to end session: $e');
        }
      });
    }

    // NEW: Dispose reporting components
    _reportStorage?.dispose();

    // Existing cleanup (unchanged)
    _networkSubscription?.cancel();
    _networkMonitor?.dispose();
    _performanceMonitor?.dispose();
    _navigationObserver.dispose();
    _initialized = false;

    if (_config?.debugMode == true) {
      print('🧹 EdgeTelemetry disposed');
    }
  }
}
