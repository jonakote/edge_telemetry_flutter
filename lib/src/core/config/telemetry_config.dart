// lib/src/core/config/telemetry_config.dart

/// Configuration class for EdgeTelemetry initialization
///
/// Contains all settings needed to set up telemetry collection
class TelemetryConfig {
  /// Name of the service/app for telemetry identification
  final String serviceName;

  /// OpenTelemetry collector endpoint URL
  final String endpoint;

  /// Enable debug logging and console output
  final bool debugMode;

  /// Global attributes added to all spans and events
  final Map<String, String> globalAttributes;

  /// Batch timeout for sending telemetry data
  final Duration batchTimeout;

  /// Maximum number of spans in a batch
  final int maxBatchSize;

  /// Enable automatic network monitoring
  final bool enableNetworkMonitoring;

  /// Enable automatic performance monitoring
  final bool enablePerformanceMonitoring;

  /// Enable automatic error and crash reporting
  final bool enableErrorReporting;

  /// Enable automatic navigation tracking
  final bool enableNavigationTracking;

  const TelemetryConfig({
    required this.serviceName,
    required this.endpoint,
    this.debugMode = false,
    this.globalAttributes = const {},
    this.batchTimeout = const Duration(seconds: 5),
    this.maxBatchSize = 512,
    this.enableNetworkMonitoring = true,
    this.enablePerformanceMonitoring = true,
    this.enableErrorReporting = true,
    this.enableNavigationTracking = true,
  });

  /// Create a copy of this config with some values overridden
  TelemetryConfig copyWith({
    String? serviceName,
    String? endpoint,
    bool? debugMode,
    Map<String, String>? globalAttributes,
    Duration? batchTimeout,
    int? maxBatchSize,
    bool? enableNetworkMonitoring,
    bool? enablePerformanceMonitoring,
    bool? enableErrorReporting,
    bool? enableNavigationTracking,
  }) {
    return TelemetryConfig(
      serviceName: serviceName ?? this.serviceName,
      endpoint: endpoint ?? this.endpoint,
      debugMode: debugMode ?? this.debugMode,
      globalAttributes: globalAttributes ?? this.globalAttributes,
      batchTimeout: batchTimeout ?? this.batchTimeout,
      maxBatchSize: maxBatchSize ?? this.maxBatchSize,
      enableNetworkMonitoring:
          enableNetworkMonitoring ?? this.enableNetworkMonitoring,
      enablePerformanceMonitoring:
          enablePerformanceMonitoring ?? this.enablePerformanceMonitoring,
      enableErrorReporting: enableErrorReporting ?? this.enableErrorReporting,
      enableNavigationTracking:
          enableNavigationTracking ?? this.enableNavigationTracking,
    );
  }
}
