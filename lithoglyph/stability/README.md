# Lith Stability Module

Production stability features for Lith including configuration validation, health checks, graceful shutdown, and readiness verification.

## Features

| Feature | File | Description |
|---------|------|-------------|
| Configuration | `Lith_Stability_Config.res` | Type-safe config with validation |
| Health Checks | `Lith_Stability_Health.res` | Component health monitoring |
| Graceful Shutdown | `Lith_Stability_Shutdown.res` | Coordinated shutdown sequence |
| Readiness | `Lith_Stability_Readiness.res` | Production readiness checks |

## Configuration Validation

Type-safe configuration with environment-specific rules.

```rescript
// Load and validate configuration
let config = loadFromEnv()

switch validate(config) {
| Valid(cfg) => startServer(cfg)
| Invalid(errors) => {
    Console.error("Configuration errors:")
    Console.error(formatErrors(errors))
    Process.exit(1)
  }
}
```

### Production Rules

In production environment, validation enforces:
- API key authentication required
- No wildcard CORS origins
- Positive connection limits
- Valid port numbers

## Health Checks

Comprehensive health monitoring for Kubernetes probes.

```rescript
// Create health checker
let checker = createDefault(~version="0.0.10")

// Register custom check
register(checker, "database", async () => {
  // Check database connectivity
  {name: "database", status: Healthy, ...}
})

// Run all checks
let report = await runAll(checker)

// Export as JSON for /health endpoint
let json = toJson(report)
```

### Health Status Levels

| Status | Meaning | HTTP Code |
|--------|---------|-----------|
| Healthy | All systems operational | 200 |
| Degraded | Some issues, still functional | 200 |
| Unhealthy | Critical failure | 503 |

### Built-in Checks

- **memory** - Memory usage monitoring
- **storage** - Storage backend connectivity
- **bridge** - Form.Bridge FFI status

## Graceful Shutdown

Coordinated shutdown with connection draining.

```rescript
// Register shutdown handlers (lower priority runs first)
onShutdown("connections", ~priority=10, async () => {
  // Stop accepting new connections
})

onShutdown("flush", ~priority=20, async () => {
  // Flush pending writes
})

onShutdown("cleanup", ~priority=30, async () => {
  // Clean up resources
})

// Initiate shutdown (e.g., on SIGTERM)
await initiateShutdown()
```

### Shutdown Phases

1. **DrainConnections** - Stop accepting new connections
2. **FlushBuffers** - Write pending data
3. **CloseResources** - Release resources
4. **Terminated** - Shutdown complete

## Production Readiness

Pre-flight checks before production deployment.

```rescript
let config: readinessConfig = {
  apiKeyRequired: true,
  corsOrigins: ["https://app.example.com"],
  tlsEnabled: true,
  connectionPoolSize: 50,
  queryCacheEnabled: true,
  healthEndpointEnabled: true,
  gracefulShutdownConfigured: true,
  metricsEnabled: true,
  tracingEnabled: true,
  loggingLevel: "info",
  environment: "production",
}

let report = runChecks(config)

if !report.ready {
  Console.error(formatReport(report))
  Process.exit(1)
}
```

### Check Categories

| Category | Checks |
|----------|--------|
| Security | API key, CORS, TLS |
| Performance | Pool size, query cache |
| Reliability | Health endpoint, graceful shutdown |
| Observability | Metrics, tracing, logging |
| Configuration | Environment setting |

### Severity Levels

| Level | Meaning |
|-------|---------|
| 1 (Critical) | Must pass for production |
| 2 (Warning) | Recommended to fix |
| 3 (Info) | Nice to have |

## Architecture

```
stability/
├── README.md
└── src/
    ├── Lith_Stability_Config.res    # Configuration
    ├── Lith_Stability_Health.res    # Health checks
    ├── Lith_Stability_Shutdown.res  # Graceful shutdown
    └── Lith_Stability_Readiness.res # Readiness checks
```

## Kubernetes Integration

### Liveness Probe

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 10
```

### Readiness Probe

```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

### Graceful Shutdown

```yaml
spec:
  terminationGracePeriodSeconds: 30
  containers:
  - name: lith
    lifecycle:
      preStop:
        httpGet:
          path: /shutdown
          port: 8080
```

## License

PMPL-1.0-or-later
