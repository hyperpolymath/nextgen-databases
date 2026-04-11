;; SPDX-License-Identifier: PMPL-1.0-or-later
;; @taxonomy: spec/core
;;
;; SPEC.core.scm — Formal specification for the NextGen Query Client (NQC).
;;
;; Defines the semantic model, type system, execution model, and protocol
;; invariants for NQC. This specification is the authoritative reference
;; for all NQC implementations (CLI REPL and Web UI).
;;
;; Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

(spec
  (name "NQC — NextGen Query Client")
  (version "0.1.0")
  (media-type "application/vnd.nqc+scm")
  (license "PMPL-1.0-or-later")
  (author "Jonathan D.A. Jewell" "j.d.a.jewell@open.ac.uk")

  ;; ========================================================================
  ;; 1. Purpose and Scope
  ;; ========================================================================

  (purpose
    "NQC is a unified query client that abstracts over multiple database"
    "backends via a common HTTP+JSON protocol. It provides interactive"
    "REPL and web interfaces for executing queries against any database"
    "that implements the NQC protocol pattern.")

  (scope
    (in-scope
      "Meta-command parsing and dispatch"
      "Database profile registry and lookup"
      "HTTP protocol for query execution and health checks"
      "Output formatting (table, JSON, CSV)"
      "CLI argument parsing"
      "Interactive database selection"
      "Session state management")
    (out-of-scope
      "Query language parsing (delegated to database backends)"
      "Query optimisation (handled by backends)"
      "Authentication and authorisation (future work)"
      "Transaction management (future work)"))

  ;; ========================================================================
  ;; 2. Type System
  ;; ========================================================================

  (types

    ;; --- Core types ---

    (type DatabaseProfile
      (doc "Everything NQC needs to know about a database backend.")
      (fields
        (id            String   (doc "Short identifier, e.g. 'vcl'. Must be unique."))
        (display-name  String   (doc "Human-readable name, e.g. 'VeriSimDB'."))
        (language-name String   (doc "Query language name, e.g. 'VCL'."))
        (description   String   (doc "Short description for menus."))
        (aliases       (List String) (doc "Alternative names for lookup."))
        (default-host  String   (doc "Default server hostname."))
        (default-port  Integer  (doc "Default server port."))
        (execute-path  String   (doc "API path for query execution."))
        (health-path   String   (doc "API path for health checks."))
        (prompt        String   (doc "REPL prompt string."))
        (supports-dt   Boolean  (doc "Whether dependent type verification is supported."))
        (keywords      (List String) (doc "Language keywords for display.")))
      (invariants
        (non-empty-id       (> (length id) 0))
        (valid-port         (and (>= default-port 1) (<= default-port 65535)))
        (path-starts-slash  (starts-with? execute-path "/"))
        (health-starts-slash (starts-with? health-path "/"))
        (non-empty-prompt   (> (length prompt) 0))
        (unique-id          "No two profiles share the same id")
        (no-alias-id-clash  "No alias matches another profile's id")))

    (type Connection
      (doc "Active connection state for a database session.")
      (fields
        (profile    DatabaseProfile (doc "The active database profile."))
        (host       String          (doc "Hostname (may override profile default)."))
        (port       Integer         (doc "Port (may override profile default)."))
        (dt-enabled Boolean         (doc "Whether dependent type verification is on.")))
      (invariants
        (valid-port (and (>= port 1) (<= port 65535)))))

    (type Session
      (doc "REPL session state — tracks connection, format, and preferences.")
      (fields
        (conn         Connection   (doc "Active database connection."))
        (format       OutputFormat (doc "Current output format."))
        (show-timing  Boolean      (doc "Whether to display query timing."))
        (should-exit  Boolean      (doc "Whether the REPL should terminate."))))

    (type OutputFormat
      (doc "Supported output formats for query results.")
      (variants
        (Table (doc "ASCII table with headers, separators, and row count."))
        (Json  (doc "Pretty-printed JSON encoding of the response."))
        (Csv   (doc "RFC 4180 compliant comma-separated values."))))

    ;; --- Error types ---

    (type ClientError
      (doc "Errors that can occur during HTTP client operations.")
      (variants
        (RequestError   String (doc "Failed to build HTTP request."))
        (TransportError String (doc "HTTP transport error (connection refused, etc)."))
        (ServerError    (status Integer) (body String)
                        (doc "Server returned non-2xx status."))
        (ParseError     String (doc "Failed to parse JSON response.")))))

  ;; ========================================================================
  ;; 3. Protocol Specification
  ;; ========================================================================

  (protocol

    (name "NQC Query Protocol")
    (transport "HTTP/1.1")
    (encoding "JSON (UTF-8)")

    ;; --- Query execution ---

    (operation execute
      (doc "Execute a query against the active database.")
      (request
        (method "POST")
        (url    (concat (base-url connection) (execute-path profile)))
        (headers
          ("Content-Type" "application/json")
          ("Accept"       "application/json"))
        (body (json-object ("query" query-text))))
      (response
        (success (status 200..299) (body json-value))
        (error   (status 400..599) (body error-message)))
      (invariants
        (query-non-empty "Query text must not be empty after stripping.")
        (trailing-semicolons-stripped
          "All trailing semicolons are removed before transmission.")))

    ;; --- Health check ---

    (operation health
      (doc "Check server health status.")
      (request
        (method "GET")
        (url    (concat (base-url connection) (health-path profile)))
        (headers ("Accept" "application/json")))
      (response
        (success (status 200..299) (body json-value))
        (error   (status 400..599) (body error-message))))

    ;; --- URL construction ---

    (function base-url
      (doc "Build the base URL from a connection.")
      (signature (-> Connection String))
      (definition (concat "http://" host ":" (to-string port))))

    (function execute-url
      (doc "Build the full execute URL.")
      (signature (-> Connection String))
      (definition (concat (base-url conn) (execute-path (profile conn)))))

    (function health-url
      (doc "Build the full health URL.")
      (signature (-> Connection String))
      (definition (concat (base-url conn) (health-path (profile conn))))))

  ;; ========================================================================
  ;; 4. Profile Registry
  ;; ========================================================================

  (registry

    (doc "The profile registry maps identifiers and aliases to database"
         "profiles. Lookup is case-insensitive.")

    ;; --- Built-in profiles ---

    (builtin-profiles
      (profile vcl
        (display-name "VeriSimDB")
        (language-name "VCL")
        (description "6-core multimodal database with self-normalization")
        (aliases "verisimdb" "verisim")
        (default-port 8080)
        (execute-path "/vcl/execute")
        (supports-dt #t))

      (profile gql
        (display-name "Lithoglyph")
        (language-name "GQL")
        (description "Graph database with formal verification")
        (aliases "lithoglyph" "formdb")
        (default-port 8081)
        (execute-path "/gql/execute")
        (supports-dt #t))

      (profile kql
        (display-name "QuandleDB")
        (language-name "KQL")
        (description "Knot-theoretic structural equivalence database")
        (aliases "quandledb" "quandle")
        (default-port 8082)
        (execute-path "/kql/execute")
        (supports-dt #t)))

    ;; --- Lookup semantics ---

    (function find-profile
      (doc "Find a profile by ID or alias. Case-insensitive.")
      (signature (-> String (Result DatabaseProfile String)))
      (algorithm
        (let ((needle (lowercase input)))
          (or (find-by-id needle all-profiles)
              (find-by-alias needle all-profiles)
              (error (format "Unknown database: '~a'. Available: ~a."
                             input (join ", " (map id all-profiles))))))))

    ;; --- Registry invariants ---

    (invariants
      (unique-ids
        "All profile IDs are distinct.")
      (no-alias-id-overlap
        "No alias of profile A matches the ID of profile B.")
      (unique-aliases
        "No alias appears in more than one profile.")
      (order-preserved
        "Built-in profiles always appear before custom profiles.")
      (builtins-immutable
        "Built-in profiles cannot be modified at runtime.")))

  ;; ========================================================================
  ;; 5. Output Formatting
  ;; ========================================================================

  (formatting

    ;; --- Format selection ---

    (function parse-format
      (doc "Parse an output format from a string. Case-insensitive.")
      (signature (-> String (Result OutputFormat String)))
      (cases
        ("table" -> (Ok Table))
        ("json"  -> (Ok Json))
        ("csv"   -> (Ok Csv))
        (other   -> (Error (format "Unknown format: '~a'. Use table, json, or csv." other)))))

    ;; --- Table formatting ---

    (format table
      (doc "ASCII table with auto-detected columns.")
      (algorithm
        (step 1 "Extract 'data' field if present (VCL response shape),"
                "otherwise use raw value.")
        (step 2 "Coerce to list. If not a list, format as single object"
                "or fall back to JSON.")
        (step 3 "Extract column names from keys of first item.")
        (step 4 "Build header row: column names joined by ' | '.")
        (step 5 "Build separator: dashes per column width, joined by '+'.")
        (step 6 "Build data rows: field values joined by ' | '.")
        (step 7 "Append row count: '(N rows)'.")))

    ;; --- JSON formatting ---

    (format json
      (doc "Pretty-printed JSON encoding of the raw response value.")
      (algorithm
        (step 1 "Encode the dynamic value as a JSON string.")
        (step 2 "Return the encoded string verbatim.")))

    ;; --- CSV formatting ---

    (format csv
      (doc "RFC 4180 compliant CSV output.")
      (algorithm
        (step 1 "Extract 'data' field if present, otherwise use raw value.")
        (step 2 "Coerce to list. If empty, return empty string.")
        (step 3 "Extract column names from keys of first item.")
        (step 4 "Output header row: column names joined by ','.")
        (step 5 "Output data rows: field values escaped per RFC 4180."))
      (escaping
        (rule "Fields containing commas, double quotes, or newlines"
              "must be enclosed in double quotes.")
        (rule "Double quotes within fields are escaped by doubling: '\"\"'."))))

  ;; ========================================================================
  ;; 6. Meta-Command Semantics
  ;; ========================================================================

  (meta-commands

    (doc "Meta-commands control the REPL session. They are prefixed with '\\'."
         "Any input not starting with '\\' is treated as a query.")

    (command quit
      (aliases "\\quit" "\\q")
      (doc "Exit the REPL.")
      (effect (set should-exit #t)))

    (command help
      (aliases "\\help" "\\h" "\\?")
      (doc "Display available commands and usage.")
      (effect (print help-text)))

    (command connect
      (aliases "\\connect")
      (doc "Change server connection.")
      (argument "<host:port>" "optional")
      (effect
        (if (empty? argument)
          (print current-connection-info)
          (parse-and-update-connection argument))))

    (command db
      (aliases "\\db")
      (doc "Switch database backend.")
      (argument "<id>" "optional")
      (effect
        (if (empty? argument)
          (print current-database-info)
          (switch-to-profile argument)))
      (preserves host dt-enabled)
      (doc "Host and DT settings are preserved across database switches."))

    (command databases
      (aliases "\\databases" "\\dbs")
      (doc "List all available database profiles.")
      (effect (print profile-list)))

    (command dt
      (aliases "\\dt")
      (doc "Toggle dependent type verification.")
      (precondition (supports-dt (profile connection)))
      (effect (toggle dt-enabled)))

    (command format
      (aliases "\\format")
      (doc "Change output format.")
      (argument "<table|json|csv>" "optional")
      (effect
        (if (empty? argument)
          (print current-format)
          (set-format (parse-format argument)))))

    (command timing
      (aliases "\\timing")
      (doc "Toggle query timing display.")
      (effect (toggle show-timing)))

    (command status
      (aliases "\\status")
      (doc "Check server health.")
      (effect (execute-health-check-and-display)))

    (command keywords
      (aliases "\\keywords")
      (doc "List keywords for the active database's query language.")
      (effect (print keyword-list))))

  ;; ========================================================================
  ;; 7. CLI Argument Semantics
  ;; ========================================================================

  (cli

    (doc "NQC accepts command-line arguments for non-interactive startup.")

    (argument --db
      (type database-id)
      (required #f)
      (doc "Database backend to connect to. If omitted, interactive selector."))

    (argument --host
      (type hostname)
      (required #f)
      (doc "Override server hostname."))

    (argument --port
      (type integer)
      (required #f)
      (doc "Override server port."))

    (argument --format
      (type output-format)
      (required #f)
      (default "table")
      (doc "Initial output format."))

    (argument --dt
      (type flag)
      (required #f)
      (doc "Enable dependent type verification."))

    (argument --help
      (aliases "-h")
      (doc "Print usage and exit."))

    (startup-logic
      (case no-arguments   -> interactive-selector)
      (case --help          -> print-usage-and-exit)
      (case --db-provided   -> connect-and-start-repl)
      (case other           -> error-missing-db-flag)))

  ;; ========================================================================
  ;; 8. Session Lifecycle
  ;; ========================================================================

  (lifecycle

    (phase startup
      (step 1 "Parse CLI arguments.")
      (step 2 "Resolve database profile.")
      (step 3 "Apply host/port/format/dt overrides.")
      (step 4 "Print welcome banner.")
      (step 5 "Enter REPL loop."))

    (phase repl-loop
      (step 1 "Display prompt.")
      (step 2 "Read line from stdin.")
      (step 3 "If EOF, print goodbye and exit.")
      (step 4 "Trim whitespace.")
      (step 5 "If empty, continue loop.")
      (step 6 "If starts with '\\', dispatch to meta-command handler.")
      (step 7 "Otherwise, strip trailing semicolons and execute as query.")
      (step 8 "Display result in current format.")
      (step 9 "If timing enabled, display elapsed time.")
      (step 10 "Continue loop unless should-exit is set."))

    (phase shutdown
      (step 1 "Print 'Goodbye.'")
      (step 2 "Exit process.")))

  ;; ========================================================================
  ;; 9. Invariants and Guarantees
  ;; ========================================================================

  (invariants

    (safety
      (no-crash-on-any-input
        "NQC must not crash on any user input. All errors are caught"
        "and displayed as error messages.")
      (no-data-loss
        "NQC never modifies query text beyond stripping trailing semicolons.")
      (graceful-disconnect
        "Connection failures produce clear error messages, not crashes."))

    (correctness
      (format-roundtrip
        "parse-format(format-to-string(f)) == Ok(f) for all OutputFormat values.")
      (profile-lookup-consistent
        "find-profile(p.id) == Ok(p) for every registered profile p.")
      (alias-lookup-consistent
        "find-profile(alias) == Ok(p) for every alias of profile p.")
      (url-construction
        "execute-url(conn) == base-url(conn) ++ conn.profile.execute-path")
      (semicolon-stripping-idempotent
        "strip(strip(s)) == strip(s) for all strings s."))

    (protocol
      (json-content-type
        "All POST requests set Content-Type: application/json.")
      (accept-json
        "All requests set Accept: application/json.")
      (query-field-name
        "The JSON body field for queries is always 'query'.")
      (status-code-handling
        "2xx responses are parsed as success. All others are errors."))))
