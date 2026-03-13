! SPDX-License-Identifier: PMPL-1.0-or-later
! Form.Runtime - Performance Benchmarks
!
! Benchmarks for Parser, Planner, Executor, and Normalizer components.
! Used for establishing baseline performance and detecting regressions.

USING: accessors arrays assocs calendar gql fd-discovery formatting
io kernel locals math math.parser math.statistics namespaces random
sequences system vectors ;

IN: benchmarks

! ============================================================
! Timing Utilities
! ============================================================

: measure-ns ( quot -- result nanoseconds )
    nano-count [ call ] dip nano-count swap - ; inline

: measure-ms ( quot -- result milliseconds )
    measure-ns 1000000.0 / ; inline

: average-time-ms ( quot n -- avg-ms )
    [ measure-ms nip ] curry replicate mean ; inline

: benchmark-with-warmup ( quot warmup-runs bench-runs -- avg-ms )
    [ 2dup [ drop call drop ] curry times ] dip
    average-time-ms ; inline

! ============================================================
! Test Data Generation
! ============================================================

: random-string ( len -- str )
    [ CHAR: a CHAR: z [a..b] random ] "" replicate-as ;

: random-document ( -- doc )
    H{ } clone
    10 random-string "id" pick set-at
    8 random-string "name" pick set-at
    { "Engineering" "Sales" "Marketing" "HR" "Finance" } random "dept" pick set-at
    50000 100000 [a..b] random number>string "salary" pick set-at
    1990 2000 [a..b] random number>string "start_year" pick set-at ;

:: generate-test-data ( n -- data )
    V{ } clone :> data
    n [ random-document data push ] times
    data ;

:: setup-benchmark-collection ( name n -- )
    collections get clear-assoc
    n generate-test-data name set-collection ;

! ============================================================
! Parser Benchmarks
! ============================================================

: bench-parse-simple-select ( -- ms )
    [ "SELECT * FROM users" parse-gql drop ] 100 average-time-ms ;

: bench-parse-complex-select ( -- ms )
    [ "SELECT name, dept, salary FROM employees WHERE dept = Engineering LIMIT 100 OFFSET 10" parse-gql drop ]
    100 average-time-ms ;

: bench-parse-insert ( -- ms )
    [ "INSERT INTO users { name: Test, dept: HR }" parse-gql drop ]
    100 average-time-ms ;

: bench-parse-explain ( -- ms )
    [ "EXPLAIN ANALYZE VERBOSE SELECT * FROM users WHERE salary > 50000" parse-gql drop ]
    100 average-time-ms ;

: run-parser-benchmarks ( -- )
    "=== Parser Benchmarks ===" print
    bench-parse-simple-select "Simple SELECT: %.3f ms" sprintf print
    bench-parse-complex-select "Complex SELECT: %.3f ms" sprintf print
    bench-parse-insert "INSERT: %.3f ms" sprintf print
    bench-parse-explain "EXPLAIN ANALYZE: %.3f ms" sprintf print
    "" print ;

! ============================================================
! Planner Benchmarks
! ============================================================

: bench-plan-simple-select ( -- ms )
    "SELECT * FROM users" parse-gql :> ast
    [ ast plan-query drop ] 100 average-time-ms ;

: bench-plan-complex-select ( -- ms )
    "SELECT name, dept FROM users WHERE dept = Engineering LIMIT 50" parse-gql :> ast
    [ ast plan-query drop ] 100 average-time-ms ;

: bench-plan-insert ( -- ms )
    "INSERT INTO users { name: Test }" parse-gql :> ast
    [ ast plan-query drop ] 100 average-time-ms ;

: run-planner-benchmarks ( -- )
    "=== Planner Benchmarks ===" print
    bench-plan-simple-select "Simple SELECT plan: %.3f ms" sprintf print
    bench-plan-complex-select "Complex SELECT plan: %.3f ms" sprintf print
    bench-plan-insert "INSERT plan: %.3f ms" sprintf print
    "" print ;

! ============================================================
! Executor Benchmarks
! ============================================================

:: bench-executor-select ( n -- ms )
    "bench_select" n setup-benchmark-collection
    [ "SELECT * FROM bench_select" run-gql drop ]
    10 average-time-ms ;

:: bench-executor-select-filtered ( n -- ms )
    "bench_filter" n setup-benchmark-collection
    [ "SELECT * FROM bench_filter WHERE dept = Engineering" run-gql drop ]
    10 average-time-ms ;

:: bench-executor-insert ( n -- ms )
    "bench_insert" 0 setup-benchmark-collection
    [
        n [
            random-document :> doc
            "INSERT INTO bench_insert { name: X }" run-gql drop
        ] times
    ] measure-ms nip ;

:: bench-executor-update ( n -- ms )
    "bench_update" n setup-benchmark-collection
    [ "UPDATE bench_update SET salary = 999999 WHERE dept = Engineering" run-gql drop ]
    10 average-time-ms ;

: run-executor-benchmarks ( -- )
    "=== Executor Benchmarks ===" print

    "SELECT (100 docs):" print
    100 bench-executor-select "  Full scan: %.3f ms" sprintf print
    100 bench-executor-select-filtered "  Filtered: %.3f ms" sprintf print

    "SELECT (1000 docs):" print
    1000 bench-executor-select "  Full scan: %.3f ms" sprintf print
    1000 bench-executor-select-filtered "  Filtered: %.3f ms" sprintf print

    "SELECT (10000 docs):" print
    10000 bench-executor-select "  Full scan: %.3f ms" sprintf print
    10000 bench-executor-select-filtered "  Filtered: %.3f ms" sprintf print

    "INSERT (100 docs):" print
    100 bench-executor-insert "  Batch: %.3f ms" sprintf print

    "UPDATE (1000 docs):" print
    1000 bench-executor-update "  Filtered update: %.3f ms" sprintf print

    "" print ;

! ============================================================
! FD Discovery Benchmarks
! ============================================================

:: bench-fd-discovery ( n -- ms )
    "bench_fd" n setup-benchmark-collection
    "bench_fd" get-collection :> data
    [
        data
        fd-discovery-config new
            1000 >>sample-size
            0.95 >>confidence-threshold
            "dfd" >>algorithm
            3 >>max-lhs-size
        run-dfd drop
    ] measure-ms nip ;

:: bench-fd-discovery-full ( n -- ms )
    "bench_fd_full" n setup-benchmark-collection
    "bench_fd_full" get-collection :> data
    [
        data
        fd-discovery-config new
            n >>sample-size  ! Full dataset
            0.95 >>confidence-threshold
            "dfd" >>algorithm
            4 >>max-lhs-size  ! Deeper search
        run-dfd drop
    ] measure-ms nip ;

: run-fd-discovery-benchmarks ( -- )
    "=== FD Discovery Benchmarks ===" print

    "DFD (sampled, max-lhs=3):" print
    100 bench-fd-discovery "  100 docs: %.3f ms" sprintf print
    500 bench-fd-discovery "  500 docs: %.3f ms" sprintf print
    1000 bench-fd-discovery "  1000 docs: %.3f ms" sprintf print

    "DFD (full, max-lhs=4):" print
    100 bench-fd-discovery-full "  100 docs: %.3f ms" sprintf print
    200 bench-fd-discovery-full "  200 docs: %.3f ms" sprintf print

    "" print ;

! ============================================================
! Normal Form Analysis Benchmarks
! ============================================================

:: bench-nf-analysis ( num-fds -- ms )
    ! Generate synthetic FDs
    V{ } clone :> fds
    num-fds [
        functional-dependency new
            1array "attr" swap number>string append >>determinant
            { "dependent" } >>dependent
            1.0 >>confidence
        fds push
    ] each-integer

    { { "id" } } :> keys  ! Simple key

    [ fds keys analyze-normal-form drop ]
    100 average-time-ms ;

: run-nf-analysis-benchmarks ( -- )
    "=== Normal Form Analysis Benchmarks ===" print
    5 bench-nf-analysis "5 FDs: %.3f ms" sprintf print
    10 bench-nf-analysis "10 FDs: %.3f ms" sprintf print
    20 bench-nf-analysis "20 FDs: %.3f ms" sprintf print
    50 bench-nf-analysis "50 FDs: %.3f ms" sprintf print
    "" print ;

! ============================================================
! End-to-End Pipeline Benchmarks
! ============================================================

:: bench-full-pipeline ( n -- ms )
    "bench_pipeline" n setup-benchmark-collection
    [
        ! Parse
        "SELECT * FROM bench_pipeline WHERE dept = Engineering" parse-gql :> ast
        ! Plan
        ast plan-query :> plan
        ! Execute
        ast execute-gql :> result
        ! Discover FDs
        "bench_pipeline" get-collection
        fd-discovery-config new
            100 >>sample-size
            0.95 >>confidence-threshold
            "dfd" >>algorithm
            3 >>max-lhs-size
        run-dfd :> fds
        ! Analyze normal form
        fds dependencies>> { { "id" } } analyze-normal-form drop
    ] measure-ms nip ;

: run-pipeline-benchmarks ( -- )
    "=== Full Pipeline Benchmarks ===" print
    100 bench-full-pipeline "100 docs: %.3f ms" sprintf print
    500 bench-full-pipeline "500 docs: %.3f ms" sprintf print
    1000 bench-full-pipeline "1000 docs: %.3f ms" sprintf print
    "" print ;

! ============================================================
! Memory Usage Estimation
! ============================================================

:: estimate-collection-memory ( n -- bytes )
    ! Rough estimate: each document ~200 bytes
    n 200 * ;

: run-memory-estimates ( -- )
    "=== Memory Estimates ===" print
    100 estimate-collection-memory "100 docs: ~%d bytes" sprintf print
    1000 estimate-collection-memory "1000 docs: ~%d bytes" sprintf print
    10000 estimate-collection-memory "10000 docs: ~%d bytes" sprintf print
    100000 estimate-collection-memory "100000 docs: ~%d bytes (~%d MB)" [ 1048576 / ] keep 2array vsprintf print
    "" print ;

! ============================================================
! Benchmark Report Generation
! ============================================================

: generate-benchmark-report ( -- )
    "Lith Performance Benchmark Report" print
    "=" 50 <repetition> concat print
    now timestamp>rfc3339 "Generated: %s" sprintf print
    "" print

    run-parser-benchmarks
    run-planner-benchmarks
    run-executor-benchmarks
    run-fd-discovery-benchmarks
    run-nf-analysis-benchmarks
    run-pipeline-benchmarks
    run-memory-estimates

    "=" 50 <repetition> concat print
    "Benchmark complete." print ;

! ============================================================
! Quick Benchmark (for CI)
! ============================================================

: quick-benchmark ( -- success? )
    ! Run abbreviated benchmarks, return false if any exceed thresholds
    t :> passed!

    ! Parser should be < 1ms
    bench-parse-simple-select 1.0 > [ f passed! ] when

    ! SELECT 100 docs should be < 10ms
    100 bench-executor-select 10.0 > [ f passed! ] when

    ! FD discovery on 100 docs should be < 100ms
    100 bench-fd-discovery 100.0 > [ f passed! ] when

    passed ;

! ============================================================
! Main Entry Point
! ============================================================

: run-benchmarks ( -- )
    generate-benchmark-report ;

MAIN: run-benchmarks
