! SPDX-License-Identifier: PMPL-1.0-or-later
! Form.Normalizer - Three-Phase Migration Framework
!
! Implements the Announce -> Shadow -> Commit migration pattern
! for schema normalization/denormalization changes.
! Decision D-NORM-005: Three-phase migration with query rewriting.

USING: accessors arrays assocs calendar calendar.format combinators
continuations hash-sets io kernel math math.order sequences sets
sorting strings vectors ;

IN: migration

! ============================================================
! Migration Phase Enumeration
! ============================================================

TUPLE: migration-phase name description ;

: <announce> ( -- phase )
    migration-phase new
        "announce" >>name
        "Proposal journaled, affected queries identified" >>description ;

: <shadow> ( -- phase )
    migration-phase new
        "shadow" >>name
        "Both schemas exist, queries rewritten to use new schema" >>description ;

: <commit> ( -- phase )
    migration-phase new
        "commit" >>name
        "Old schema removed, migration complete" >>description ;

! Phase predicates
: announce? ( phase -- ? ) name>> "announce" = ;
: shadow? ( phase -- ? ) name>> "shadow" = ;
: commit? ( phase -- ? ) name>> "commit" = ;

! ============================================================
! Migration Configuration
! ============================================================

TUPLE: migration-config
    announce-duration-hours    ! Warning period before shadow (default: 24)
    shadow-duration-days       ! Compatibility period (default: 7)
    auto-commit                ! Auto-commit after shadow? (default: f)
    require-zero-errors ;      ! Must have 0 query errors to commit (default: t)

: default-migration-config ( -- config )
    migration-config new
        24 >>announce-duration-hours
        7 >>shadow-duration-days
        f >>auto-commit
        t >>require-zero-errors ;

! ============================================================
! Query Rewrite Rule
! ============================================================

TUPLE: rewrite-rule
    original-query      ! The original query pattern
    rewritten-query     ! The rewritten query for new schema
    bidirectional       ! Can queries be translated both directions?
    validation-status ; ! "untested" | "validated" | "failed"

: <rewrite-rule> ( original rewritten -- rule )
    rewrite-rule new
        swap >>original-query
        swap >>rewritten-query
        t >>bidirectional
        "untested" >>validation-status ;

! ============================================================
! Compatibility View
! ============================================================

TUPLE: compat-view
    name                ! View name (usually old table name)
    definition          ! View definition (query against new schema)
    created-at          ! When view was created
    access-count ;      ! Number of times accessed during shadow

: <compat-view> ( name definition -- view )
    compat-view new
        swap >>name
        swap >>definition
        now timestamp>ymd >>created-at
        0 >>access-count ;

! ============================================================
! Migration State
! ============================================================

TUPLE: migration-state
    id                   ! Unique migration ID
    phase                ! Current migration-phase
    transformation       ! The normalization/denormalization step
    transformation-type  ! "normalize" | "denormalize"
    source-schema        ! Original schema name(s)
    target-schema        ! New schema name(s)
    affected-queries     ! List of query patterns affected
    rewrite-rules        ! List of rewrite-rule
    compat-views         ! List of compat-view
    journal-entry        ! Journal sequence number
    config               ! migration-config
    started-at           ! Migration start timestamp
    phase-entered-at     ! When current phase was entered
    errors               ! List of errors encountered
    narrative ;          ! Human-readable explanation

! ============================================================
! Migration Lifecycle
! ============================================================

! Start a new migration in announce phase
:: start-migration ( transformation type source target affected journal-entry -- state )
    migration-state new
        journal-entry >>id
        <announce> >>phase
        transformation >>transformation
        type >>transformation-type
        source >>source-schema
        target >>target-schema
        affected >>affected-queries
        V{ } clone >>rewrite-rules
        V{ } clone >>compat-views
        journal-entry >>journal-entry
        default-migration-config >>config
        now timestamp>ymd >>started-at
        now timestamp>ymd >>phase-entered-at
        V{ } clone >>errors
        "MIGRATION STARTED\n"
        "Type: " type append "\n" append
        "Source: " source >string append "\n" append
        "Target: " target >string append "\n" append
        "Affected queries: " affected length number>string append "\n" append
        "Journal entry: #" journal-entry number>string append
        append >>narrative ;

! Check if migration can advance to next phase
:: can-advance? ( state -- ? reason )
    state phase>>
    {
        { [ dup announce? ] [
            drop
            ! Can advance if announce duration elapsed
            ! For PoC, always allow
            t "Announce period complete"
        ] }
        { [ dup shadow? ] [
            drop
            ! Can advance if shadow duration elapsed and no errors
            state config>> require-zero-errors>> [
                state errors>> empty? [
                    t "Shadow period complete with zero errors"
                ] [
                    f "Errors encountered during shadow phase"
                ] if
            ] [
                t "Shadow period complete"
            ] if
        ] }
        { [ dup commit? ] [
            drop f "Migration already complete"
        ] }
    } cond ;

! Generate rewrite rules for affected queries
:: generate-rewrite-rules ( state -- rules )
    state affected-queries>> [| query |
        ! Simplified: just create placeholder rules
        ! Real implementation would analyze query and generate rewrites
        query
        query " /* rewritten for " state target-schema>> >string append " */" append
        <rewrite-rule>
    ] map ;

! Create compatibility views for shadow phase
:: create-compat-views ( state -- views )
    state transformation-type>> "normalize" = [
        ! For normalization: create view with old schema name that JOINs new tables
        state source-schema>> >string
        "SELECT * FROM " state target-schema>> >string append
        " /* compatibility view */"
        append
        <compat-view> 1array
    ] [
        ! For denormalization: create views that extract from merged table
        V{ } clone
    ] if ;

! Advance migration to shadow phase
:: advance-to-shadow ( state -- state' )
    state phase>> announce? [
        state generate-rewrite-rules :> rules
        state create-compat-views :> views

        state
            <shadow> >>phase
            now timestamp>ymd >>phase-entered-at
            rules >>rewrite-rules
            views >>compat-views
            dup narrative>>
            "\n\nADVANCED TO SHADOW PHASE\n"
            "Rewrite rules generated: " rules length number>string append "\n" append
            "Compatibility views created: " views length number>string append
            append append >>narrative
    ] [
        state "ERROR: Cannot advance to shadow from " state phase>> name>> append
        suffix >>errors
    ] if ;

! Advance migration to commit phase
:: advance-to-commit ( state -- state' )
    state phase>> shadow? [
        state can-advance? :> ( ok? reason )
        ok? [
            state
                <commit> >>phase
                now timestamp>ymd >>phase-entered-at
                V{ } clone >>compat-views  ! Views removed at commit
                dup narrative>>
                "\n\nMIGRATION COMMITTED\n"
                "Reason: " reason append "\n" append
                "Compatibility views removed.\n" append
                "Old schema can now be dropped." append
                append append >>narrative
        ] [
            state "ERROR: Cannot commit - " reason append
            suffix >>errors
        ] if
    ] [
        state "ERROR: Cannot commit from " state phase>> name>> append
        suffix >>errors
    ] if ;

! Abort migration (rollback to original state)
:: abort-migration ( state reason -- state' )
    state phase>> commit? [
        state "ERROR: Cannot abort committed migration"
        suffix >>errors
    ] [
        state
            dup narrative>>
            "\n\nMIGRATION ABORTED\n"
            "Reason: " reason append "\n" append
            "Schema changes rolled back." append
            append append >>narrative
            ! Note: actual rollback would be handled by the runtime
    ] if ;

! ============================================================
! Query Execution During Migration
! ============================================================

! Execute query with migration awareness
:: execute-with-migration ( query state -- result )
    state phase>>
    {
        { [ dup announce? ] [
            drop
            ! During announce: execute against old schema, log affected
            H{
                { "executed" query }
                { "schema" "old" }
                { "warning" "Migration pending - query may need update" }
            }
        ] }
        { [ dup shadow? ] [
            drop
            ! During shadow: try new schema, fallback to compat view
            state rewrite-rules>> [ original-query>> query = ] find nip [
                rewritten-query>> :> rewritten
                H{
                    { "executed" rewritten }
                    { "schema" "new (rewritten)" }
                    { "original" query }
                }
            ] [
                ! No rewrite rule, use compat view
                H{
                    { "executed" query }
                    { "schema" "compatibility view" }
                    { "warning" "Using compatibility view - update query" }
                }
            ] if*
        ] }
        { [ dup commit? ] [
            drop
            ! After commit: must use new schema
            state rewrite-rules>> [ original-query>> query = ] find nip [
                rewritten-query>> :> rewritten
                H{
                    { "executed" rewritten }
                    { "schema" "new" }
                }
            ] [
                H{
                    { "error" "Query not compatible with new schema" }
                    { "query" query }
                    { "suggestion" "Update query for new schema" }
                }
            ] if*
        ] }
    } cond ;

! ============================================================
! Narrative Generation
! ============================================================

! Generate full migration narrative
:: migration>narrative ( state -- string )
    "THREE-PHASE MIGRATION REPORT\n" :> out!
    "=" 60 <repetition> concat "\n" append out swap append out!

    "\nMigration ID: #" state id>> number>string append "\n" append
    out swap append out!

    "Current Phase: " state phase>> name>> append
    " - " state phase>> description>> append "\n" append
    out swap append out!

    "\nTransformation: " state transformation-type>> append "\n" append
    out swap append out!

    "Source Schema: " state source-schema>> >string append "\n" append
    out swap append out!

    "Target Schema: " state target-schema>> >string append "\n" append
    out swap append out!

    "\nTimeline:\n" out swap append out!
    "  Started: " state started-at>> append "\n" append
    out swap append out!
    "  Phase entered: " state phase-entered-at>> append "\n" append
    out swap append out!

    "\nAffected Queries: " state affected-queries>> length number>string append "\n"
    append out swap append out!

    state phase>> shadow? state phase>> commit? or [
        "\nRewrite Rules: " state rewrite-rules>> length number>string append "\n"
        append out swap append out!
        state rewrite-rules>> [| rule |
            "  " rule original-query>> append " -> " append
            rule rewritten-query>> append
            " [" rule validation-status>> append "]\n" append
            out swap append out!
        ] each
    ] when

    state phase>> shadow? [
        "\nCompatibility Views: " state compat-views>> length number>string append "\n"
        append out swap append out!
        state compat-views>> [| view |
            "  " view name>> append " (accessed " append
            view access-count>> number>string append " times)\n" append
            out swap append out!
        ] each
    ] when

    state errors>> empty? not [
        "\nERRORS:\n" out swap append out!
        state errors>> [
            "  - " swap append "\n" append
            out swap append out!
        ] each
    ] when

    "\n" out swap append out!
    "-" 60 <repetition> concat "\n" append out swap append out!
    "Full Narrative:\n" out swap append out!
    state narrative>> out swap append out!

    out ;

! ============================================================
! FQL Integration
! ============================================================

TUPLE: migrate-stmt
    action           ! "start" | "advance" | "abort" | "status"
    migration-id     ! For existing migrations
    transformation   ! For start action
    type             ! "normalize" | "denormalize"
    source           ! Source schema
    target           ! Target schema
    reason ;         ! For abort action

! Parse MIGRATE statement
: parse-migrate ( tokens -- tokens' ast )
    migrate-stmt new swap ;

! Execute MIGRATE statement
:: execute-migrate ( stmt migrations -- result )
    stmt action>>
    {
        { "start" [
            stmt transformation>>
            stmt type>>
            stmt source>>
            stmt target>>
            { } ! affected queries would be detected
            migrations length 1 +
            start-migration :> new-state
            new-state new-state id>> migrations set-at
            H{
                { "status" "started" }
                { "migration-id" new-state id>> }
                { "phase" new-state phase>> name>> }
            }
        ] }
        { "advance" [
            stmt migration-id>> migrations at [| state |
                state phase>> announce? [
                    state advance-to-shadow :> new-state
                    new-state stmt migration-id>> migrations set-at
                    H{
                        { "status" "advanced" }
                        { "phase" new-state phase>> name>> }
                    }
                ] [
                    state phase>> shadow? [
                        state advance-to-commit :> new-state
                        new-state stmt migration-id>> migrations set-at
                        H{
                            { "status" "committed" }
                            { "phase" new-state phase>> name>> }
                        }
                    ] [
                        H{ { "error" "Migration already complete" } }
                    ] if
                ] if
            ] [
                H{ { "error" "Migration not found" } }
            ] if*
        ] }
        { "abort" [
            stmt migration-id>> migrations at [| state |
                state stmt reason>> abort-migration :> new-state
                new-state stmt migration-id>> migrations set-at
                H{
                    { "status" "aborted" }
                    { "reason" stmt reason>> }
                }
            ] [
                H{ { "error" "Migration not found" } }
            ] if*
        ] }
        { "status" [
            stmt migration-id>> migrations at [| state |
                H{
                    { "migration-id" state id>> }
                    { "phase" state phase>> name>> }
                    { "type" state transformation-type>> }
                    { "errors" state errors>> length }
                    { "narrative" state migration>narrative }
                }
            ] [
                H{ { "error" "Migration not found" } }
            ] if*
        ] }
        [ drop H{ { "error" "Unknown migrate action" } } ]
    } case ;

! ============================================================
! Public API
! ============================================================

! Global migration registry (for PoC)
SYMBOL: active-migrations
active-migrations [ H{ } clone ] initialize

: list-migrations ( -- migrations )
    active-migrations get ;

: get-migration ( id -- state/f )
    active-migrations get at ;

: create-migration ( transformation type source target affected -- state )
    active-migrations get length 1 +
    start-migration
    dup id>> active-migrations get set-at ;

: advance-migration ( id -- state/f )
    get-migration [
        dup phase>> announce? [
            advance-to-shadow
        ] [
            dup phase>> shadow? [
                advance-to-commit
            ] [ ] if
        ] if
        dup id>> active-migrations get set-at
    ] [ f ] if* ;

: cancel-migration ( id reason -- state/f )
    swap get-migration [
        swap abort-migration
        dup id>> active-migrations get set-at
    ] [ drop f ] if* ;

: migration-status ( id -- narrative/f )
    get-migration [ migration>narrative ] [ f ] if* ;
