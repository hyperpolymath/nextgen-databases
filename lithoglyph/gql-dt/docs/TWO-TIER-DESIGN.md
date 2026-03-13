# GQL-DT Two-Tier Language Design

**SPDX-License-Identifier:** PMPL-1.0-or-later
**SPDX-FileCopyrightText:** 2026 Jonathan D.A. Jewell (@hyperpolymath)

**Date:** 2026-02-01
**Status:** Architectural Decision

---

## The Problem: Two User Populations

### Population 1: Developers & Advanced Admins (GQL-DT)
- **Who:** Formal methods experts, security auditors, senior database admins
- **Needs:** Full type safety, proof obligations, compile-time verification
- **Willing to:** Write proofs, understand dependent types, debug type errors
- **Use case:** Extreme secure audit projects, critical data entry

### Population 2: Regular Users & Junior Admins (GQL)
- **Who:** Journalists, researchers, junior staff
- **Needs:** Simple syntax, runtime checks, helpful error messages
- **Can't:** Write Lean 4 proofs, understand type theory
- **Use case:** Day-to-day database operations, routine queries

---

## Solution: Two-Tier Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  GQL-DT (Type-Safe Tier)                                    │
│  - Full dependent types                                      │
│  - Compile-time proofs required                              │
│  - Used by: Developers, advanced admins                      │
│  - Error: Proof fails → Query doesn't compile                │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ├─ Compiles to ──→
                       │
┌──────────────────────▼──────────────────────────────────────┐
│  GQL (Runtime-Checked Tier)                                │
│  - Familiar SQL-like syntax                                  │
│  - Runtime constraint checks                                 │
│  - Used by: Regular users, junior admins                     │
│  - Error: Constraint violated → Runtime error with fix       │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ├─ Both execute on ──→
                       │
┌──────────────────────▼──────────────────────────────────────┐
│  Lithoglyph Runtime                                              │
│  - Stores data with constraints                              │
│  - Enforces invariants at runtime                            │
│  - Accepts queries from both tiers                           │
└─────────────────────────────────────────────────────────────┘
```

---

## Tier 1: GQL-DT (Developer/Admin)

### Syntax: Explicit Types & Proofs

```lean
-- GQL-DT: Full type annotations
INSERT INTO evidence (
  title : NonEmptyString,
  prompt_provenance : BoundedNat 0 100
)
VALUES (
  NonEmptyString.mk "ONS Data" (by decide),
  BoundedNat.mk 0 100 95 (by omega) (by omega)
)
RATIONALE "Official statistics"
WITH_PROOF {
  scores_in_bounds: by lithoglyph_prompt,
  provenance_tracked: by lithoglyph_prov
};
```

**Characteristics:**
- ✅ **Compile-time verification** - Invalid queries don't compile
- ✅ **Proof obligations** - Must provide proofs or use auto-tactics
- ✅ **Type safety guaranteed** - No runtime type errors possible
- ⚠️ **Steep learning curve** - Requires Lean 4 knowledge
- ⚠️ **Verbose** - Explicit types and proofs

**Who uses it:**
- Security auditors entering sensitive data
- Database administrators setting up schemas
- Developers creating normalization proofs
- Formal verification team

---

## Tier 2: GQL (Regular User)

### Syntax: Familiar SQL-Style

```sql
-- GQL: Inferred types, runtime checks
INSERT INTO evidence (title, prompt_provenance)
VALUES ('ONS Data', 95)
RATIONALE 'Official statistics';

-- Behind the scenes:
-- 1. Type inference: 'ONS Data' → NonEmptyString (inferred)
-- 2. Bounds check: 95 ∈ [0, 100] → validated at runtime
-- 3. Rationale check: 'Official statistics' non-empty → validated
```

**Characteristics:**
- ✅ **Familiar syntax** - Looks like standard SQL
- ✅ **Type inference** - Types automatically inferred
- ✅ **Helpful errors** - Runtime errors with fix suggestions
- ✅ **No proofs needed** - Constraints checked at runtime
- ⚠️ **Runtime overhead** - Validation happens at execution

**Who uses it:**
- Journalists entering evidence
- Researchers adding claims
- Junior admins performing routine operations
- General users querying data

---

## How They Interact: Compilation Strategy

### GQL → GQL-DT → Lithoglyph

```
User writes GQL
      ↓
Type Inference (auto-generate types)
      ↓
Proof Generation (auto-generate proofs or admit)
      ↓
GQL-DT AST (with types & proofs)
      ↓
Type Checking (validate proofs)
      ↓
  ┌───┴───┐
  │ Valid │ Invalid
  ↓       ↓
Execute   Error (with fix suggestion)
```

### Example: GQL → GQL-DT Translation

**Input (GQL):**
```sql
INSERT INTO evidence (prompt_provenance) VALUES (95);
```

**Translated to (GQL-DT):**
```lean
INSERT INTO evidence (
  prompt_provenance : BoundedNat 0 100
)
VALUES (
  BoundedNat.mk 0 100 95 (by omega) (by omega)
)
RATIONALE (inferred from context)
WITH_PROOF {
  bounds_check: by omega  -- Auto-generated!
};
```

**If value is invalid:**
```sql
INSERT INTO evidence (prompt_provenance) VALUES (150);
-- Runtime error: Value 150 out of bounds [0, 100]
-- Suggestion: Use a value between 0 and 100
```

---

## Preventing User Mistakes: Safety Mechanisms

### Problem: "Annoying users mess up, admins spend time fixing"

### Solution 1: Transaction-Based Validation

```sql
-- User's transaction
BEGIN TRANSACTION;
  INSERT INTO evidence (title, prompt_provenance)
  VALUES ('My Evidence', 150);  -- Invalid!
COMMIT;

-- What happens:
-- 1. Query enters validation queue
-- 2. Type checker runs (auto-prove or reject)
-- 3. If valid: execute immediately
-- 4. If invalid: error + admin notification

-- User sees:
ERROR: Value 150 out of bounds for prompt_provenance
Expected: Integer between 0 and 100
Suggestion: Change 150 to a value like 95
Status: NOT COMMITTED (no data changed)
```

**Key insight:** Invalid queries never reach the database!

### Solution 2: Permission-Based Write Access

```sql
-- Schema-level permissions
CREATE COLLECTION evidence (
  title : NonEmptyString,
  prompt_provenance : BoundedNat 0 100
) WITH DEPENDENT_TYPES
  PERMISSIONS (
    -- Regular users can INSERT with runtime checks
    GRANT INSERT TO users WITH VALIDATION LEVEL runtime;

    -- Admins can INSERT with compile-time checks bypassed
    GRANT INSERT TO admins WITH VALIDATION LEVEL compile_time;

    -- Advanced admins can modify schema
    GRANT ALTER TO advanced_admins WITH VALIDATION LEVEL proof_required;
  );
```

**Access levels:**
- `runtime`: GQL with type inference + runtime checks
- `compile_time`: GQL-DT with proofs auto-generated where possible
- `proof_required`: GQL-DT with manual proofs required (no auto-admit)

### Solution 3: Admin Review Queue

```sql
-- User submits query
INSERT INTO evidence (prompt_provenance) VALUES (95);
-- Status: Pending review (if configured)

-- Admin sees in review queue:
SELECT * FROM pending_queries WHERE status = 'needs_review';

-- Result:
-- query_id | user      | query                 | validation_status
-- 1        | alice     | INSERT INTO ...       | ✓ Type-safe
-- 2        | bob       | INSERT INTO ...       | ✗ Bounds error
-- 3        | charlie   | UPDATE ...            | ⚠ Manual proof needed

-- Admin actions:
APPROVE QUERY 1;  -- Execute immediately
REJECT QUERY 2 REASON "Invalid value";  -- Notify user
ASSIST QUERY 3 WITH_PROOF { ... };  -- Provide proof, then execute
```

### Solution 4: Template-Based Entry (Recommended!)

**Instead of letting users write raw SQL:**

```typescript
// Lithoglyph Studio: Web UI with type-safe form
interface EvidenceForm {
  title: string  // Auto-validated: non-empty
  promptProvenance: number  // Auto-validated: 0-100 with slider
  rationale: string  // Auto-validated: non-empty
}

function submitEvidence(form: EvidenceForm) {
  // UI pre-validates
  if (form.promptProvenance < 0 || form.promptProvenance > 100) {
    showError("Score must be between 0 and 100")
    return
  }

  // Generate type-safe GQL
  const query = `
    INSERT INTO evidence (title, prompt_provenance)
    VALUES ('${form.title}', ${form.promptProvenance})
    RATIONALE '${form.rationale}'
  `

  // Submit (will be validated again server-side)
  await lithoglyph.execute(query)
}
```

**Benefits:**
- ✅ Users never write raw SQL
- ✅ UI enforces constraints (dropdowns, sliders, validation)
- ✅ Type-safe generation of GQL
- ✅ Admins don't see malformed queries

### Solution 5: Gradual Validation Levels

```sql
-- Configure per-collection validation strictness
ALTER COLLECTION evidence
  SET VALIDATION_LEVEL FOR users = 'strict';
  -- Options: 'permissive', 'strict', 'paranoid'

-- Permissive: Runtime checks, auto-fix attempts
INSERT INTO evidence (prompt_provenance) VALUES (150);
-- Auto-fix: Clamped to 100 (with warning)

-- Strict: Runtime checks, reject on error
INSERT INTO evidence (prompt_provenance) VALUES (150);
-- Error: Value out of bounds (no auto-fix)

-- Paranoid: Compile-time checks required
INSERT INTO evidence (prompt_provenance) VALUES (150);
-- Error: Proof obligation failed, query not executed
```

---

## When to Use Each Tier

### Use GQL-DT (Type-Safe) When:
1. **Defining schemas** - Admins create collections with type constraints
2. **Critical data entry** - Security auditors entering sensitive evidence
3. **Normalization operations** - Database transformations need proofs
4. **Integration code** - Programmatic access from applications

### Use GQL (Runtime-Checked) When:
1. **Routine queries** - Day-to-day SELECT operations
2. **User data entry** - Journalists adding evidence
3. **Exploratory analysis** - Researchers querying data
4. **Learning/testing** - New users getting familiar with system

---

## Implementation Timeline

### Phase 1: GQL-DT Only (Current)
- ✅ Milestone 1-4: Core types implemented
- 🔧 Milestone 5-6: Parser + type checker

**Status:** Advanced users can use GQL-DT now

### Phase 2: GQL with Type Inference (Next)
- [ ] Type inference engine
- [ ] Auto-proof generation (omega, decide tactics)
- [ ] Runtime validation layer
- [ ] Error messages with suggestions

**Estimated:** 2-3 months after M6 complete

### Phase 3: Validation Levels & Permissions (Later)
- [ ] Permission system
- [ ] Admin review queue
- [ ] Gradual validation levels
- [ ] Audit trail

**Estimated:** 4-6 months

### Phase 4: Lithoglyph Studio UI (Future)
- [ ] Web-based form builder
- [ ] Type-safe form generation
- [ ] Visual query builder
- [ ] No raw SQL for end users

**Estimated:** 6-9 months

---

## Recommended Approach: NOW vs LATER

### ✅ Deal with NOW (During Parser Implementation)

1. **Design AST to support both tiers**
   - Explicit types (GQL-DT) vs inferred types (GQL)
   - Proof annotations optional
   - Same AST, different parsing paths

2. **Add type inference hooks**
   - Placeholder for "infer type from value"
   - Auto-proof generation infrastructure
   - Graceful degradation (admit if can't prove)

3. **Define validation levels**
   - Schema metadata: which tier is allowed
   - User roles: which validation level they get
   - Default: GQL for users, GQL-DT for admins

### ⏳ Deal with LATER (After M6)

1. **Actual GQL parser**
   - SQL-like syntax parser
   - Type inference algorithm
   - Auto-proof tactics

2. **Runtime validation**
   - Constraint checking at execution
   - Error messages with fix suggestions
   - Auto-fix for permissive mode

3. **UI/Forms**
   - Lithoglyph Studio
   - Template-based entry
   - Zero SQL for end users

---

## Example: Dual-Tier in Practice

### Schema Definition (Admin, GQL-DT)

```lean
CREATE COLLECTION evidence (
  id : UUID PRIMARY KEY,
  title : NonEmptyString,
  prompt_provenance : BoundedNat 0 100,
  prompt_scores : PromptScores
) WITH DEPENDENT_TYPES
  TARGET_NORMAL_FORM BCNF
  PERMISSIONS (
    GRANT SELECT TO public;
    GRANT INSERT TO users WITH VALIDATION runtime;
    GRANT INSERT TO admins WITH VALIDATION compile_time;
  );
```

### User Insert (GQL, Type-Inferred)

```sql
-- User writes simple SQL
INSERT INTO evidence (title, prompt_provenance)
VALUES ('ONS Data', 95)
RATIONALE 'Official statistics';

-- System infers:
-- title: NonEmptyString (from 'ONS Data' length > 0)
-- prompt_provenance: BoundedNat 0 100 (95 ∈ [0, 100])
-- rationale: Rationale (from 'Official statistics' non-empty)

-- Auto-generates proof:
-- WITH_PROOF {
--   title_nonempty: by decide,
--   score_in_bounds: by omega
-- }

-- Executes immediately if all proofs pass
```

### Admin Insert (GQL-DT, Explicit Types)

```lean
-- Admin writes full type annotations
INSERT INTO evidence (
  title : NonEmptyString,
  prompt_scores : PromptScores
)
VALUES (
  NonEmptyString.mk "ONS CPI Data" (by decide),
  PromptScores.create
    (BoundedNat.mk 0 100 100 (by omega) (by omega))
    (BoundedNat.mk 0 100 100 (by omega) (by omega))
    (BoundedNat.mk 0 100 95 (by omega) (by omega))
    (BoundedNat.mk 0 100 95 (by omega) (by omega))
    (BoundedNat.mk 0 100 100 (by omega) (by omega))
    (BoundedNat.mk 0 100 95 (by omega) (by omega))
)
RATIONALE "Official UK government statistics"
WITH_PROOF {
  all_scores_valid: by lithoglyph_prompt,
  overall_computed: by lithoglyph_prompt
};

-- Compile-time type checking ensures correctness
```

---

## Decision: Start Two-Tier Support NOW

**Recommendation:** Add two-tier support **during Milestone 6 (Parser)**

**Why NOW:**
1. Parser architecture affects both tiers
2. AST design must support type inference
3. Easier to build both parsers together
4. Type inference shares infrastructure with type checker

**What to implement:**

### M6a: GQL-DT Parser (Full Types)
- Parse explicit type annotations
- Parse proof obligations
- Generate typed AST

### M6b: GQL Parser (Type Inference)
- Parse SQL-like syntax
- Infer types from values
- Auto-generate proofs where possible
- Graceful degradation (admit if can't prove)

### M6c: Unified Type Checker
- Check both explicit and inferred types
- Validate or auto-prove obligations
- Helpful error messages for both tiers

---

## Summary

### Two Tiers

| Feature | GQL-DT (Advanced) | GQL (Users) |
|---------|-------------------|--------------|
| **Syntax** | Lean 4-style | SQL-style |
| **Types** | Explicit | Inferred |
| **Proofs** | Required | Auto-generated |
| **Validation** | Compile-time | Runtime |
| **Errors** | Type errors | Constraint violations |
| **Users** | Admins, developers | Everyone else |

### Preventing User Mistakes

1. **Transaction validation** - Invalid queries don't commit
2. **Permission levels** - Users get runtime validation
3. **Admin review queue** - Optional approval workflow
4. **Template-based UI** - Lithoglyph Studio (no raw SQL)
5. **Gradual strictness** - Permissive/strict/paranoid modes

### Timeline

- ✅ **NOW:** Design dual-tier AST, add type inference hooks
- 🔧 **M6:** Implement both parsers together
- ⏳ **Later:** Runtime validation, UI, permissions

---

## Granular Permission System: Workplace-Specific Type Restrictions

### The Question: "Can we restrict users to ONLY numbers, strings, dates?"

**Answer: YES - Fine-grained type-level permissions**

### Permission Architecture

```lean
-- Type whitelist per role
structure TypeWhitelist where
  allowedTypes : List TypeExpr
  allowBuiltinTypes : Bool      -- Nat, String, Bool
  allowRefinedTypes : Bool      -- BoundedNat, NonEmptyString
  allowDependentTypes : Bool    -- PromptScores, custom types
  allowProofTypes : Bool        -- Types requiring manual proofs

-- Permission profile for a user or role
structure PermissionProfile where
  name : String
  typeWhitelist : TypeWhitelist
  validationLevel : ValidationLevel
  canCreateSchema : Bool
  canModifySchema : Bool
  canDeleteData : Bool
```

### Example: Restrict Users to Basic Types Only

```lean
-- Workplace policy: journalists can only use Nat, String, Date
def journalistPermissions : PermissionProfile := {
  name := "journalist"
  typeWhitelist := {
    allowedTypes := [.nat, .string, .date],  -- ONLY these types
    allowBuiltinTypes := true,
    allowRefinedTypes := false,   -- No BoundedNat
    allowDependentTypes := false, -- No PromptScores
    allowProofTypes := false      -- No custom proofs
  },
  validationLevel := .runtime,    -- GQL only
  canCreateSchema := false,
  canModifySchema := false,
  canDeleteData := false
}

-- Admin permissions: full access
def adminPermissions : PermissionProfile := {
  name := "admin"
  typeWhitelist := {
    allowedTypes := [],           -- Empty = all types allowed
    allowBuiltinTypes := true,
    allowRefinedTypes := true,
    allowDependentTypes := true,
    allowProofTypes := true
  },
  validationLevel := .compile,    -- GQL-DT allowed
  canCreateSchema := true,
  canModifySchema := true,
  canDeleteData := true
}
```

### Permission Enforcement in Parser

```lean
-- Parser checks permissions before accepting query
def parseWithPermissions
  (query : String)
  (user : User)
  (profile : PermissionProfile)
  : IO (Except String (InsertStmt schema)) := do

  -- 1. Parse query (GQL or GQL-DT based on validationLevel)
  let ast ← if profile.validationLevel == .runtime then
    parseGQL query
  else
    parseGQL-DT query

  -- 2. Extract types used in query
  let usedTypes := ast.values.map (·.1)

  -- 3. Check all types are allowed
  for t in usedTypes do
    if !isTypeAllowed t profile.typeWhitelist then
      return .error s!"Type {t} not allowed for user {user.name}. Allowed types: {profile.typeWhitelist.allowedTypes}"

  -- 4. Proceed with type checking
  return typeCheck ast profile.validationLevel
```

### Schema-Level Type Restrictions

```sql
-- Create schema with per-role type restrictions
CREATE COLLECTION simple_data (
  id : Nat,
  name : String,
  created : Date,
  score : BoundedNat 0 100  -- Only admins can insert this!
) WITH PERMISSIONS (
  -- Journalists: can INSERT, but only to Nat/String/Date columns
  GRANT INSERT (id, name, created) TO journalists
    WITH TYPES RESTRICTED TO (Nat, String, Date);

  -- Admins: can INSERT to all columns including BoundedNat
  GRANT INSERT (id, name, created, score) TO admins
    WITH TYPES UNRESTRICTED;

  -- Everyone: can SELECT
  GRANT SELECT TO public;
);
```

### Workplace Configuration Examples

#### Example 1: Journalism Organization

```scheme
; workplace-policy.scm
(define journalism-org
  (workplace
    (name "Daily News")
    (roles
      (role (name "journalist")
            (types (Nat String Date))
            (validation runtime)
            (operations (SELECT INSERT)))
      (role (name "editor")
            (types (Nat String Date BoundedNat NonEmptyString))
            (validation runtime)
            (operations (SELECT INSERT UPDATE)))
      (role (name "tech-admin")
            (types all)
            (validation compile)
            (operations all)))))
```

**Result:**
- Journalists: Simple GQL, basic types only, can't mess up type system
- Editors: GQL with some refined types, still runtime-checked
- Tech admins: Full GQL-DT, compile-time verification

#### Example 2: Security Audit Firm

```scheme
; workplace-policy.scm
(define security-firm
  (workplace
    (name "SecureAudit LLC")
    (roles
      (role (name "junior-auditor")
            (types (Nat String Date Confidence))  ; Confidence is BoundedNat 0 100
            (validation strict)     ; Strict runtime validation
            (operations (SELECT INSERT))
            (require-review true))  ; All queries go to review queue
      (role (name "senior-auditor")
            (types all-refined)     ; All refined types, no dependent types
            (validation compile)
            (operations (SELECT INSERT UPDATE))
            (require-review false))
      (role (name "principal")
            (types all)
            (validation paranoid)   ; Manual proofs required
            (operations all)
            (require-review false)))))
```

**Result:**
- Junior auditors: Limited types, all queries reviewed
- Senior auditors: All standard types, compile-time checks
- Principals: Full dependent types, manual proof obligations

### Implementation: Type Filter in AST

```lean
-- Check if type is allowed for user
def isTypeAllowed (t : TypeExpr) (whitelist : TypeWhitelist) : Bool :=
  -- If allowedTypes is empty, allow all
  if whitelist.allowedTypes.isEmpty then
    true
  -- If type is in explicit whitelist, allow it
  else if whitelist.allowedTypes.contains t then
    true
  -- Check categorical permissions
  else match t with
    | .nat | .string | .bool | .date =>
        whitelist.allowBuiltinTypes
    | .boundedNat _ _ | .boundedFloat _ _ | .nonEmptyString | .confidence =>
        whitelist.allowRefinedTypes
    | .promptScores | .custom _ =>
        whitelist.allowDependentTypes
    | .proof _ =>
        whitelist.allowProofTypes

-- Filter schema columns to only show allowed types
def filterSchemaForUser (schema : Schema) (profile : PermissionProfile) : Schema :=
  { schema with
    columns := schema.columns.filter (fun col =>
      isTypeAllowed col.type profile.typeWhitelist) }
```

### User Experience with Type Restrictions

**Journalist attempts to use BoundedNat:**
```sql
-- User: journalist (restricted to Nat, String, Date)
INSERT INTO evidence (title, prompt_provenance)
VALUES ('My Evidence', 95);

-- Parser response:
ERROR: Type 'BoundedNat 0 100' not allowed for user 'alice'
Allowed types: Nat, String, Date
Column 'prompt_provenance' requires type 'BoundedNat 0 100'

Suggestion: Contact your administrator to request access to this column,
or use a different column that accepts your allowed types.
Available columns for you: id (Nat), title (String), created_date (Date)
```

**Admin uses same query:**
```sql
-- User: admin (unrestricted)
INSERT INTO evidence (title, prompt_provenance)
VALUES ('My Evidence', 95);

-- Parser response:
✓ Type checking successful
✓ Auto-proved: prompt_provenance ∈ [0, 100]
Executing INSERT...
```

### Form-Based UI Respects Permissions

```typescript
// Lithoglyph Studio auto-hides fields based on permissions
function renderEvidenceForm(user: User, profile: PermissionProfile) {
  const schema = getSchema("evidence");
  const allowedColumns = filterSchemaForUser(schema, profile);

  return (
    <Form>
      {allowedColumns.map(col => (
        <Field
          key={col.name}
          name={col.name}
          type={sqlTypeToFormType(col.type)}
          validation={getValidationForType(col.type, profile)}
        />
      ))}
      {/* Users NEVER see restricted columns - they don't exist in UI! */}
    </Form>
  );
}
```

---

## Summary: One Language, Layered Access Control

### Layer 1: Syntax Choice (User Convenience)
- **GQL**: SQL-like, type inference, runtime checks
- **GQL-DT**: Lean-like, explicit types, compile-time proofs
- **Same language**, different parsers, same AST

### Layer 2: Type Permissions (Organizational Policy)
- **Whitelist-based**: Only allow specific types per role
- **Granular**: Can restrict to `[Nat, String, Date]` only
- **Schema-level**: Column access based on type requirements
- **Enforced in parser**: Type checks happen before execution

### Layer 3: Validation Level (Risk Management)
- **Permissive**: Runtime checks with auto-fix
- **Strict**: Runtime checks, reject on error
- **Compile**: Compile-time proofs (auto-generated)
- **Paranoid**: Manual proofs required

### Layer 4: UI Forms (Maximum Safety)
- **No syntax exposure**: Users never write SQL/GQL-DT
- **Type-driven forms**: UI generates based on allowed types
- **Impossible to bypass**: Restricted columns don't appear

### Answer to "Flexibility" Question

**Q: Can a workplace say "GQL with numbers, strings, dates BUT NOTHING ELSE"?**

**A: YES, exactly this:**

```lean
def workplacePolicy : PermissionProfile := {
  name := "basic-user"
  typeWhitelist := {
    allowedTypes := [.nat, .string, .date],
    allowBuiltinTypes := true,   -- Nat, String allowed
    allowRefinedTypes := false,  -- No BoundedNat
    allowDependentTypes := false, -- No PromptScores
    allowProofTypes := false     -- No proofs
  },
  validationLevel := .runtime,   -- GQL only
  canCreateSchema := false,
  canModifySchema := false,
  canDeleteData := false
}
```

**Result:**
- ✅ Can use: Nat, String, Date
- ❌ Cannot use: BoundedNat, NonEmptyString, PromptScores, custom types
- ✅ Syntax: Simple SQL (GQL)
- ❌ Cannot access: GQL-DT syntax, proof obligations, dependent types
- ✅ Queries: Runtime-checked, helpful error messages
- ❌ Cannot break: Type system (restricted types can't violate invariants)

---

**Document Status:** Complete architectural decision for two-tier language design with granular permission system

**Recommendation:** Implement dual-tier support + permission system in Milestone 6 (Parser)

**Next Steps:**
1. Design AST to support both tiers
2. Implement GQL-DT parser (explicit types)
3. Implement GQL parser (type inference)
4. Implement TypeWhitelist and PermissionProfile
5. Unified type checker with permission enforcement
6. Schema-level permission annotations
