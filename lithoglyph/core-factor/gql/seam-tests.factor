! SPDX-License-Identifier: PMPL-1.0-or-later
! Form.Runtime - Seam Tests
!
! End-to-end tests validating the pipeline:
! Parser -> Planner -> Executor -> Normalizer
!
! These tests verify that data flows correctly across component boundaries.

USING: accessors arrays assocs fdql fd-discovery io kernel math
namespaces sequences strings tools.test vectors ;

IN: seam-tests

! ============================================================
! Test Setup
! ============================================================

: reset-test-state ( -- )
    collections get clear-assoc ;

: setup-test-collection ( -- )
    reset-test-state
    ! Create a test collection with sample data
    "CREATE COLLECTION test_users" run-fdql drop
    ! Insert test documents
    V{
        H{ { "id" "u1" } { "name" "Alice" } { "dept" "Engineering" } { "salary" "100000" } }
        H{ { "id" "u2" } { "name" "Bob" } { "dept" "Engineering" } { "salary" "95000" } }
        H{ { "id" "u3" } { "name" "Carol" } { "dept" "Sales" } { "salary" "80000" } }
        H{ { "id" "u4" } { "name" "Dave" } { "dept" "Sales" } { "salary" "85000" } }
        H{ { "id" "u5" } { "name" "Eve" } { "dept" "Engineering" } { "salary" "110000" } }
    } "test_users" set-collection ;

! ============================================================
! Seam 1: Parser -> Planner
! ============================================================

! Test that parsed AST can be planned

{ t } [
    "SELECT * FROM users" parse-fdql
    fdql-select?
] unit-test

{ t } [
    "SELECT * FROM users" parse-fdql plan-query
    query-plan?
] unit-test

{ t } [
    "SELECT name, dept FROM users WHERE dept = Engineering" parse-fdql plan-query
    steps>> length 2 >=  ! At least project + scan
] unit-test

{ t } [
    "INSERT INTO users { name: Test }" parse-fdql plan-query
    steps>> first type>> "insert" =
] unit-test

! Test EXPLAIN produces plan

{ "ok" } [
    "EXPLAIN SELECT * FROM users" parse-fdql execute-fdql
    "status" swap at
] unit-test

{ t } [
    "EXPLAIN SELECT * FROM users" parse-fdql execute-fdql
    "plan" swap at
    "steps" swap at
    array?
] unit-test

! ============================================================
! Seam 2: Planner -> Executor
! ============================================================

! Test that planned queries execute correctly

{ "ok" } [
    setup-test-collection
    "SELECT * FROM test_users" run-fdql
    "status" swap at
] unit-test

{ 5 } [
    setup-test-collection
    "SELECT * FROM test_users" run-fdql
    "count" swap at
] unit-test

{ t } [
    setup-test-collection
    "SELECT * FROM test_users WHERE dept = Engineering" run-fdql
    "count" swap at 3 =
] unit-test

! Test INSERT -> SELECT round trip

{ t } [
    setup-test-collection
    "INSERT INTO test_users { name: Frank, dept: HR }" run-fdql drop
    "SELECT * FROM test_users WHERE dept = HR" run-fdql
    "count" swap at 1 =
] unit-test

! Test UPDATE -> SELECT verification

{ t } [
    setup-test-collection
    "UPDATE test_users SET salary = 120000 WHERE name = Alice" run-fdql drop
    "SELECT salary FROM test_users WHERE name = Alice" run-fdql
    "rows" swap at first "salary" swap at "120000" =
] unit-test

! Test DELETE -> SELECT verification

{ t } [
    setup-test-collection
    "DELETE FROM test_users WHERE dept = Sales" run-fdql drop
    "SELECT * FROM test_users" run-fdql
    "count" swap at 3 =  ! 5 - 2 Sales employees = 3
] unit-test

! ============================================================
! Seam 3: Executor -> Normalizer (FD Discovery)
! ============================================================

! Test that executor results can be fed to FD discovery

{ t } [
    setup-test-collection
    "test_users" get-collection :> data
    data length 5 =
] unit-test

{ t } [
    setup-test-collection
    "test_users" get-collection
    default-fd-config run-dfd
    fd-discovery-result?
] unit-test

! Test FD discovery on executor results

{ t } [
    reset-test-state
    ! Create collection with clear FD: employee_id -> name, dept
    V{
        H{ { "emp_id" "E1" } { "name" "Alice" } { "dept" "Eng" } }
        H{ { "emp_id" "E2" } { "name" "Bob" } { "dept" "Eng" } }
        H{ { "emp_id" "E3" } { "name" "Carol" } { "dept" "Sales" } }
        H{ { "emp_id" "E1" } { "name" "Alice" } { "dept" "Eng" } }  ! Duplicate to confirm FD
    } "employees" set-collection
    "employees" get-collection
    default-fd-config run-dfd
    dependencies>> empty? not  ! Should find emp_id -> name, dept
] unit-test

! ============================================================
! Seam 4: Full Round Trip
! ============================================================

! Test complete pipeline: Parse -> Plan -> Execute -> Discover -> Analyze

: run-full-pipeline-test ( -- success? )
    reset-test-state

    ! Step 1: Create collection
    "CREATE COLLECTION orders" run-fdql
    "status" swap at "ok" = not [ f ] [

        ! Step 2: Insert data with clear FD pattern
        V{
            H{ { "order_id" "O1" } { "customer_id" "C1" } { "customer_name" "Acme Corp" } { "total" "1000" } }
            H{ { "order_id" "O2" } { "customer_id" "C1" } { "customer_name" "Acme Corp" } { "total" "2000" } }
            H{ { "order_id" "O3" } { "customer_id" "C2" } { "customer_name" "Beta Inc" } { "total" "1500" } }
            H{ { "order_id" "O4" } { "customer_id" "C2" } { "customer_name" "Beta Inc" } { "total" "3000" } }
        } "orders" set-collection

        ! Step 3: Query and verify
        "SELECT * FROM orders" run-fdql
        "count" swap at 4 = not [ f ] [

            ! Step 4: Run FD discovery
            "orders" get-collection
            default-fd-config run-dfd :> fd-result

            ! Step 5: Check normal form
            fd-result dependencies>> :> fds
            { { "order_id" } } :> keys  ! order_id is the key
            fds keys analyze-normal-form :> nf-analysis

            ! Step 6: Verify we can generate narrative
            fd-result result>narrative length 0 >

        ] if
    ] if ;

{ t } [
    run-full-pipeline-test
] unit-test

! ============================================================
! Seam 5: EXPLAIN -> Execution Correlation
! ============================================================

! Test that EXPLAIN ANALYZE produces timing data

{ t } [
    setup-test-collection
    "EXPLAIN ANALYZE SELECT * FROM test_users" run-fdql
    "execution_time_ms" swap key?
] unit-test

{ t } [
    setup-test-collection
    "EXPLAIN ANALYZE SELECT * FROM test_users" run-fdql
    "actual_result" swap at
    "count" swap at 5 =
] unit-test

! Test EXPLAIN VERBOSE produces readable plan

{ t } [
    setup-test-collection
    "EXPLAIN VERBOSE SELECT * FROM test_users WHERE dept = Engineering" run-fdql
    "verbose_plan" swap at
    "Seq Scan" swap subseq?
] unit-test

! ============================================================
! Seam 6: Introspection -> FD Discovery
! ============================================================

! Test that introspection data can be used for FD discovery context

{ t } [
    setup-test-collection
    "INTROSPECT COLLECTIONS" run-fdql
    "collections" swap at
    "test_users" swap member?
] unit-test

{ "ok" } [
    setup-test-collection
    "INTROSPECT SCHEMA" run-fdql
    "status" swap at
] unit-test

! ============================================================
! Error Propagation Tests
! ============================================================

! Test that parser errors don't crash planner

{ t } [
    [ "SELECTT * FROM users" parse-fdql ] [ fdql-parse-error? ] recover
] unit-test

! Test that missing collection returns error gracefully

{ "ok" } [
    reset-test-state
    "SELECT * FROM nonexistent" run-fdql
    "status" swap at
    ! Should still return ok, just with empty results
] unit-test

{ 0 } [
    reset-test-state
    "SELECT * FROM nonexistent" run-fdql
    "count" swap at
] unit-test

! ============================================================
! Stress Test: Large Dataset
! ============================================================

: create-large-dataset ( n -- )
    reset-test-state
    V{ } clone swap [
        [ ] dip  ! ( accum i )
        H{ } clone
            over "id" number>string "U" prepend "id" pick set-at
            over 2 mod 0 = [ "Eng" ] [ "Sales" ] if "dept" pick set-at
            over 50000 + number>string "salary" pick set-at
        nip swap push
    ] each-integer
    "large_users" set-collection ;

{ t } [
    1000 create-large-dataset
    "SELECT * FROM large_users" run-fdql
    "count" swap at 1000 =
] unit-test

{ t } [
    1000 create-large-dataset
    "SELECT * FROM large_users WHERE dept = Eng" run-fdql
    "count" swap at 500 =
] unit-test

{ t } [
    1000 create-large-dataset
    "large_users" get-collection
    fd-discovery-config new
        100 >>sample-size  ! Sample for speed
        0.95 >>confidence-threshold
        "dfd" >>algorithm
        3 >>max-lhs-size
    run-dfd
    fd-discovery-result?
] unit-test

! ============================================================
! Test Summary
! ============================================================

: run-seam-tests ( -- )
    "Running seam tests (Parser -> Planner -> Executor -> Normalizer)..." print
    "seam-tests" run-tests
    "Seam tests complete." print ;

MAIN: run-seam-tests
