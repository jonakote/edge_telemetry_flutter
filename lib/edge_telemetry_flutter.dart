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
import 'package:edge_telemetry_flutter/src/managers/session_manager.dart'; // NEW
import 'package:edge_telemetry_flutter/src/managers/span_manager.dart';
import 'package:edge_telemetry_flutter/src/managers/user_id_manager.dart';
import 'package:edge_telemetry_flutter/src/monitors/flutter_network_monitor.dart'
    as network_monitor;
import 'package:edge_telemetry_flutter/src/monitors/flutter_performance_monitor.dart';
import 'package:edge_telemetry_flutter/src/reports/simple_report_generator.dart';
import 'package:edge_telemetry_flutter/src/storage/memory_report_storage.dart';
import 'package:edge_telemetry_flutter/src/widgets/edge_navigation_observer.dart'
    as nav_widget;
import 'package:opentelemetry/api.dart';
import 'package:opentelemetry/sdk.dart' as otel_sdk;

/// Main EdgeTelemetry class with enhanced session tracking
class EdgeTelemetry {
  static EdgeTelemetry? _instance;
  static EdgeTelemetry get instance => _instance ??= EdgeTelemetry._();

  EdgeTelemetry._();

  // Core components
  SpanManager? _spanManager;
  late EventTracker _eventTracker;
  late nav_widget.EdgeNavigationObserver _navigationObserver;

  // User and session management
  late UserIdManager _userIdManager;
  late SessionManager _sessionManager; // NEW
  String? _currentUserId;

  // User profile data (separate from ID)
  final Map<String, String> _userProfile = {};

  // Monitoring components
  NetworkMonitor? _networkMonitor;
  PerformanceMonitor? _performanceMonitor;
  DeviceInfoCollector? _deviceInfoCollector;

  // Report system components
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
      useJsonFormat: useJsonFormat,
    );

    await instance._setup(config);
  }

  /// Internal setup method
  Future<void> _setup(TelemetryConfig config) async {
    if (_initialized) return;

    _config = config;

    try {
      // Initialize user ID manager and get/generate user ID
      await _initializeUserId();

      // NEW: Initialize session manager
      await _initializeSession();

      // Collect device information
      await _collectDeviceInfo();

      // Setup telemetry (JSON or OpenTelemetry)
      if (config.useJsonFormat) {
        await _setupJsonTelemetry();
      } else {
        await _setupOpenTelemetry();
      }

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
        'json_format': config.useJsonFormat.toString(),
        'user_id_auto_generated': 'true',
        'initialization_timestamp': DateTime.now().toIso8601String(),
      });

      if (config.debugMode) {
        print('✅ EdgeTelemetry initialized successfully');
        print('📱 Service: ${config.serviceName}');
        print('🔗 Endpoint: ${config.endpoint}');
        print('📡 Format: ${config.useJsonFormat ? 'JSON' : 'OpenTelemetry'}');
        print('👤 User ID: $_currentUserId');
        print('🔄 Session ID: ${_sessionManager.currentSessionId}');
        print('📊 Session Stats: ${_sessionManager.getSessionStats()}');
        print(
            '📊 Device: ${_globalAttributes['device.model'] ?? 'Unknown'} (${_globalAttributes['device.platform'] ?? 'Unknown'})');
        print(
            '📦 App: ${_globalAttributes['app.name'] ?? 'Unknown'} v${_globalAttributes['app.version'] ?? 'Unknown'}');
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

  /// Initialize user ID (auto-generated and persistent)
  Future<void> _initializeUserId() async {
    _userIdManager = UserIdManager();
    _currentUserId = await _userIdManager.getUserId();
  }

  /// NEW: Initialize session manager and start session
  Future<void> _initializeSession() async {
    _sessionManager = SessionManager();
    _currentSessionId = _generateSessionId();
    await _sessionManager.startSession(_currentSessionId!);
  }

  /// Collect device and app information
  Future<void> _collectDeviceInfo() async {
    _deviceInfoCollector = FlutterDeviceInfoCollector();
    _globalAttributes = await _deviceInfoCollector!.collectDeviceInfo();
    _globalAttributes.addAll(_config!.globalAttributes);

    // Add auto-generated user ID to global attributes
    _globalAttributes['user.id'] = _currentUserId!;
  }

  /// Get enriched attributes with session details
  Map<String, String> _getEnrichedAttributes(
      [Map<String, String>? customAttributes]) {
    return {
      ..._globalAttributes,
      ..._sessionManager.getSessionAttributes(), // NEW: Session details
      'network.type': _networkMonitor?.currentNetworkType ?? 'unknown',
      ...?customAttributes,
    };
  }

  /// Setup OpenTelemetry SDK
  Future<void> _setupOpenTelemetry() async {
    final processors = [
      otel_sdk.BatchSpanProcessor(
        otel_sdk.CollectorExporter(Uri.parse(_config!.endpoint)),
      ),
    ];

    final tracerProvider = otel_sdk.TracerProviderBase(processors: processors);
    registerGlobalTracerProvider(tracerProvider);

    final tracer = globalTracerProvider.getTracer(_config!.serviceName);
    _spanManager = SpanManager(tracer, _globalAttributes);

    // Set user context in span manager with auto-generated ID
    _spanManager!.setUser(userId: _currentUserId!);
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
    // Only initialize EventTrackerImpl for OpenTelemetry mode
    if (!_config!.useJsonFormat) {
      _eventTracker = EventTrackerImpl(_spanManager!);
    }
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

        // Only update spanManager for OpenTelemetry mode
        if (!_config!.useJsonFormat && _spanManager != null) {
          _spanManager = SpanManager(
              globalTracerProvider.getTracer(_config!.serviceName),
              _globalAttributes);
          // Maintain user context after network changes
          _spanManager!.setUser(userId: _currentUserId!);
          _applyUserProfile();
        }
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
        onEvent: (eventName, {attributes}) {
          // NEW: Track screen visits for session
          if (eventName == 'navigation.route_change' &&
              attributes != null &&
              attributes.containsKey('navigation.to')) {
            _sessionManager.recordScreen(attributes['navigation.to']!);
          }

          // Track the event
          _eventTracker.trackEvent(eventName, attributes: attributes);
        },
        onMetric: _eventTracker.trackMetric,
        onSpanStart: (spanName, {attributes}) {
          // Only use spanManager for OpenTelemetry mode
          if (!_config!.useJsonFormat && _spanManager != null) {
            final span =
                _spanManager!.createSpan(spanName, attributes: attributes);
            final routeName = spanName.startsWith('screen.')
                ? spanName.substring(7)
                : spanName;
            _navigationObserver.registerScreenSpan(routeName, span);
          }
        },
        onSpanEnd: (span) {
          // Only use spanManager for OpenTelemetry mode
          if (!_config!.useJsonFormat && _spanManager != null) {
            _spanManager!.endSpan(span);
          }
        },
      );
    }
  }

  // ==================== REPORT SYSTEM METHODS ====================

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

    _currentSession = TelemetrySession(
      sessionId: _currentSessionId!,
      startTime: DateTime.now(),
      userId: _currentUserId,
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

  // ==================== USER PROFILE API ====================

  /// Set user profile information (name, email, phone)
  void setUserProfile({
    String? name,
    String? email,
    String? phone,
    Map<String, String>? customAttributes,
  }) {
    _ensureInitialized();

    // Clear existing profile
    _userProfile.clear();

    // Add profile data
    if (name != null) _userProfile['user.name'] = name;
    if (email != null) _userProfile['user.email'] = email;
    if (phone != null) _userProfile['user.phone'] = phone;
    if (customAttributes != null) _userProfile.addAll(customAttributes);

    // Apply to span manager (OpenTelemetry mode)
    _applyUserProfile();

    // Track profile set event
    _eventTracker.trackEvent('user.profile_set', attributes: {
      'user.has_name': (name != null).toString(),
      'user.has_email': (email != null).toString(),
      'user.has_phone': (phone != null).toString(),
      'user.custom_attributes_count':
          (customAttributes?.length ?? 0).toString(),
      'profile_timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Apply user profile to span manager
  void _applyUserProfile() {
    if (!_config!.useJsonFormat && _spanManager != null) {
      _spanManager!.setUser(
        userId: _currentUserId!,
        email: _userProfile['user.email'],
        name: _userProfile['user.name'],
        customAttributes: {
          if (_userProfile['user.phone'] != null)
            'user.phone': _userProfile['user.phone']!,
          ..._userProfile.entries
              .where((e) =>
                  !['user.email', 'user.name', 'user.phone'].contains(e.key))
              .fold<Map<String, String>>({}, (map, entry) {
            map[entry.key] = entry.value;
            return map;
          }),
        },
      );
    }
  }

  /// Clear user profile (but keep auto-generated user ID)
  void clearUserProfile() {
    _ensureInitialized();

    _userProfile.clear();

    // Reset span manager to just have user ID
    if (!_config!.useJsonFormat && _spanManager != null) {
      _spanManager!.setUser(userId: _currentUserId!);
    }

    _eventTracker.trackEvent('user.profile_cleared');
  }

  /// Get current user ID (read-only)
  String? get currentUserId => _currentUserId;

  /// Get current user profile (read-only)
  Map<String, String> get currentUserProfile => Map.unmodifiable(_userProfile);

  /// NEW: Get current session information
  Map<String, dynamic> get currentSessionInfo =>
      _sessionManager.getSessionStats();

  // ==================== ENHANCED API WITH SESSION DETAILS ====================

  /// Execute a function within a span with automatic lifecycle management
  Future<T> withSpan<T>(
    String spanName,
    Future<T> Function() operation, {
    Map<String, String>? attributes,
  }) async {
    _ensureInitialized();

    // Only use spanManager in OpenTelemetry mode
    if (!_config!.useJsonFormat && _spanManager != null) {
      return _spanManager!.withSpan(spanName, operation,
          attributes: _getEnrichedAttributes(attributes));
    } else {
      // For JSON mode, just execute the operation
      return await operation();
    }
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
      'network.operation': operationName,
      ...?attributes,
    };

    return withSpan('network.$operationName', operation,
        attributes: networkAttributes);
  }

  /// Track a custom event (ENHANCED - now includes session details)
  void trackEvent(String eventName, {Map<String, String>? attributes}) {
    _ensureInitialized();

    // NEW: Record event in session manager
    _sessionManager.recordEvent();

    final enrichedAttributes = _getEnrichedAttributes(attributes);

    // Store locally for reports if enabled
    if (isLocalReportingEnabled && _currentSessionId != null) {
      final event = TelemetryEvent(
        id: _generateEventId(),
        sessionId: _currentSessionId!,
        eventName: eventName,
        timestamp: DateTime.now(),
        attributes: enrichedAttributes,
        userId: _currentUserId,
      );

      _reportStorage!.storeEvent(event).catchError((e) {
        if (_config?.debugMode == true) {
          print('⚠️ Failed to store event locally: $e');
        }
      });
    }

    // Continue with normal tracking
    _eventTracker.trackEvent(eventName, attributes: enrichedAttributes);
  }

  /// Track a custom metric (ENHANCED - now includes session details)
  void trackMetric(String metricName, double value,
      {Map<String, String>? attributes}) {
    _ensureInitialized();

    // NEW: Record metric in session manager
    _sessionManager.recordMetric();

    final enrichedAttributes = _getEnrichedAttributes(attributes);

    // Store locally for reports if enabled
    if (isLocalReportingEnabled && _currentSessionId != null) {
      final metric = TelemetryMetric(
        id: _generateMetricId(),
        sessionId: _currentSessionId!,
        metricName: metricName,
        value: value,
        timestamp: DateTime.now(),
        attributes: enrichedAttributes,
        userId: _currentUserId,
      );

      _reportStorage!.storeMetric(metric).catchError((e) {
        if (_config?.debugMode == true) {
          print('⚠️ Failed to store metric locally: $e');
        }
      });
    }

    // Continue with normal tracking
    _eventTracker.trackMetric(metricName, value,
        attributes: enrichedAttributes);
  }

  /// Track an error or exception
  void trackError(Object error,
      {StackTrace? stackTrace, Map<String, String>? attributes}) {
    _ensureInitialized();

    final enrichedAttributes = _getEnrichedAttributes(attributes);

    _eventTracker.trackError(error,
        stackTrace: stackTrace, attributes: enrichedAttributes);
  }

  /// Create a span manually (for advanced use cases)
  Span? startSpan(String name, {Map<String, String>? attributes}) {
    _ensureInitialized();

    // Only available in OpenTelemetry mode
    if (!_config!.useJsonFormat && _spanManager != null) {
      return _spanManager!
          .createSpan(name, attributes: _getEnrichedAttributes(attributes));
    }
    return null;
  }

  /// End a span manually (for advanced use cases)
  void endSpan(Span? span) {
    if (span == null) return;
    _ensureInitialized();

    // Only available in OpenTelemetry mode
    if (!_config!.useJsonFormat && _spanManager != null) {
      _spanManager!.endSpan(span);
    }
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

  /// Get global attributes (now includes session details)
  Map<String, String> get globalAttributes =>
      Map.unmodifiable(_getEnrichedAttributes());

  // ==================== REPORT API METHODS ====================

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
    // NEW: End session before disposing
    _sessionManager.endSession();

    // End current session if reporting is enabled
    if (isLocalReportingEnabled && _currentSessionId != null) {
      _currentSession = _currentSession?.copyWith(endTime: DateTime.now());
      _reportStorage?.endSession(_currentSessionId!).catchError((e) {
        if (_config?.debugMode == true) {
          print('⚠️ Failed to end session: $e');
        }
      });
    }

    // Dispose reporting components
    _reportStorage?.dispose();

    // Existing cleanup
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
