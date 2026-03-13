! SPDX-License-Identifier: PMPL-1.0-or-later
! Form.Runtime - GQL Parser and Executor
!
! GQL (Glyph Query Language) - Carving queries into stone-carved data.
! Part of Lithoglyph: Stone-carved data for the ages.

USING: accessors arrays assocs combinators combinators.short-circuit
continuations formatting generalizations io json kernel locals math
math.parser peg peg.ebnf random sequences splitting storage-backend
strings system unicode vectors ;

IN: gql

! ============================================================
! AST Node Types
! ============================================================

TUPLE: gql-insert collection document provenance ;
TUPLE: gql-select fields collection where-clause edge-clause limit-clause with-provenance? ;
TUPLE: gql-update collection assignments where-clause provenance ;
TUPLE: gql-delete collection where-clause provenance ;
TUPLE: gql-create collection fields schema ;
TUPLE: gql-drop collection provenance ;
TUPLE: gql-explain inner-stmt analyze? verbose? ;
TUPLE: gql-introspect target arg ;

TUPLE: edge-clause type direction depth where ;
TUPLE: where-clause expression ;
TUPLE: limit-clause limit offset ;

TUPLE: comparison field op value ;
TUPLE: binary-expr left op right ;

! ============================================================
! Tokenizer
! ============================================================

: skip-whitespace ( str -- str' )
    [ " \t\n\r" member? not ] find drop "" or ;

: keyword? ( str -- ? )
    >upper {
        "SELECT" "FROM" "WHERE" "INSERT" "INTO" "UPDATE"
        "DELETE" "SET" "CREATE" "DROP" "COLLECTION"
        "WITH" "PROVENANCE" "LIMIT" "OFFSET"
        "TRAVERSE" "OUTBOUND" "INBOUND" "ANY" "DEPTH"
        "EXPLAIN" "INTROSPECT" "SCHEMA" "CONSTRAINTS"
        "JOURNAL" "SINCE" "COLLECTIONS"
        "AND" "OR" "NOT" "NULL" "TRUE" "FALSE"
        "STRING" "INTEGER" "FLOAT" "BOOLEAN" "TIMESTAMP"
        "JSON" "PROMPT_SCORE" "UNIQUE" "CHECK" "REFERENCES"
        "LIKE" "IN" "CONTAINS"
    } member? ;

: split-tokens ( str -- tokens )
    ! Simple tokenizer - splits on whitespace and punctuation
    " \t\n\r" split harvest
    [ "," = not ] filter ;

! ============================================================
! Parser Combinators (Simplified)
! ============================================================

ERROR: gql-parse-error message position ;

: peek-token ( tokens -- token/f )
    dup empty? [ drop f ] [ first ] if ;

: consume-token ( tokens -- tokens' token )
    unclip-slice ;  ! Returns ( rest first ) = ( tokens' token ), token on top

: expect-token ( tokens expected -- tokens' )
    over peek-token              ! ( tokens expected token )
    swap >upper swap >upper      ! ( tokens EXPECTED TOKEN )
    over = [                     ! ( tokens EXPECTED ) if match
        drop consume-token drop  ! ( tokens' )
    ] [
        "Expected '" "'" surround gql-parse-error
    ] if ;

: try-consume ( tokens expected -- tokens' matched? )
    over peek-token                  ! ( tokens expected actual/f )
    dup [
        ! Have a token - check if it matches
        swap >upper swap >upper      ! ( tokens EXPECTED ACTUAL )
        over over =                  ! ( tokens EXPECTED ACTUAL match? )
        [
            2drop                    ! ( tokens )
            unclip-slice drop        ! ( tokens' )
            t                        ! ( tokens' t )
        ] [
            2drop                    ! ( tokens )
            f                        ! ( tokens f )
        ] if
    ] [
        ! No token
        drop drop f                  ! ( tokens f )
    ] if ;

! ============================================================
! Parse Primitives
! ============================================================

: parse-identifier ( tokens -- tokens' identifier )
    consume-token
    dup keyword? [ "Unexpected keyword" gql-parse-error ] when ;

: parse-json-value ( tokens -- tokens' value )
    ! Simplified: just consume until end of JSON
    consume-token
    dup "{" = [
        drop
        ! Parse JSON object
        H{ } clone
        [ over peek-token "}" = not ] [
            swap consume-token drop  ! key
            swap consume-token drop  ! :
            swap consume-token       ! value
            ! Would need full JSON parsing here
            2drop
        ] while
        swap consume-token drop  ! }
        swap
    ] [
        ! It's a simple value
        swap
    ] if ;

: parse-string-literal ( tokens -- tokens' string )
    consume-token
    ! Remove quotes if present
    dup first CHAR: " = [
        1 tail* dup length 1 - head*
    ] when ;

! ============================================================
! Parse Statements
! ============================================================

: parse-collection-name ( tokens -- tokens' name )
    parse-identifier ;

: parse-field-list ( tokens -- tokens' fields )
    ! Collect field names until we see "FROM"
    V{ } clone swap  ! ( accum tokens )
    [ dup peek-token "FROM" = not ] [
        consume-token           ! ( accum tokens' field )
        [ swap ] dip            ! ( tokens' accum field )
        suffix                  ! ( tokens' accum' )
        swap                    ! ( accum' tokens' )
        dup peek-token "," = [ consume-token drop ] when
    ] while
    swap >array ;  ! ( tokens' fields )

: parse-where-clause ( tokens -- tokens' where/f )
    "WHERE" try-consume [
        ! Parse expression: field op value
        parse-identifier              ! ( tokens' field )
        [ consume-token ] dip         ! ( tokens'' op field )
        [ consume-token ] dip         ! ( tokens''' value op field )
        swap rot                      ! ( tokens''' field op value )
        comparison boa                ! ( tokens''' comparison )
        where-clause boa              ! ( tokens''' where )
    ] [
        f
    ] if ;

:: parse-edge-clause ( tokens -- tokens' edge/f )
    tokens "TRAVERSE" try-consume :> ( tokens' matched? )
    matched? [
        tokens' parse-identifier :> ( tokens'' edge-type )
        tokens'' consume-token :> ( tokens''' dir-raw )
        dir-raw >upper :> direction
        tokens''' "DEPTH" try-consume :> ( tokens'''' has-depth? )
        has-depth? [
            tokens'''' consume-token string>number :> ( tokens''''' depth )
            tokens'''''
            edge-type direction depth f edge-clause boa
        ] [
            tokens''''
            edge-type direction 1 f edge-clause boa
        ] if
    ] [
        tokens f
    ] if ;

:: parse-limit-clause ( tokens -- tokens' limit/f )
    tokens "LIMIT" try-consume :> ( tokens' matched? )
    matched? [
        tokens' consume-token string>number :> ( tokens'' limit )
        tokens'' "OFFSET" try-consume :> ( tokens''' has-offset? )
        has-offset? [
            tokens''' consume-token string>number :> ( tokens'''' offset )
            tokens''''
            limit offset limit-clause boa
        ] [
            tokens'''
            limit 0 limit-clause boa
        ] if
    ] [
        tokens f
    ] if ;

: parse-provenance-clause ( tokens -- tokens' prov/f )
    "WITH" try-consume [
        "PROVENANCE" expect-token
        ! Parse JSON object
        consume-token drop  ! {
        H{ } clone          ! placeholder
        [ over peek-token "}" = not ] [
            swap consume-token drop  ! skip tokens until }
        ] while
        swap consume-token drop  ! }
        swap
    ] [
        f
    ] if ;

! ============================================================
! Statement Parsers
! ============================================================

:: parse-insert ( tokens -- tokens' ast )
    tokens "INTO" expect-token parse-collection-name :> ( tokens' collection )
    ! Parse document body (simplified - just consume JSON)
    tokens' consume-token drop :> tokens''  ! consume {
    H{ } clone :> doc
    tokens'' [ dup peek-token "}" = not ] [
        consume-token drop
    ] while :> tokens'''
    tokens''' consume-token drop :> tokens''''  ! consume }
    ! Parse provenance
    tokens'''' parse-provenance-clause :> ( final-tokens prov )
    final-tokens
    collection doc prov gql-insert boa ;

: parse-select ( tokens -- tokens' ast )
    ! Parse "SELECT fields FROM collection" (simplified)
    ! Stack discipline: always keep tokens on top until the end

    ! Parse field list
    dup peek-token "*" = [
        consume-token drop { "*" }  ! ( tokens' { "*" } )
    ] [
        parse-field-list            ! ( tokens' fields )
    ] if
    ! Stack: ( tokens' fields )

    ! FROM collection
    swap                            ! ( fields tokens' )
    "FROM" expect-token             ! ( fields tokens'' )
    parse-collection-name           ! ( fields tokens'' collection )

    ! Build the gql-select tuple with defaults for optional clauses
    ! gql-select needs: ( fields collection where edge lim prov )
    ! Stack has: ( fields tokens'' collection )

    rot                             ! ( tokens'' collection fields )
    swap                            ! ( tokens'' fields collection )
    f f f f                         ! ( tokens'' fields collection f f f f )
    gql-select boa                 ! ( tokens'' ast )
    ;

:: parse-update ( tokens -- tokens' ast )
    tokens parse-collection-name :> ( tokens' collection )
    tokens' "SET" expect-token :> tokens''
    ! Parse assignments (simplified)
    V{ } clone :> assignments
    tokens'' [ dup peek-token "WHERE" = not ] [
        parse-identifier :> ( t field )
        t consume-token drop :> t'   ! =
        t' consume-token :> ( t'' value )
        field value 2array assignments push
        t'' dup peek-token "," = [ consume-token drop ] when
    ] while :> tokens'''
    tokens''' parse-where-clause :> ( tokens'''' where )
    tokens'''' parse-provenance-clause :> ( final-tokens prov )
    final-tokens
    collection assignments >array where prov gql-update boa ;

:: parse-delete ( tokens -- tokens' ast )
    tokens "FROM" expect-token parse-collection-name :> ( tokens' collection )
    tokens' parse-where-clause :> ( tokens'' where )
    tokens'' parse-provenance-clause :> ( final-tokens prov )
    final-tokens
    collection where prov gql-delete boa ;

:: parse-create ( tokens -- tokens' ast )
    tokens "COLLECTION" expect-token parse-collection-name :> ( tokens' collection )
    ! Parse optional field definitions
    tokens' peek-token "(" = [
        tokens' consume-token drop :> tokens''  ! consume (
        V{ } clone :> field-defs
        tokens'' [ dup peek-token ")" = not ] [
            parse-identifier :> ( t field )
            t consume-token :> ( t' type )
            field type 2array field-defs push
            t' dup peek-token "," = [ consume-token drop ] when
        ] while :> tokens'''
        tokens''' consume-token drop :> tokens''''  ! consume )
        tokens'''' field-defs >array
    ] [
        tokens' { }
    ] if :> ( tokens''''' fields )
    ! Parse optional schema
    tokens''''' "WITH" try-consume :> ( tokens'''''' has-schema? )
    has-schema? [
        tokens'''''' "SCHEMA" expect-token :> tokens'''''''
        tokens'''''''
        collection fields H{ } clone gql-create boa  ! placeholder schema
    ] [
        tokens''''''
        collection fields f gql-create boa
    ] if ;

:: parse-drop ( tokens -- tokens' ast )
    tokens "COLLECTION" expect-token parse-collection-name :> ( tokens' collection )
    tokens' parse-provenance-clause :> ( final-tokens prov )
    final-tokens
    collection prov gql-drop boa ;

:: parse-introspect-target ( tokens -- tokens' target arg )
    tokens consume-token :> ( tokens' target-raw )
    target-raw >upper :> target
    target "JOURNAL" = [
        tokens' "SINCE" try-consume :> ( tokens'' has-since? )
        has-since? [
            tokens'' consume-token string>number :> ( tokens''' since-val )
            tokens''' target since-val
        ] [
            tokens'' target 0
        ] if
    ] [
        target "SCHEMA" = target "CONSTRAINTS" = or [
            tokens' peek-token :> next-tok
            next-tok keyword? not next-tok and [
                tokens' parse-identifier :> ( tokens'' arg )
                tokens'' target arg
            ] [
                tokens' target f
            ] if
        ] [
            tokens' target f
        ] if
    ] if ;

: parse-introspect ( tokens -- tokens' ast )
    parse-introspect-target
    gql-introspect boa ;

DEFER: parse-statement

:: parse-explain ( tokens -- tokens' ast )
    ! Parse optional ANALYZE and VERBOSE flags
    f :> analyze?!
    f :> verbose?!
    tokens
    "ANALYZE" try-consume [ t analyze?! ] when
    "VERBOSE" try-consume [ t verbose?! ] when
    parse-statement :> ( tokens' inner )
    tokens'
    inner analyze? verbose? gql-explain boa ;

: parse-statement ( tokens -- tokens' ast )
    consume-token >upper {  ! After consume-token: ( tokens' token ), >upper: ( tokens' TOKEN )
        { "INSERT" [ parse-insert ] }
        { "SELECT" [ parse-select ] }
        { "UPDATE" [ parse-update ] }
        { "DELETE" [ parse-delete ] }
        { "CREATE" [ parse-create ] }
        { "DROP" [ parse-drop ] }
        { "EXPLAIN" [ parse-explain ] }
        { "INTROSPECT" [ parse-introspect ] }
        [ "Unknown statement type" gql-parse-error ]
    } case ;

! ============================================================
! Main Parser Entry Point
! ============================================================

: parse-gql ( str -- ast )
    ! Remove trailing semicolon if present
    dup ";" tail? [ but-last ] when
    ! Remove comments
    "\n" split
    [
        "--" split1 drop ! Remove line comments
        "" or
    ] map
    " " join
    ! Tokenize
    split-tokens
    ! Parse
    parse-statement
    ! Should have consumed all tokens
    nip ;

! ============================================================
! Query Plan Types
! ============================================================

TUPLE: plan-step
    type            ! scan | index-lookup | filter | project | sort | limit | join
    target          ! collection name or subplan
    cost            ! estimated cost
    rows            ! estimated rows
    rationale ;     ! why this step was chosen

TUPLE: query-plan
    steps           ! sequence of plan-steps
    total-cost      ! sum of costs
    provenance? ;   ! whether provenance is requested

! ============================================================
! Query Planner
! ============================================================

GENERIC: plan-query ( ast -- plan )

:: make-scan-step ( collection where -- step )
    plan-step new
        "scan" >>type
        collection >>target
        where [ 100 ] [ 1000 ] if >>cost   ! filter reduces cost estimate
        where [ 10 ] [ 100 ] if >>rows
        where [
            "Full collection scan with filter - consider adding index"
        ] [
            "Full collection scan - no filter specified"
        ] if >>rationale ;

:: make-project-step ( fields -- step )
    plan-step new
        "project" >>type
        fields >>target
        1 >>cost
        0 >>rows
        fields { "*" } = [
            "Selecting all fields"
        ] [
            fields length "Projecting %d field(s)" sprintf
        ] if >>rationale ;

:: make-limit-step ( lim -- step )
    plan-step new
        "limit" >>type
        lim >>target
        1 >>cost
        lim limit>> >>rows
        lim limit>> "Limiting to %d rows" sprintf >>rationale ;

:: make-edge-step ( edge -- step )
    plan-step new
        "traverse" >>type
        edge type>> >>target
        edge depth>> 10 * >>cost
        edge depth>> 5 * >>rows
        edge direction>> edge depth>> "Traversing %s edges to depth %d" sprintf >>rationale ;

M: gql-select plan-query
    query-plan new
        V{ } clone
        ! Add project step
        over fields>> make-project-step suffix
        ! Add scan step
        over collection>> over where-clause>> make-scan-step suffix
        ! Add edge traversal if present
        over edge-clause>> [ make-edge-step suffix ] when*
        ! Add limit if present
        over limit-clause>> [ make-limit-step suffix ] when*
        >>steps
        ! Calculate total cost
        dup steps>> [ cost>> ] map-sum >>total-cost
        ! Check provenance flag
        swap with-provenance?>> >>provenance? ;

M: gql-insert plan-query
    query-plan new
        V{ }
        over collection>>
        plan-step new
            "insert" >>type
            swap >>target
            10 >>cost
            1 >>rows
            "Insert document into collection" >>rationale
        suffix >>steps
        10 >>total-cost
        f >>provenance? ;

M: gql-update plan-query
    query-plan new
        V{ }
        over collection>> over where-clause>> make-scan-step suffix
        over collection>>
        plan-step new
            "update" >>type
            swap >>target
            50 >>cost
            0 >>rows
            "Update matching documents" >>rationale
        suffix >>steps
        60 >>total-cost
        f >>provenance? ;

M: gql-delete plan-query
    query-plan new
        V{ }
        over collection>> over where-clause>> make-scan-step suffix
        over collection>>
        plan-step new
            "delete" >>type
            swap >>target
            50 >>cost
            0 >>rows
            "Delete matching documents" >>rationale
        suffix >>steps
        60 >>total-cost
        f >>provenance? ;

M: gql-create plan-query
    query-plan new
        V{ }
        over collection>>
        plan-step new
            "create-collection" >>type
            swap >>target
            5 >>cost
            0 >>rows
            "Create new collection with schema" >>rationale
        suffix >>steps
        5 >>total-cost
        f >>provenance? ;

M: gql-drop plan-query
    query-plan new
        V{ }
        over collection>>
        plan-step new
            "drop-collection" >>type
            swap >>target
            5 >>cost
            0 >>rows
            "Drop collection and all documents" >>rationale
        suffix >>steps
        5 >>total-cost
        f >>provenance? ;

M: gql-explain plan-query
    inner-stmt>> plan-query ;

M: gql-introspect plan-query
    query-plan new
        V{ }
        over target>>
        plan-step new
            "introspect" >>type
            swap >>target
            1 >>cost
            0 >>rows
            "Read system metadata" >>rationale
        suffix >>steps
        1 >>total-cost
        f >>provenance? ;

! ============================================================
! Plan Rendering (for EXPLAIN)
! ============================================================

: step>assoc ( step -- assoc )
    {
        [ type>> "type" swap 2array ]
        [ target>> "target" swap 2array ]
        [ cost>> "cost" swap 2array ]
        [ rows>> "estimated_rows" swap 2array ]
        [ rationale>> "rationale" swap 2array ]
    } cleave 5 narray >hashtable ;

: plan>assoc ( plan -- assoc )
    {
        [ steps>> [ step>assoc ] map "steps" swap 2array ]
        [ total-cost>> "total_cost" swap 2array ]
        [ provenance?>> "with_provenance" swap 2array ]
    } cleave 3 narray >hashtable ;

! ============================================================
! Query Executor
! ============================================================

GENERIC: execute-gql ( ast -- result )

! Storage backend - uses pluggable storage (memory or bridge)
! See storage-backend.factor for backend implementations

: get-collection ( name -- docs )
    storage-get-collection ;

: set-collection ( docs name -- )
    storage-set-collection ;

: generate-doc-id ( -- id )
    32 [ CHAR: a CHAR: z [a..b] random ] "" replicate-as ;

:: execute-insert ( collection doc prov -- result )
    collection get-collection :> coll
    generate-doc-id :> doc-id
    doc-id "id" doc clone [ set-at ] keep :> doc'
    doc' coll push
    coll collection set-collection
    H{
        { "status" "ok" }
        { "document_id" doc-id }
        { "collection" collection }
    } clone
    prov [ "provenance" swap pick set-at ] when* ;

:: match-where? ( doc where -- ? )
    where [
        where expression>> :> comp
        comp field>> doc at :> actual
        comp value>> :> expected
        comp op>> {
            { "=" [ actual expected = ] }
            { "!=" [ actual expected = not ] }
            { ">" [ actual expected > ] }
            { "<" [ actual expected < ] }
            { ">=" [ actual expected >= ] }
            { "<=" [ actual expected <= ] }
            { "LIKE" [ actual expected swap subseq? ] }
            { "CONTAINS" [ actual expected swap member? ] }
            [ 3drop f ]
        } case
    ] [ t ] if ;

:: execute-select ( fields collection where edge lim prov? -- result )
    collection get-collection :> all-docs
    ! Apply filter
    all-docs [ where match-where? ] filter :> filtered
    ! Apply limit
    lim [ [ limit>> head-clamp ] keep offset>> tail-clamp ] when* :> limited
    ! Project fields
    fields { "*" } = [
        limited
    ] [
        limited [ [ fields ] dip '[ _ swap at ] map>alist >hashtable ] map
    ] if :> projected
    H{
        { "status" "ok" }
        { "collection" collection }
        { "count" projected length }
        { "rows" projected >array }
    } clone
    prov? [ "provenance_enabled" t pick set-at ] when ;

:: execute-update ( collection assignments where prov -- result )
    collection get-collection :> docs
    0 :> modified!
    docs [
        dup where match-where? [
            assignments [ first2 pick set-at ] each
            modified 1 + modified!
        ] when
    ] each
    docs collection set-collection
    H{
        { "status" "ok" }
        { "collection" collection }
        { "modified_count" modified }
    } clone
    prov [ "provenance" swap pick set-at ] when* ;

:: execute-delete ( collection where prov -- result )
    collection get-collection :> docs
    docs [ where match-where? not ] filter :> remaining
    docs length remaining length - :> deleted
    remaining collection set-collection
    H{
        { "status" "ok" }
        { "collection" collection }
        { "deleted_count" deleted }
    } clone
    prov [ "provenance" swap pick set-at ] when* ;

:: execute-create ( collection fields schema -- result )
    V{ } clone collection set-collection
    H{
        { "status" "ok" }
        { "collection" collection }
        { "schema_version" 1 }
        { "fields" fields }
    } clone ;

:: execute-drop ( collection prov -- result )
    f collection set-collection
    H{
        { "status" "ok" }
        { "collection" collection }
        { "dropped" t }
    } clone
    prov [ "provenance" swap pick set-at ] when* ;

M: gql-insert execute-gql
    [ collection>> ] [ document>> ] [ provenance>> ] tri
    execute-insert ;

M: gql-select execute-gql
    [ fields>> ]
    [ collection>> ]
    [ where-clause>> ]
    [ edge-clause>> ]
    [ limit-clause>> ]
    [ with-provenance?>> ] 6 ncleave
    execute-select ;

M: gql-update execute-gql
    [ collection>> ] [ assignments>> ] [ where-clause>> ] [ provenance>> ] quad
    execute-update ;

M: gql-delete execute-gql
    [ collection>> ] [ where-clause>> ] [ provenance>> ] tri
    execute-delete ;

M: gql-create execute-gql
    [ collection>> ] [ fields>> ] [ schema>> ] tri
    execute-create ;

M: gql-drop execute-gql
    [ collection>> ] [ provenance>> ] bi
    execute-drop ;

! Timing helper for ANALYZE mode
: with-timing ( quot -- result elapsed-ms )
    nano-count [ call ] dip nano-count swap - 1000000 / ; inline

! Generate verbose plan description
:: plan-step>verbose ( step -- string )
    step type>> :> type
    step target>> :> target
    step cost>> :> cost
    step rows>> :> rows
    step rationale>> :> rationale
    {
        { [ type "scan" = ] [
            target "-> Seq Scan on %s" sprintf
            "\n     Estimated Cost: " cost number>string append
            "\n     Estimated Rows: " rows number>string append
            "\n     Note: " rationale append
            append append append
        ] }
        { [ type "project" = ] [
            "-> Projection"
            target array? [
                "\n     Columns: " target ", " join append
            ] when
            append
        ] }
        { [ type "limit" = ] [
            "-> Limit"
            target limit-clause? [
                "\n     Limit: " target limit>> number>string append
                target offset>> 0 > [
                    "\n     Offset: " target offset>> number>string append
                ] when
            ] when
            append
        ] }
        { [ type "traverse" = ] [
            target "-> Graph Traversal (%s)" sprintf
            "\n     Estimated Cost: " cost number>string append
            append
        ] }
        { [ type "insert" = ] [
            target "-> Insert into %s" sprintf
        ] }
        { [ type "update" = ] [
            target "-> Update on %s" sprintf
        ] }
        { [ type "delete" = ] [
            target "-> Delete from %s" sprintf
        ] }
        { [ type "create-collection" = ] [
            target "-> Create Collection %s" sprintf
        ] }
        { [ type "drop-collection" = ] [
            target "-> Drop Collection %s" sprintf
        ] }
        { [ type "introspect" = ] [
            target "-> Introspect %s" sprintf
        ] }
        [ drop type "-> %s" sprintf ]
    } cond ;

:: plan>verbose-string ( plan -- string )
    "QUERY PLAN\n" :> out!
    "-" 50 <repetition> concat "\n" append out swap append out!
    plan steps>> [| step i |
        "  " i 2 * <repetition> concat
        step plan-step>verbose append
        "\n" append
        out swap append out!
    ] each-index
    "\nTotal Cost: " plan total-cost>> number>string append "\n" append
    out swap append out!
    plan provenance?>> [ "With Provenance Tracking\n" out swap append out! ] when
    out ;

:: execute-explain ( stmt -- result )
    stmt inner-stmt>> plan-query :> plan
    stmt analyze?>> [
        ! ANALYZE mode: actually run the query and report timing
        [ stmt inner-stmt>> execute-gql ] with-timing :> ( result elapsed )
        H{
            { "status" "ok" }
        } clone
        "plan" plan plan>assoc pick set-at
        "execution_time_ms" elapsed pick set-at
        "actual_result" result pick set-at
        stmt verbose?>> [
            "verbose_plan" plan plan>verbose-string pick set-at
        ] when
    ] [
        ! Plain EXPLAIN: just show the plan
        H{
            { "status" "ok" }
        } clone
        "plan" plan plan>assoc pick set-at
        stmt verbose?>> [
            "verbose_plan" plan plan>verbose-string pick set-at
        ] when
    ] if ;

M: gql-explain execute-gql
    execute-explain ;

M: gql-introspect execute-gql
    [ target>> ] [ arg>> ] bi
    {
        { "SCHEMA" [
            drop  ! arg
            storage-list-collections
            [ get-collection first [ keys ] [ { } ] if* ] map flatten members
            H{
                { "status" "ok" }
            } clone
            [ "fields" ] dip [ set-at ] keep
        ] }
        { "CONSTRAINTS" [
            drop
            H{
                { "status" "ok" }
                { "constraints" { } }
                { "functional_dependencies" { } }
            }
        ] }
        { "COLLECTIONS" [
            drop
            storage-list-collections >array
            H{
                { "status" "ok" }
            } clone
            [ "collections" ] dip [ set-at ] keep
        ] }
        { "JOURNAL" [
            ! arg is since sequence number
            H{
                { "status" "ok" }
                { "entries" { } }
                { "head" 0 }
            } clone
            [ "since" ] dip [ set-at ] keep
        ] }
        [ 2drop H{ { "status" "error" } { "message" "Unknown introspect target" } } ]
    } case ;

! ============================================================
! Public API
! ============================================================

: run-gql ( str -- result )
    parse-gql execute-gql ;

: explain-gql ( str -- plan )
    "EXPLAIN " prepend
    run-gql ;

: explain-verbose-gql ( str -- plan )
    "EXPLAIN VERBOSE " prepend
    run-gql ;

: explain-analyze-gql ( str -- plan )
    "EXPLAIN ANALYZE " prepend
    run-gql ;

: explain-analyze-verbose-gql ( str -- plan )
    "EXPLAIN ANALYZE VERBOSE " prepend
    run-gql ;
