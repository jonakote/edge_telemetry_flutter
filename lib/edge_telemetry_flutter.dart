// lib/src/telemetry/edge_telemetry.dart

import 'dart:async';

import 'package:edge_telemetry_flutter/src/collectors/flutter_device_info_collector.dart';
import 'package:edge_telemetry_flutter/src/core/config/telemetry_config.dart';
import 'package:edge_telemetry_flutter/src/core/interfaces/device_info_collector.dart';
import 'package:edge_telemetry_flutter/src/core/interfaces/event_tracker.dart';
import 'package:edge_telemetry_flutter/src/core/interfaces/network_monitor.dart';
import 'package:edge_telemetry_flutter/src/core/interfaces/performance_monitor.dart';
import 'package:edge_telemetry_flutter/src/managers/event_tracker_impl.dart';
import 'package:edge_telemetry_flutter/src/managers/span_manager.dart';
import 'package:edge_telemetry_flutter/src/monitors/flutter_network_monitor.dart'
    as network_monitor;
import 'package:edge_telemetry_flutter/src/monitors/flutter_performance_monitor.dart';
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
    );

    await instance._setup(config);
  }

  /// Internal setup method
  Future<void> _setup(TelemetryConfig config) async {
    if (_initialized) return;

    _config = config;

    try {
      // Step 1: Collect device information
      await _collectDeviceInfo();

      // Step 2: Setup OpenTelemetry
      await _setupOpenTelemetry();

      // Step 3: Initialize core managers
      _initializeManagers();

      // Step 4: Setup monitoring components
      await _setupMonitoring();

      // Step 5: Setup navigation tracking
      _setupNavigationTracking();

      _initialized = true;

      // Track initialization
      _eventTracker.trackEvent('telemetry.initialized', attributes: {
        'service_name': config.serviceName,
        'debug_mode': config.debugMode.toString(),
        'network_monitoring': config.enableNetworkMonitoring.toString(),
        'performance_monitoring': config.enablePerformanceMonitoring.toString(),
        'navigation_tracking': config.enableNavigationTracking.toString(),
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

  // ==================== PUBLIC API ====================

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

  /// Track a custom event
  void trackEvent(String eventName, {Map<String, String>? attributes}) {
    _ensureInitialized();

    final enrichedAttributes = {
      'network.type': _networkMonitor?.currentNetworkType ?? 'unknown',
      ...?attributes,
    };

    _eventTracker.trackEvent(eventName, attributes: enrichedAttributes);
  }

  /// Track a custom metric
  void trackMetric(String metricName, double value,
      {Map<String, String>? attributes}) {
    _ensureInitialized();

    final enrichedAttributes = {
      'network.type': _networkMonitor?.currentNetworkType ?? 'unknown',
      ...?attributes,
    };

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

  // ==================== INTERNAL METHODS ====================

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
          'EdgeTelemetry is not initialized. Call EdgeTelemetry.initialize() first.');
    }
  }

  /// Dispose all resources (call when app is shutting down)
  void dispose() {
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
