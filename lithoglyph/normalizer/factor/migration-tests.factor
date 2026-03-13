! SPDX-License-Identifier: PMPL-1.0-or-later
! Form.Normalizer - Three-Phase Migration Tests
!
! End-to-end tests for the migration framework per D-NORM-005.
! Tests the Announce -> Shadow -> Commit lifecycle.

USING: accessors arrays assocs continuations io kernel math
migration namespaces sequences strings tools.test vectors ;

IN: migration-tests

! ============================================================
! Test Fixtures
! ============================================================

: sample-transformation ( -- transform )
    "Normalize orders table to 3NF" ;

: sample-source ( -- source )
    { "order_id" "customer_id" "customer_name" "product_id" "product_name" "quantity" } ;

: sample-target ( -- target )
    { "orders" "customers" "products" } ;

: sample-affected-queries ( -- queries )
    {
        "SELECT * FROM orders WHERE customer_id = ?"
        "SELECT o.*, c.name FROM orders o JOIN customers c ON o.customer_id = c.id"
        "UPDATE orders SET quantity = ? WHERE order_id = ?"
    } ;

! ============================================================
! Phase Transition Tests
! ============================================================

{ t } [
    ! Test: Migration starts in announce phase
    sample-transformation
    "normalize"
    sample-source
    sample-target
    sample-affected-queries
    1
    start-migration
    phase>> announce?
] unit-test

{ t } [
    ! Test: Can advance from announce to shadow
    sample-transformation
    "normalize"
    sample-source
    sample-target
    sample-affected-queries
    2
    start-migration
    advance-to-shadow
    phase>> shadow?
] unit-test

{ t } [
    ! Test: Can advance from shadow to commit
    sample-transformation
    "normalize"
    sample-source
    sample-target
    sample-affected-queries
    3
    start-migration
    advance-to-shadow
    advance-to-commit
    phase>> commit?
] unit-test

{ f } [
    ! Test: Cannot advance from announce directly to commit
    sample-transformation
    "normalize"
    sample-source
    sample-target
    sample-affected-queries
    4
    start-migration
    advance-to-commit
    phase>> commit?
] unit-test

! ============================================================
! Rewrite Rule Tests
! ============================================================

{ 3 } [
    ! Test: Rewrite rules generated for affected queries
    sample-transformation
    "normalize"
    sample-source
    sample-target
    sample-affected-queries
    5
    start-migration
    advance-to-shadow
    rewrite-rules>> length
] unit-test

{ t } [
    ! Test: Rewrite rules contain original queries
    sample-transformation
    "normalize"
    sample-source
    sample-target
    sample-affected-queries
    6
    start-migration
    advance-to-shadow
    rewrite-rules>>
    [ original-query>> ] map
    "SELECT * FROM orders WHERE customer_id = ?" swap member?
] unit-test

! ============================================================
! Compatibility View Tests
! ============================================================

{ t } [
    ! Test: Compat views created in shadow phase
    sample-transformation
    "normalize"
    sample-source
    sample-target
    sample-affected-queries
    7
    start-migration
    advance-to-shadow
    compat-views>> empty? not
] unit-test

{ t } [
    ! Test: Compat views removed at commit
    sample-transformation
    "normalize"
    sample-source
    sample-target
    sample-affected-queries
    8
    start-migration
    advance-to-shadow
    advance-to-commit
    compat-views>> empty?
] unit-test

! ============================================================
! Query Execution Tests
! ============================================================

{ "old" } [
    ! Test: During announce, queries execute against old schema
    sample-transformation
    "normalize"
    sample-source
    sample-target
    sample-affected-queries
    9
    start-migration
    "SELECT * FROM orders" swap
    execute-with-migration
    "schema" swap at
] unit-test

{ t } [
    ! Test: During shadow, queries are rewritten
    sample-transformation
    "normalize"
    sample-source
    sample-target
    sample-affected-queries
    10
    start-migration
    advance-to-shadow :> state
    "SELECT * FROM orders WHERE customer_id = ?" state
    execute-with-migration
    "schema" swap at "new" swap subseq?
] unit-test

! ============================================================
! Narrative Generation Tests
! ============================================================

{ t } [
    ! Test: Narrative contains phase information
    sample-transformation
    "normalize"
    sample-source
    sample-target
    sample-affected-queries
    11
    start-migration
    migration>narrative
    "ANNOUNCE" swap subseq?
] unit-test

{ t } [
    ! Test: Narrative updates with phase changes
    sample-transformation
    "normalize"
    sample-source
    sample-target
    sample-affected-queries
    12
    start-migration
    advance-to-shadow
    migration>narrative
    "SHADOW" swap subseq?
] unit-test

{ t } [
    ! Test: Narrative includes transformation type
    sample-transformation
    "normalize"
    sample-source
    sample-target
    sample-affected-queries
    13
    start-migration
    migration>narrative
    "normalize" swap subseq?
] unit-test

! ============================================================
! Error Handling Tests
! ============================================================

{ t } [
    ! Test: Errors are recorded
    sample-transformation
    "normalize"
    sample-source
    sample-target
    sample-affected-queries
    14
    start-migration
    ! Try invalid operation: advance announce->commit directly
    advance-to-commit
    errors>> empty? not
] unit-test

{ t } [
    ! Test: Cannot abort committed migration
    sample-transformation
    "normalize"
    sample-source
    sample-target
    sample-affected-queries
    15
    start-migration
    advance-to-shadow
    advance-to-commit
    "Changed my mind" abort-migration
    errors>> empty? not
] unit-test

! ============================================================
! Global Registry Tests
! ============================================================

{ t } [
    ! Test: Migrations are tracked in registry
    active-migrations get clear-assoc
    sample-transformation
    "normalize"
    sample-source
    sample-target
    sample-affected-queries
    create-migration drop
    list-migrations empty? not
] unit-test

{ t } [
    ! Test: Can retrieve migration by ID
    active-migrations get clear-assoc
    sample-transformation
    "normalize"
    sample-source
    sample-target
    sample-affected-queries
    create-migration
    id>> get-migration
    f = not
] unit-test

{ "shadow" } [
    ! Test: Can advance migration via public API
    active-migrations get clear-assoc
    sample-transformation
    "normalize"
    sample-source
    sample-target
    sample-affected-queries
    create-migration
    id>> advance-migration
    phase>> name>>
] unit-test

! ============================================================
! Configuration Tests
! ============================================================

{ 24 } [
    ! Test: Default announce duration is 24 hours
    default-migration-config announce-duration-hours>>
] unit-test

{ 7 } [
    ! Test: Default shadow duration is 7 days
    default-migration-config shadow-duration-days>>
] unit-test

{ f } [
    ! Test: Auto-commit is disabled by default
    default-migration-config auto-commit>>
] unit-test

{ t } [
    ! Test: Require zero errors by default
    default-migration-config require-zero-errors>>
] unit-test

! ============================================================
! End-to-End Scenario Test
! ============================================================

: run-full-migration-scenario ( -- success? )
    ! Clear registry
    active-migrations get clear-assoc

    ! Step 1: Start migration
    "Normalize customer_orders to 3NF"
    "normalize"
    { "order_id" "customer_id" "customer_name" "order_date" }
    { "orders" "customers" }
    { "SELECT * FROM customer_orders WHERE customer_id = ?" }
    create-migration :> state

    ! Verify announce phase
    state phase>> announce? not [ f ] [

        ! Step 2: Advance to shadow
        state id>> advance-migration :> state2
        state2 phase>> shadow? not [ f ] [

            ! Verify rewrite rules exist
            state2 rewrite-rules>> empty? [ f ] [

                ! Step 3: Simulate query execution
                "SELECT * FROM customer_orders WHERE customer_id = ?"
                state2 execute-with-migration :> result
                result "error" swap key? [ f ] [

                    ! Step 4: Advance to commit
                    state2 id>> advance-migration :> state3
                    state3 phase>> commit? not [ f ] [

                        ! Verify compat views removed
                        state3 compat-views>> empty? not [ f ] [

                            ! Step 5: Get final narrative
                            state3 id>> migration-status :> narrative
                            narrative "COMMIT" swap subseq?
                        ] if
                    ] if
                ] if
            ] if
        ] if
    ] if ;

{ t } [
    run-full-migration-scenario
] unit-test

! ============================================================
! Test Summary
! ============================================================

: run-migration-tests ( -- )
    "Running migration framework tests..." print
    "migration-tests" run-tests
    "Migration tests complete." print ;

MAIN: run-migration-tests
