// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
//! Role-Based Access Control (RBAC) for VeriSimDB API.
//!
//! Provides fine-grained permission checking beyond the basic [`ClientRole`]
//! authentication layer. Supports:
//!
//! - **Global permissions**: Apply to all resources (e.g., Admin can do everything).
//! - **Per-modality permissions**: Grant read/write/execute per VeriSimDB modality
//!   (graph, vector, tensor, semantic, document, temporal).
//! - **Entity-level ACLs**: Override permissions for specific hexad entities.
//! - **Audit logging**: Every access decision is recorded with timestamps.
//!
//! # Integration with auth middleware
//!
//! After the [`auth_middleware`](crate::auth::auth_middleware) extracts a
//! [`ClientIdentity`](crate::auth::ClientIdentity), call
//! [`check_authorization`] to verify that the client's role permits the
//! requested operation on the target resource.

use crate::auth::{ClientIdentity, ClientRole};
use axum::http::{Method, StatusCode};
use axum::response::IntoResponse;
use axum::Json;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::SystemTime;
use tracing::{info, warn};

// ---------------------------------------------------------------------------
// Permission types
// ---------------------------------------------------------------------------

/// Individual permission that can be granted to a role or entity ACL.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Permission {
    /// Read data (GET requests, search, list).
    Read,
    /// Write data (POST, PUT, DELETE on hexads and related resources).
    Write,
    /// Administrative operations (config changes, normalizer triggers, key management).
    Admin,
    /// Execute queries (VQL execution, query planning, EXPLAIN).
    Execute,
}

impl std::fmt::Display for Permission {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Permission::Read => write!(f, "read"),
            Permission::Write => write!(f, "write"),
            Permission::Admin => write!(f, "admin"),
            Permission::Execute => write!(f, "execute"),
        }
    }
}

/// Permissions scoped to a specific VeriSimDB modality.
///
/// For example, a role might have `Read` + `Execute` on the `vector` modality
/// but only `Read` on `graph`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModalityPermission {
    /// The modality name (e.g., "graph", "vector", "tensor", "semantic",
    /// "document", "temporal").
    pub modality: String,
    /// Permissions granted for this modality.
    pub permissions: Vec<Permission>,
}

// ---------------------------------------------------------------------------
// Role definitions
// ---------------------------------------------------------------------------

/// A named role definition with global and per-modality permissions.
///
/// Roles are composable: a client's effective permissions are the union of
/// global permissions and any modality-specific grants.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoleDefinition {
    /// Human-readable role name (e.g., "reader", "writer", "admin",
    /// "vector-analyst").
    pub name: String,
    /// Permissions that apply to every modality and every resource.
    pub global_permissions: Vec<Permission>,
    /// Per-modality permission overrides. Key is the modality name.
    pub modality_permissions: HashMap<String, Vec<Permission>>,
}

impl RoleDefinition {
    /// Check whether this role grants a specific permission globally.
    pub fn has_global_permission(&self, permission: Permission) -> bool {
        self.global_permissions.contains(&permission)
    }

    /// Check whether this role grants a specific permission for a modality.
    ///
    /// Returns `true` if the permission is granted either globally or
    /// specifically for the named modality.
    pub fn has_modality_permission(&self, modality: &str, permission: Permission) -> bool {
        if self.has_global_permission(permission) {
            return true;
        }
        self.modality_permissions
            .get(modality)
            .map(|perms| perms.contains(&permission))
            .unwrap_or(false)
    }
}

// ---------------------------------------------------------------------------
// RBAC policy
// ---------------------------------------------------------------------------

/// The complete RBAC policy for the VeriSimDB instance.
///
/// Contains all role definitions and entity-level ACL overrides.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RbacPolicy {
    /// Named role definitions. Key is the role name (lowercase).
    pub roles: HashMap<String, RoleDefinition>,
    /// Entity-level ACL overrides. Outer key is the entity (hexad) ID,
    /// inner tuples are `(client_id, Vec<Permission>)` pairs.
    pub entity_acls: HashMap<String, Vec<(String, Vec<Permission>)>>,
}

impl Default for RbacPolicy {
    /// Construct the default policy with built-in reader/writer/admin roles.
    fn default() -> Self {
        let mut roles = HashMap::new();

        // Reader: read + execute globally.
        roles.insert(
            "reader".to_string(),
            RoleDefinition {
                name: "reader".to_string(),
                global_permissions: vec![Permission::Read, Permission::Execute],
                modality_permissions: HashMap::new(),
            },
        );

        // Writer: read + write + execute globally.
        roles.insert(
            "writer".to_string(),
            RoleDefinition {
                name: "writer".to_string(),
                global_permissions: vec![Permission::Read, Permission::Write, Permission::Execute],
                modality_permissions: HashMap::new(),
            },
        );

        // Admin: every permission globally.
        roles.insert(
            "admin".to_string(),
            RoleDefinition {
                name: "admin".to_string(),
                global_permissions: vec![
                    Permission::Read,
                    Permission::Write,
                    Permission::Admin,
                    Permission::Execute,
                ],
                modality_permissions: HashMap::new(),
            },
        );

        Self {
            roles,
            entity_acls: HashMap::new(),
        }
    }
}

impl RbacPolicy {
    /// Create a new empty policy (no roles, no ACLs).
    pub fn new() -> Self {
        Self {
            roles: HashMap::new(),
            entity_acls: HashMap::new(),
        }
    }

    /// Look up the [`RoleDefinition`] for a [`ClientRole`].
    pub fn role_for(&self, client_role: ClientRole) -> Option<&RoleDefinition> {
        let key = match client_role {
            ClientRole::Reader => "reader",
            ClientRole::Writer => "writer",
            ClientRole::Admin => "admin",
        };
        self.roles.get(key)
    }

    /// Register or replace a custom role definition.
    pub fn set_role(&mut self, role: RoleDefinition) {
        self.roles.insert(role.name.clone(), role);
    }

    /// Add an entity-level ACL entry granting `permissions` to `client_id`
    /// on `entity_id`.
    pub fn add_entity_acl(
        &mut self,
        entity_id: &str,
        client_id: &str,
        permissions: Vec<Permission>,
    ) {
        self.entity_acls
            .entry(entity_id.to_string())
            .or_default()
            .push((client_id.to_string(), permissions));
    }

    /// Check whether `client_id` has `permission` on `entity_id` via an
    /// entity-level ACL entry.
    pub fn check_entity_acl(
        &self,
        entity_id: &str,
        client_id: &str,
        permission: Permission,
    ) -> bool {
        self.entity_acls
            .get(entity_id)
            .map(|acls| {
                acls.iter().any(|(cid, perms)| {
                    cid == client_id && perms.contains(&permission)
                })
            })
            .unwrap_or(false)
    }
}

// ---------------------------------------------------------------------------
// Audit log
// ---------------------------------------------------------------------------

/// Outcome of an authorization decision.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AccessDecision {
    /// Access was permitted.
    Allowed,
    /// Access was denied.
    Denied,
}

impl std::fmt::Display for AccessDecision {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AccessDecision::Allowed => write!(f, "ALLOWED"),
            AccessDecision::Denied => write!(f, "DENIED"),
        }
    }
}

/// A single entry in the authorization audit log.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditEntry {
    /// Timestamp of the decision (seconds since UNIX epoch).
    pub timestamp: u64,
    /// Client identifier (API key hash or JWT subject).
    pub client_id: String,
    /// Role of the client at the time of the decision.
    pub client_role: String,
    /// The resource path that was accessed.
    pub resource_path: String,
    /// The HTTP method used.
    pub method: String,
    /// The permission that was required.
    pub required_permission: Permission,
    /// The decision outcome.
    pub decision: AccessDecision,
    /// Optional reason string for denials.
    pub reason: Option<String>,
}

/// Thread-safe audit log that records all authorization decisions.
#[derive(Debug, Clone)]
pub struct AuditLog {
    entries: Arc<Mutex<Vec<AuditEntry>>>,
    /// Maximum number of entries retained (ring buffer behaviour).
    max_entries: usize,
}

impl AuditLog {
    /// Create a new audit log with the given capacity.
    pub fn new(max_entries: usize) -> Self {
        Self {
            entries: Arc::new(Mutex::new(Vec::with_capacity(max_entries.min(4096)))),
            max_entries,
        }
    }

    /// Record an authorization decision.
    pub fn record(&self, entry: AuditEntry) {
        let mut entries = self.entries.lock().expect("audit log lock");
        if entries.len() >= self.max_entries {
            // Drop the oldest entry to stay within capacity.
            entries.remove(0);
        }
        entries.push(entry);
    }

    /// Retrieve a snapshot of all recorded entries.
    pub fn entries(&self) -> Vec<AuditEntry> {
        let entries = self.entries.lock().expect("audit log lock");
        entries.clone()
    }

    /// Return the number of recorded entries.
    pub fn len(&self) -> usize {
        let entries = self.entries.lock().expect("audit log lock");
        entries.len()
    }

    /// Check if the audit log is empty.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Clear all entries.
    pub fn clear(&self) {
        let mut entries = self.entries.lock().expect("audit log lock");
        entries.clear();
    }
}

impl Default for AuditLog {
    fn default() -> Self {
        Self::new(10_000)
    }
}

// ---------------------------------------------------------------------------
// RBAC state (shared across the application)
// ---------------------------------------------------------------------------

/// Shared RBAC state that is attached to the Axum application state.
#[derive(Debug, Clone)]
pub struct RbacState {
    /// The active RBAC policy.
    pub policy: Arc<Mutex<RbacPolicy>>,
    /// Authorization audit log.
    pub audit_log: AuditLog,
}

impl RbacState {
    /// Create RBAC state from a policy.
    pub fn new(policy: RbacPolicy) -> Self {
        Self {
            policy: Arc::new(Mutex::new(policy)),
            audit_log: AuditLog::default(),
        }
    }
}

impl Default for RbacState {
    fn default() -> Self {
        Self::new(RbacPolicy::default())
    }
}

// ---------------------------------------------------------------------------
// Authorization error
// ---------------------------------------------------------------------------

/// Error returned when an authorization check fails.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthzError {
    /// Human-readable error message.
    pub error: String,
    /// HTTP status code (always 403 for authorization failures).
    pub code: u16,
    /// The permission that was required but not granted.
    pub required_permission: String,
}

impl IntoResponse for AuthzError {
    fn into_response(self) -> axum::response::Response {
        (StatusCode::FORBIDDEN, Json(self)).into_response()
    }
}

// ---------------------------------------------------------------------------
// Permission derivation from HTTP method + path
// ---------------------------------------------------------------------------

/// Derive the required [`Permission`] from an HTTP method and resource path.
///
/// The mapping follows REST conventions:
/// - `GET` / `HEAD` / `OPTIONS` -> [`Permission::Read`]
/// - `POST` to query/plan/explain endpoints -> [`Permission::Execute`]
/// - `POST` / `PUT` / `PATCH` / `DELETE` -> [`Permission::Write`]
/// - Admin endpoints (`/normalizer/trigger`, `/planner/config` PUT) ->
///   [`Permission::Admin`]
pub fn required_permission(method: &Method, path: &str) -> Permission {
    // Admin endpoints (explicitly listed).
    if is_admin_path(method, path) {
        return Permission::Admin;
    }

    // Query execution endpoints.
    if is_execute_path(method, path) {
        return Permission::Execute;
    }

    // Read-only methods.
    if matches!(*method, Method::GET | Method::HEAD | Method::OPTIONS) {
        return Permission::Read;
    }

    // All other mutating methods.
    Permission::Write
}

/// Check if a (method, path) combination targets an admin-only resource.
fn is_admin_path(method: &Method, path: &str) -> bool {
    // Normalizer trigger is admin-only.
    if path.starts_with("/normalizer/trigger") && *method == Method::POST {
        return true;
    }
    // Planner config mutation is admin-only.
    if path.starts_with("/planner/config") && *method == Method::PUT {
        return true;
    }
    false
}

/// Check if a (method, path) combination targets a query execution resource.
fn is_execute_path(method: &Method, path: &str) -> bool {
    if *method != Method::POST {
        return false;
    }
    path.starts_with("/query/plan")
        || path.starts_with("/query/explain")
        || path.starts_with("/queries/similar")
        || path.starts_with("/search/")
}

/// Extract the modality name from a resource path, if applicable.
///
/// Returns `None` when the path does not target a specific modality.
/// For hexad-level paths we return `None` because hexads span all modalities.
pub fn modality_from_path(path: &str) -> Option<&str> {
    if path.starts_with("/search/vector") {
        return Some("vector");
    }
    if path.starts_with("/search/text") {
        return Some("document");
    }
    if path.starts_with("/search/related") {
        return Some("graph");
    }
    if path.starts_with("/drift") {
        return Some("temporal");
    }
    None
}

/// Extract the entity (hexad) ID from a resource path, if applicable.
pub fn entity_from_path(path: &str) -> Option<&str> {
    // Matches /hexads/{id} and sub-paths.
    if let Some(rest) = path.strip_prefix("/hexads/") {
        let id = rest.split('/').next().unwrap_or(rest);
        if !id.is_empty() {
            return Some(id);
        }
    }
    // Matches /drift/entity/{id}.
    if let Some(rest) = path.strip_prefix("/drift/entity/") {
        let id = rest.split('/').next().unwrap_or(rest);
        if !id.is_empty() {
            return Some(id);
        }
    }
    // Matches /normalizer/trigger/{id}.
    if let Some(rest) = path.strip_prefix("/normalizer/trigger/") {
        let id = rest.split('/').next().unwrap_or(rest);
        if !id.is_empty() {
            return Some(id);
        }
    }
    None
}

// ---------------------------------------------------------------------------
// Core authorization check
// ---------------------------------------------------------------------------

/// Check whether a client is authorized to access a resource.
///
/// This is the primary entry point for RBAC enforcement. It:
///
/// 1. Determines the required [`Permission`] from the HTTP method and path.
/// 2. Looks up the client's [`RoleDefinition`] in the active policy.
/// 3. Checks entity-level ACLs (which can grant access that the role alone
///    would not).
/// 4. Checks modality-specific permissions when the path targets a specific
///    modality.
/// 5. Falls back to global role permissions.
/// 6. Records the decision in the audit log.
///
/// Returns `Ok(())` when access is granted, or `Err(AuthzError)` when denied.
pub fn check_access(
    identity: &ClientIdentity,
    resource_path: &str,
    method: &Method,
    rbac: &RbacState,
) -> Result<(), AuthzError> {
    let permission = required_permission(method, resource_path);
    let policy = rbac.policy.lock().expect("rbac policy lock");

    let now_secs = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    let role_name = match identity.role {
        ClientRole::Reader => "reader",
        ClientRole::Writer => "writer",
        ClientRole::Admin => "admin",
    };

    // Helper to record + return a decision.
    let record = |decision: AccessDecision, reason: Option<String>| {
        let entry = AuditEntry {
            timestamp: now_secs,
            client_id: identity.id.clone(),
            client_role: role_name.to_string(),
            resource_path: resource_path.to_string(),
            method: method.to_string(),
            required_permission: permission,
            decision,
            reason: reason.clone(),
        };
        rbac.audit_log.record(entry);
    };

    // --- 1. Entity-level ACL check (overrides role) ---
    if let Some(entity_id) = entity_from_path(resource_path) {
        if policy.check_entity_acl(entity_id, &identity.id, permission) {
            info!(
                client = %identity.id,
                role = %role_name,
                path = %resource_path,
                permission = %permission,
                "Access ALLOWED via entity ACL"
            );
            record(AccessDecision::Allowed, Some("entity ACL grant".to_string()));
            return Ok(());
        }
    }

    // --- 2. Look up role definition ---
    let role_def = match policy.role_for(identity.role) {
        Some(rd) => rd,
        None => {
            let reason = format!("No role definition found for '{}'", role_name);
            warn!(
                client = %identity.id,
                role = %role_name,
                path = %resource_path,
                "Access DENIED: {}", reason
            );
            record(AccessDecision::Denied, Some(reason.clone()));
            return Err(AuthzError {
                error: reason,
                code: 403,
                required_permission: permission.to_string(),
            });
        }
    };

    // --- 3. Modality-specific check ---
    if let Some(modality) = modality_from_path(resource_path) {
        if role_def.has_modality_permission(modality, permission) {
            info!(
                client = %identity.id,
                role = %role_name,
                path = %resource_path,
                modality = %modality,
                permission = %permission,
                "Access ALLOWED via modality permission"
            );
            record(AccessDecision::Allowed, Some(format!("modality '{}' grant", modality)));
            return Ok(());
        }
        // If the role has a modality_permissions entry for this modality
        // but the specific permission is missing, deny rather than falling
        // through to global (explicit modality config is restrictive).
        if role_def.modality_permissions.contains_key(modality) {
            let reason = format!(
                "Role '{}' lacks '{}' permission on modality '{}'",
                role_name, permission, modality
            );
            warn!(
                client = %identity.id,
                role = %role_name,
                path = %resource_path,
                "Access DENIED: {}", reason
            );
            record(AccessDecision::Denied, Some(reason.clone()));
            return Err(AuthzError {
                error: reason,
                code: 403,
                required_permission: permission.to_string(),
            });
        }
    }

    // --- 4. Global permission check ---
    if role_def.has_global_permission(permission) {
        info!(
            client = %identity.id,
            role = %role_name,
            path = %resource_path,
            permission = %permission,
            "Access ALLOWED via global permission"
        );
        record(AccessDecision::Allowed, Some("global role grant".to_string()));
        return Ok(());
    }

    // --- 5. Denied ---
    let reason = format!(
        "Role '{}' does not have '{}' permission",
        role_name, permission
    );
    warn!(
        client = %identity.id,
        role = %role_name,
        path = %resource_path,
        "Access DENIED: {}", reason
    );
    record(AccessDecision::Denied, Some(reason.clone()));
    Err(AuthzError {
        error: reason,
        code: 403,
        required_permission: permission.to_string(),
    })
}

/// Convenience wrapper intended for use by the authentication middleware.
///
/// After [`extract_identity`](crate::auth) succeeds, the middleware calls
/// this function to perform authorization. If the check fails, the returned
/// error is directly convertible to an Axum response via [`IntoResponse`].
pub fn check_authorization(
    identity: &ClientIdentity,
    resource_path: &str,
    method: &Method,
    rbac: &RbacState,
) -> Result<(), AuthzError> {
    check_access(identity, resource_path, method, rbac)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::auth::{ClientIdentity, ClientRole};

    /// Helper: build an [`RbacState`] with the default policy.
    fn default_rbac() -> RbacState {
        RbacState::default()
    }

    /// Helper: build a [`ClientIdentity`] with the given role.
    fn identity(id: &str, role: ClientRole) -> ClientIdentity {
        ClientIdentity {
            id: id.to_string(),
            role,
        }
    }

    // ------------------------------------------------------------------
    // Test 1: Admin has all permissions
    // ------------------------------------------------------------------
    #[test]
    fn test_admin_has_all_permissions() {
        let rbac = default_rbac();
        let admin = identity("admin-user", ClientRole::Admin);

        // Read
        assert!(check_access(&admin, "/hexads", &Method::GET, &rbac).is_ok());
        // Write
        assert!(check_access(&admin, "/hexads", &Method::POST, &rbac).is_ok());
        // Execute
        assert!(check_access(&admin, "/query/plan", &Method::POST, &rbac).is_ok());
        // Admin
        assert!(check_access(
            &admin,
            "/normalizer/trigger/entity-1",
            &Method::POST,
            &rbac
        ).is_ok());
        assert!(check_access(
            &admin,
            "/planner/config",
            &Method::PUT,
            &rbac
        ).is_ok());
    }

    // ------------------------------------------------------------------
    // Test 2: Reader denied write access
    // ------------------------------------------------------------------
    #[test]
    fn test_reader_denied_write_access() {
        let rbac = default_rbac();
        let reader = identity("reader-user", ClientRole::Reader);

        // Write should be denied.
        let result = check_access(&reader, "/hexads", &Method::POST, &rbac);
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert_eq!(err.code, 403);
        assert_eq!(err.required_permission, "write");

        // PUT should be denied.
        let result = check_access(&reader, "/hexads/some-id", &Method::PUT, &rbac);
        assert!(result.is_err());

        // DELETE should be denied.
        let result = check_access(&reader, "/hexads/some-id", &Method::DELETE, &rbac);
        assert!(result.is_err());
    }

    // ------------------------------------------------------------------
    // Test 3: Reader allowed read and execute
    // ------------------------------------------------------------------
    #[test]
    fn test_reader_allowed_read_and_execute() {
        let rbac = default_rbac();
        let reader = identity("reader-user", ClientRole::Reader);

        // Read is allowed.
        assert!(check_access(&reader, "/hexads", &Method::GET, &rbac).is_ok());
        assert!(check_access(&reader, "/hexads/abc", &Method::GET, &rbac).is_ok());
        assert!(check_access(&reader, "/drift/status", &Method::GET, &rbac).is_ok());

        // Execute is allowed (query endpoints).
        assert!(check_access(&reader, "/query/plan", &Method::POST, &rbac).is_ok());
        assert!(check_access(&reader, "/query/explain", &Method::POST, &rbac).is_ok());
        assert!(check_access(&reader, "/search/vector", &Method::POST, &rbac).is_ok());
    }

    // ------------------------------------------------------------------
    // Test 4: Writer allowed write, denied admin
    // ------------------------------------------------------------------
    #[test]
    fn test_writer_allowed_write_denied_admin() {
        let rbac = default_rbac();
        let writer = identity("writer-user", ClientRole::Writer);

        // Write is allowed.
        assert!(check_access(&writer, "/hexads", &Method::POST, &rbac).is_ok());
        assert!(check_access(&writer, "/hexads/abc", &Method::PUT, &rbac).is_ok());
        assert!(check_access(&writer, "/hexads/abc", &Method::DELETE, &rbac).is_ok());

        // Read and execute also allowed.
        assert!(check_access(&writer, "/hexads", &Method::GET, &rbac).is_ok());
        assert!(check_access(&writer, "/query/plan", &Method::POST, &rbac).is_ok());

        // Admin is denied.
        let result = check_access(
            &writer,
            "/normalizer/trigger/entity-1",
            &Method::POST,
            &rbac,
        );
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert_eq!(err.required_permission, "admin");

        let result = check_access(&writer, "/planner/config", &Method::PUT, &rbac);
        assert!(result.is_err());
    }

    // ------------------------------------------------------------------
    // Test 5: Per-modality permissions work
    // ------------------------------------------------------------------
    #[test]
    fn test_per_modality_permissions() {
        let mut policy = RbacPolicy::new();

        // Create a custom role that can only read vectors and write documents.
        let mut modality_perms = HashMap::new();
        modality_perms.insert(
            "vector".to_string(),
            vec![Permission::Read, Permission::Execute],
        );
        modality_perms.insert(
            "document".to_string(),
            vec![Permission::Read, Permission::Write],
        );
        // Explicitly empty graph permissions — should deny graph access.
        modality_perms.insert("graph".to_string(), vec![Permission::Read]);

        policy.set_role(RoleDefinition {
            name: "reader".to_string(),
            global_permissions: vec![], // No global perms — all modality-specific.
            modality_permissions: modality_perms,
        });

        let rbac = RbacState::new(policy);
        let user = identity("modal-user", ClientRole::Reader);

        // Vector search (Execute on vector) → allowed.
        assert!(check_access(&user, "/search/vector", &Method::POST, &rbac).is_ok());

        // Text search (requires execute on document modality) → denied
        // because document modality only has Read and Write.
        let result = check_access(&user, "/search/text", &Method::POST, &rbac);
        assert!(result.is_err());

        // Graph related search (requires execute on graph modality) → denied
        // because graph modality only has Read.
        let result = check_access(&user, "/search/related/xyz", &Method::POST, &rbac);
        assert!(result.is_err());
    }

    // ------------------------------------------------------------------
    // Test 6: Entity-level ACLs work
    // ------------------------------------------------------------------
    #[test]
    fn test_entity_level_acls() {
        let mut policy = RbacPolicy::default();

        // Grant the reader "writer-user" write access to a specific entity.
        policy.add_entity_acl("secret-hexad", "special-reader", vec![Permission::Write]);

        let rbac = RbacState::new(policy);
        let reader = identity("special-reader", ClientRole::Reader);

        // Normally a reader cannot write.
        let result = check_access(
            &reader,
            "/hexads/other-hexad",
            &Method::PUT,
            &rbac,
        );
        assert!(result.is_err());

        // But the entity ACL grants write on "secret-hexad".
        assert!(check_access(
            &reader,
            "/hexads/secret-hexad",
            &Method::PUT,
            &rbac,
        ).is_ok());
    }

    // ------------------------------------------------------------------
    // Test 7: Audit log records decisions
    // ------------------------------------------------------------------
    #[test]
    fn test_audit_log_records_decisions() {
        let rbac = default_rbac();
        let admin = identity("audit-admin", ClientRole::Admin);
        let reader = identity("audit-reader", ClientRole::Reader);

        // Successful access.
        let _ = check_access(&admin, "/hexads", &Method::GET, &rbac);
        // Denied access.
        let _ = check_access(&reader, "/hexads", &Method::POST, &rbac);

        let entries = rbac.audit_log.entries();
        assert!(entries.len() >= 2, "Expected at least 2 audit entries, got {}", entries.len());

        // First entry: admin allowed read.
        let allowed_entry = entries.iter().find(|e| e.decision == AccessDecision::Allowed);
        assert!(allowed_entry.is_some(), "Expected an ALLOWED entry");
        let allowed = allowed_entry.unwrap();
        assert_eq!(allowed.client_id, "audit-admin");
        assert_eq!(allowed.client_role, "admin");
        assert_eq!(allowed.required_permission, Permission::Read);

        // Second entry: reader denied write.
        let denied_entry = entries.iter().find(|e| e.decision == AccessDecision::Denied);
        assert!(denied_entry.is_some(), "Expected a DENIED entry");
        let denied = denied_entry.unwrap();
        assert_eq!(denied.client_id, "audit-reader");
        assert_eq!(denied.client_role, "reader");
        assert_eq!(denied.required_permission, Permission::Write);
        assert!(denied.reason.is_some());
    }

    // ------------------------------------------------------------------
    // Test 8: Audit log capacity limit
    // ------------------------------------------------------------------
    #[test]
    fn test_audit_log_capacity() {
        let log = AuditLog::new(3);
        assert!(log.is_empty());

        for i in 0..5 {
            log.record(AuditEntry {
                timestamp: i as u64,
                client_id: format!("client-{}", i),
                client_role: "reader".to_string(),
                resource_path: "/test".to_string(),
                method: "GET".to_string(),
                required_permission: Permission::Read,
                decision: AccessDecision::Allowed,
                reason: None,
            });
        }

        // Should only retain the last 3 entries.
        assert_eq!(log.len(), 3);
        let entries = log.entries();
        assert_eq!(entries[0].client_id, "client-2");
        assert_eq!(entries[1].client_id, "client-3");
        assert_eq!(entries[2].client_id, "client-4");
    }

    // ------------------------------------------------------------------
    // Test 9: Required permission derivation
    // ------------------------------------------------------------------
    #[test]
    fn test_required_permission_derivation() {
        // Read
        assert_eq!(required_permission(&Method::GET, "/hexads"), Permission::Read);
        assert_eq!(required_permission(&Method::HEAD, "/hexads"), Permission::Read);
        assert_eq!(required_permission(&Method::OPTIONS, "/anything"), Permission::Read);

        // Write
        assert_eq!(required_permission(&Method::POST, "/hexads"), Permission::Write);
        assert_eq!(required_permission(&Method::PUT, "/hexads/abc"), Permission::Write);
        assert_eq!(required_permission(&Method::DELETE, "/hexads/abc"), Permission::Write);

        // Execute
        assert_eq!(required_permission(&Method::POST, "/query/plan"), Permission::Execute);
        assert_eq!(required_permission(&Method::POST, "/query/explain"), Permission::Execute);
        assert_eq!(required_permission(&Method::POST, "/search/vector"), Permission::Execute);
        assert_eq!(required_permission(&Method::POST, "/search/text?q=foo"), Permission::Execute);
        assert_eq!(required_permission(&Method::POST, "/queries/similar"), Permission::Execute);

        // Admin
        assert_eq!(
            required_permission(&Method::POST, "/normalizer/trigger/abc"),
            Permission::Admin
        );
        assert_eq!(
            required_permission(&Method::PUT, "/planner/config"),
            Permission::Admin
        );
    }

    // ------------------------------------------------------------------
    // Test 10: Entity and modality extraction from paths
    // ------------------------------------------------------------------
    #[test]
    fn test_entity_and_modality_extraction() {
        // Entity extraction
        assert_eq!(entity_from_path("/hexads/my-entity"), Some("my-entity"));
        assert_eq!(entity_from_path("/hexads/abc/sub"), Some("abc"));
        assert_eq!(entity_from_path("/drift/entity/drift-id"), Some("drift-id"));
        assert_eq!(entity_from_path("/normalizer/trigger/norm-id"), Some("norm-id"));
        assert_eq!(entity_from_path("/hexads"), None);
        assert_eq!(entity_from_path("/search/text"), None);

        // Modality extraction
        assert_eq!(modality_from_path("/search/vector"), Some("vector"));
        assert_eq!(modality_from_path("/search/text"), Some("document"));
        assert_eq!(modality_from_path("/search/related/xyz"), Some("graph"));
        assert_eq!(modality_from_path("/drift/status"), Some("temporal"));
        assert_eq!(modality_from_path("/hexads"), None);
        assert_eq!(modality_from_path("/query/plan"), None);
    }

    // ------------------------------------------------------------------
    // Test 11: Custom role definition
    // ------------------------------------------------------------------
    #[test]
    fn test_custom_role_definition() {
        let mut policy = RbacPolicy::new();

        let mut modality_perms = HashMap::new();
        modality_perms.insert(
            "vector".to_string(),
            vec![Permission::Read, Permission::Write, Permission::Execute],
        );

        policy.set_role(RoleDefinition {
            name: "writer".to_string(),
            global_permissions: vec![Permission::Read],
            modality_permissions: modality_perms,
        });

        let rbac = RbacState::new(policy);
        let writer = identity("custom-writer", ClientRole::Writer);

        // Global read → allowed.
        assert!(check_access(&writer, "/hexads", &Method::GET, &rbac).is_ok());

        // Vector write → allowed (modality grant).
        assert!(check_access(&writer, "/search/vector", &Method::POST, &rbac).is_ok());

        // Hexad write → denied (no global write, no modality for hexad paths).
        let result = check_access(&writer, "/hexads", &Method::POST, &rbac);
        assert!(result.is_err());
    }

    // ------------------------------------------------------------------
    // Test 12: Missing role definition handled gracefully
    // ------------------------------------------------------------------
    #[test]
    fn test_missing_role_definition() {
        // Policy with no roles at all.
        let policy = RbacPolicy::new();
        let rbac = RbacState::new(policy);
        let reader = identity("orphan-user", ClientRole::Reader);

        let result = check_access(&reader, "/hexads", &Method::GET, &rbac);
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(err.error.contains("No role definition found"));
    }

    // ------------------------------------------------------------------
    // Test 13: check_authorization wrapper works identically
    // ------------------------------------------------------------------
    #[test]
    fn test_check_authorization_wrapper() {
        let rbac = default_rbac();
        let admin = identity("wrapper-admin", ClientRole::Admin);
        let reader = identity("wrapper-reader", ClientRole::Reader);

        // Admin should pass.
        assert!(check_authorization(&admin, "/hexads", &Method::POST, &rbac).is_ok());

        // Reader write should fail.
        assert!(check_authorization(&reader, "/hexads", &Method::POST, &rbac).is_err());
    }

    // ------------------------------------------------------------------
    // Test 14: Entity ACL does not leak to other entities
    // ------------------------------------------------------------------
    #[test]
    fn test_entity_acl_isolation() {
        let mut policy = RbacPolicy::default();
        policy.add_entity_acl("entity-alpha", "reader-x", vec![Permission::Write]);

        let rbac = RbacState::new(policy);
        let reader = identity("reader-x", ClientRole::Reader);

        // Write to entity-alpha → allowed via ACL.
        assert!(check_access(&reader, "/hexads/entity-alpha", &Method::PUT, &rbac).is_ok());

        // Write to entity-beta → denied (no ACL for this entity).
        let result = check_access(&reader, "/hexads/entity-beta", &Method::PUT, &rbac);
        assert!(result.is_err());

        // Write to entity-alpha by a DIFFERENT client → denied.
        let other_reader = identity("reader-y", ClientRole::Reader);
        let result = check_access(
            &other_reader,
            "/hexads/entity-alpha",
            &Method::PUT,
            &rbac,
        );
        assert!(result.is_err());
    }

    // ------------------------------------------------------------------
    // Test 15: Audit log clear
    // ------------------------------------------------------------------
    #[test]
    fn test_audit_log_clear() {
        let rbac = default_rbac();
        let admin = identity("clear-admin", ClientRole::Admin);

        let _ = check_access(&admin, "/hexads", &Method::GET, &rbac);
        assert!(!rbac.audit_log.is_empty());

        rbac.audit_log.clear();
        assert!(rbac.audit_log.is_empty());
        assert_eq!(rbac.audit_log.len(), 0);
    }
}
