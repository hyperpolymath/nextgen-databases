// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Production Readiness
 *
 * Pre-flight checks and production readiness validation
 */

/** Readiness check category */
type checkCategory =
  | Security
  | Performance
  | Reliability
  | Observability
  | Configuration

/** Readiness check result */
type checkResult = {
  name: string,
  category: checkCategory,
  passed: bool,
  message: string,
  severity: int, // 1 = critical, 2 = warning, 3 = info
}

/** Readiness report */
type readinessReport = {
  ready: bool,
  checks: array<checkResult>,
  criticalFailures: int,
  warnings: int,
  timestamp: float,
}

/** Security checks */
let checkApiKeyRequired = (required: bool): checkResult => {
  {
    name: "api_key_required",
    category: Security,
    passed: required,
    message: required ? "API key authentication enabled" : "API key authentication disabled",
    severity: 1,
  }
}

let checkCorsConfiguration = (origins: array<string>): checkResult => {
  let hasWildcard = origins->Array.includes("*")
  {
    name: "cors_configuration",
    category: Security,
    passed: !hasWildcard,
    message: hasWildcard
      ? "CORS allows all origins (wildcard)"
      : `CORS restricted to ${Int.toString(Array.length(origins))} origins`,
    severity: 2,
  }
}

let checkTlsEnabled = (enabled: bool): checkResult => {
  {
    name: "tls_enabled",
    category: Security,
    passed: enabled,
    message: enabled ? "TLS/HTTPS enabled" : "TLS/HTTPS not enabled",
    severity: 1,
  }
}

/** Performance checks */
let checkConnectionPoolSize = (size: int): checkResult => {
  let adequate = size >= 10
  {
    name: "connection_pool_size",
    category: Performance,
    passed: adequate,
    message: adequate
      ? `Connection pool size ${Int.toString(size)} is adequate`
      : `Connection pool size ${Int.toString(size)} may be too small`,
    severity: 2,
  }
}

let checkQueryCacheEnabled = (enabled: bool): checkResult => {
  {
    name: "query_cache_enabled",
    category: Performance,
    passed: enabled,
    message: enabled ? "Query plan caching enabled" : "Query plan caching disabled",
    severity: 3,
  }
}

/** Reliability checks */
let checkHealthEndpoint = (enabled: bool): checkResult => {
  {
    name: "health_endpoint",
    category: Reliability,
    passed: enabled,
    message: enabled ? "Health check endpoint available" : "No health check endpoint",
    severity: 1,
  }
}

let checkGracefulShutdown = (configured: bool): checkResult => {
  {
    name: "graceful_shutdown",
    category: Reliability,
    passed: configured,
    message: configured ? "Graceful shutdown configured" : "Graceful shutdown not configured",
    severity: 2,
  }
}

/** Observability checks */
let checkMetricsEnabled = (enabled: bool): checkResult => {
  {
    name: "metrics_enabled",
    category: Observability,
    passed: enabled,
    message: enabled ? "Prometheus metrics enabled" : "Metrics disabled",
    severity: 2,
  }
}

let checkTracingEnabled = (enabled: bool): checkResult => {
  {
    name: "tracing_enabled",
    category: Observability,
    passed: enabled,
    message: enabled ? "Distributed tracing enabled" : "Distributed tracing disabled",
    severity: 3,
  }
}

let checkLoggingLevel = (level: string): checkResult => {
  let isProduction = level == "info" || level == "warn" || level == "error"
  {
    name: "logging_level",
    category: Observability,
    passed: isProduction,
    message: isProduction
      ? `Log level '${level}' appropriate for production`
      : `Log level '${level}' may be too verbose for production`,
    severity: 3,
  }
}

/** Configuration checks */
let checkEnvironmentSet = (env: string): checkResult => {
  let isProduction = env == "production" || env == "prod"
  {
    name: "environment_set",
    category: Configuration,
    passed: isProduction,
    message: isProduction
      ? "Environment set to production"
      : `Environment is '${env}', expected 'production'`,
    severity: 2,
  }
}

/** Run all readiness checks */
type readinessConfig = {
  apiKeyRequired: bool,
  corsOrigins: array<string>,
  tlsEnabled: bool,
  connectionPoolSize: int,
  queryCacheEnabled: bool,
  healthEndpointEnabled: bool,
  gracefulShutdownConfigured: bool,
  metricsEnabled: bool,
  tracingEnabled: bool,
  loggingLevel: string,
  environment: string,
}

let runChecks = (config: readinessConfig): readinessReport => {
  let checks = [
    // Security
    checkApiKeyRequired(config.apiKeyRequired),
    checkCorsConfiguration(config.corsOrigins),
    checkTlsEnabled(config.tlsEnabled),
    // Performance
    checkConnectionPoolSize(config.connectionPoolSize),
    checkQueryCacheEnabled(config.queryCacheEnabled),
    // Reliability
    checkHealthEndpoint(config.healthEndpointEnabled),
    checkGracefulShutdown(config.gracefulShutdownConfigured),
    // Observability
    checkMetricsEnabled(config.metricsEnabled),
    checkTracingEnabled(config.tracingEnabled),
    checkLoggingLevel(config.loggingLevel),
    // Configuration
    checkEnvironmentSet(config.environment),
  ]

  let criticalFailures = checks->Array.filter(c => !c.passed && c.severity == 1)->Array.length
  let warnings = checks->Array.filter(c => !c.passed && c.severity == 2)->Array.length

  {
    ready: criticalFailures == 0,
    checks,
    criticalFailures,
    warnings,
    timestamp: Js.Date.now(),
  }
}

/** Format report as string */
let formatReport = (report: readinessReport): string => {
  let lines: array<string> = []

  lines->Array.push(report.ready ? "✓ READY FOR PRODUCTION" : "✗ NOT READY FOR PRODUCTION")->ignore
  lines->Array.push("")->ignore

  let categoryToString = c =>
    switch c {
    | Security => "Security"
    | Performance => "Performance"
    | Reliability => "Reliability"
    | Observability => "Observability"
    | Configuration => "Configuration"
    }

  report.checks->Array.forEach(check => {
    let icon = check.passed ? "✓" : "✗"
    let severity = switch check.severity {
    | 1 => "[CRITICAL]"
    | 2 => "[WARNING]"
    | _ => "[INFO]"
    }
    let line = `${icon} ${categoryToString(check.category)}: ${check.name} - ${check.message} ${check.passed ? "" : severity}`
    lines->Array.push(line)->ignore
  })

  lines->Array.push("")->ignore
  lines->Array.push(`Critical failures: ${Int.toString(report.criticalFailures)}`)->ignore
  lines->Array.push(`Warnings: ${Int.toString(report.warnings)}`)->ignore

  lines->Array.join("\n")
}
