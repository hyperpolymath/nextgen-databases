// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Configuration Validation
 *
 * Type-safe configuration with validation and defaults
 */

/** Environment type */
type environment =
  | Development
  | Staging
  | Production

/** Log level */
type logLevel =
  | Debug
  | Info
  | Warn
  | Error

/** Storage backend type */
type storageBackend =
  | Memory
  | File(string)
  | Bridge(string)

/** Configuration schema */
type config = {
  environment: environment,
  logLevel: logLevel,
  storage: storageBackend,
  httpPort: int,
  grpcPort: int,
  maxConnections: int,
  queryTimeout: float,
  enableMetrics: bool,
  enableTracing: bool,
  corsOrigins: array<string>,
  apiKeyRequired: bool,
}

/** Validation error */
type validationError = {
  field: string,
  message: string,
}

/** Validation result */
type validationResult =
  | Valid(config)
  | Invalid(array<validationError>)

/** Default configuration */
let defaultConfig: config = {
  environment: Development,
  logLevel: Info,
  storage: Memory,
  httpPort: 8080,
  grpcPort: 9090,
  maxConnections: 100,
  queryTimeout: 30000.0,
  enableMetrics: true,
  enableTracing: false,
  corsOrigins: ["*"],
  apiKeyRequired: false,
}

/** Parse environment string */
let parseEnvironment = (s: string): option<environment> => {
  switch String.toLowerCase(s) {
  | "development" | "dev" => Some(Development)
  | "staging" | "stage" => Some(Staging)
  | "production" | "prod" => Some(Production)
  | _ => None
  }
}

/** Parse log level string */
let parseLogLevel = (s: string): option<logLevel> => {
  switch String.toLowerCase(s) {
  | "debug" => Some(Debug)
  | "info" => Some(Info)
  | "warn" | "warning" => Some(Warn)
  | "error" => Some(Error)
  | _ => None
  }
}

/** Get environment variable with default */
let getEnvOr = (key: string, default: string): string => {
  // In production, would use Deno.env.get
  default
}

/** Validate port number */
let validatePort = (port: int, field: string): array<validationError> => {
  if port < 1 || port > 65535 {
    [{field, message: `Port must be between 1 and 65535, got ${Int.toString(port)}`}]
  } else {
    []
  }
}

/** Validate positive number */
let validatePositive = (n: int, field: string): array<validationError> => {
  if n < 1 {
    [{field, message: `${field} must be positive, got ${Int.toString(n)}`}]
  } else {
    []
  }
}

/** Validate configuration */
let validate = (cfg: config): validationResult => {
  let errors: array<validationError> = []

  // Validate ports
  errors->Array.pushMany(validatePort(cfg.httpPort, "httpPort"))
  errors->Array.pushMany(validatePort(cfg.grpcPort, "grpcPort"))

  // Validate connections
  errors->Array.pushMany(validatePositive(cfg.maxConnections, "maxConnections"))

  // Validate timeout
  if cfg.queryTimeout < 0.0 {
    errors->Array.push({field: "queryTimeout", message: "Query timeout must be non-negative"})->ignore
  }

  // Production-specific validations
  if cfg.environment == Production {
    if cfg.apiKeyRequired == false {
      errors->Array.push({field: "apiKeyRequired", message: "API key required in production"})->ignore
    }
    if cfg.corsOrigins->Array.includes("*") {
      errors->Array.push({field: "corsOrigins", message: "Wildcard CORS not allowed in production"})->ignore
    }
  }

  if Array.length(errors) == 0 {
    Valid(cfg)
  } else {
    Invalid(errors)
  }
}

/** Load configuration from environment */
let loadFromEnv = (): config => {
  let env = getEnvOr("LITH_ENV", "development")
  let logLvl = getEnvOr("LITH_LOG_LEVEL", "info")

  {
    environment: parseEnvironment(env)->Option.getOr(Development),
    logLevel: parseLogLevel(logLvl)->Option.getOr(Info),
    storage: Memory,
    httpPort: 8080,
    grpcPort: 9090,
    maxConnections: 100,
    queryTimeout: 30000.0,
    enableMetrics: true,
    enableTracing: false,
    corsOrigins: ["*"],
    apiKeyRequired: false,
  }
}

/** Format validation errors */
let formatErrors = (errors: array<validationError>): string => {
  errors
  ->Array.map(e => `  - ${e.field}: ${e.message}`)
  ->Array.join("\n")
}
