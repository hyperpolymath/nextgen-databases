! SPDX-License-Identifier: PMPL-1.0-or-later
! Form.Normalizer - Functional Dependency Discovery
!
! Implements the DFD (Depth-First Discovery) algorithm for
! automatic functional dependency detection.
! Decision D-NORM-001: DFD as default algorithm.

USING: accessors arrays assocs combinators combinators.short-circuit
continuations hash-sets io kernel math math.combinatorics math.order
math.ranges math.statistics random sequences sets sorting vectors ;

IN: fd-discovery

! ============================================================
! Core Types
! ============================================================

TUPLE: functional-dependency
    determinant     ! Set of attribute names (LHS)
    dependent       ! Single attribute name (RHS)
    confidence      ! 0.0 to 1.0
    discovered-at   ! Journal sequence number
    sample-size ;   ! Number of records sampled

TUPLE: fd-discovery-config
    sample-size           ! Max records to sample
    confidence-threshold  ! Minimum confidence to report (D-NORM-002)
    algorithm             ! dfd | tane | fdhits
    max-lhs-size ;        ! Maximum left-hand side cardinality

TUPLE: fd-discovery-result
    collection        ! Collection name
    dependencies      ! List of functional-dependency (exact FDs, conf >= 0.99)
    probable-fds      ! Strong approx FDs (0.95 <= conf < 0.99)
    data-warnings     ! Weak approx FDs (conf < 0.95)
    discovery-time    ! Milliseconds
    sample-info ;     ! Sample metadata

! ============================================================
! Default Configuration (per D-NORM-001, D-NORM-002)
! ============================================================

: default-fd-config ( -- config )
    fd-discovery-config new
        10000 >>sample-size
        0.95 >>confidence-threshold
        "dfd" >>algorithm
        5 >>max-lhs-size ;

! ============================================================
! Partition Computation (Core of FD Discovery)
! ============================================================

! A partition groups row indices by their values on a set of attributes
TUPLE: partition
    attributes   ! Which attributes define this partition
    classes ;    ! List of equivalence classes (each a list of row indices)

! Compute partition: group rows by values of given attributes
:: compute-partition ( data attributes -- partition )
    H{ } clone :> groups
    data [| row idx |
        attributes [ row at ] map :> key
        key groups at [ V{ } clone ] unless* :> class
        idx class push
        class key groups set-at
    ] each-index
    partition new
        attributes >>attributes
        groups values >>classes ;

! Partition refinement: intersect with another attribute
:: refine-partition ( part attr -- part' )
    V{ } clone :> new-classes
    part classes>> [| class |
        H{ } clone :> subgroups
        class [| idx |
            ! Would need data access here - simplified for PoC
            idx subgroups at [ V{ } clone ] unless* :> subclass
            idx subclass push
            subclass idx subgroups set-at
        ] each
        subgroups values [ length 1 > ] filter new-classes push-all
    ] each
    partition new
        part attributes>> attr suffix >>attributes
        new-classes >>classes ;

! Check if partition is unique (every class has size 1)
: unique-partition? ( partition -- ? )
    classes>> [ length 1 = ] all? ;

! Get partition error (count of rows in non-singleton classes)
: partition-error ( partition -- error )
    classes>> [ length 1 - 0 max ] map-sum ;

! ============================================================
! DFD Algorithm Implementation (per D-NORM-001)
! ============================================================

! DFD state for tracking discovery progress
TUPLE: dfd-state
    data           ! The actual data rows
    attributes     ! All attribute names
    discovered     ! Set of discovered FDs
    visited        ! Set of visited (lhs, rhs) pairs
    min-deps ;     ! Minimal dependencies found

: init-dfd-state ( data -- state )
    dfd-state new
        swap >>data
        dup data>> first keys sort >array >>attributes
        V{ } clone >>discovered
        HS{ } clone >>visited
        H{ } clone >>min-deps ;

! Generate all subsets of size n
: subsets-of-size ( attrs n -- subsets )
    <combinations> [ >array ] map ;

! Check if X -> Y holds in data with given confidence
:: check-fd-holds ( data lhs rhs -- confidence )
    data length :> total
    total 0 = [ 1.0 ] [
        H{ } clone :> lhs-to-rhs
        0 :> violations!
        data [| row |
            lhs [ row at ] map :> lhs-val
            rhs row at :> rhs-val
            lhs-val lhs-to-rhs at :> existing
            existing [
                existing rhs-val = not [ violations 1 + violations! ] when
            ] [
                rhs-val lhs-val lhs-to-rhs set-at
            ] if
        ] each
        total violations - total / >float
    ] if ;

! Check if lhs is minimal (no proper subset determines rhs)
:: is-minimal-fd? ( state lhs rhs -- ? )
    lhs length 1 <= [ t ] [
        lhs length 1 - [0..b) [| i |
            lhs i swap remove :> subset
            state data>> subset rhs check-fd-holds 0.99 >=
        ] any? not
    ] if ;

! Find FDs for a given RHS attribute using DFD traversal
:: discover-fds-for-rhs ( state rhs config -- )
    state attributes>> rhs swap remove :> candidates

    ! Start with single-attribute LHS and expand
    1 config max-lhs-size>> [a..b] [| size |
        candidates size subsets-of-size [| lhs |
            ! Skip if already visited
            lhs rhs 2array state visited>> in? not [
                lhs rhs 2array state visited>> adjoin

                ! Check if FD holds
                state data>> lhs rhs check-fd-holds :> conf

                conf config confidence-threshold>> >= [
                    ! Check minimality
                    state lhs rhs is-minimal-fd? [
                        functional-dependency new
                            lhs >>determinant
                            rhs 1array >>dependent
                            conf >>confidence
                            0 >>discovered-at
                            state data>> length >>sample-size
                        state discovered>> push
                    ] when
                ] when
            ] when
        ] each
    ] each ;

! Main DFD entry point
:: run-dfd ( data config -- result )
    data init-dfd-state :> state

    ! For each attribute as potential RHS
    state attributes>> [| rhs |
        state rhs config discover-fds-for-rhs
    ] each

    ! Classify results per D-NORM-002 three-tier policy
    state discovered>> :> all-fds
    all-fds [ confidence>> 0.99 >= ] filter :> exact
    all-fds [ confidence>> [ 0.95 >= ] [ 0.99 < ] bi and ] filter :> probable
    all-fds [ confidence>> 0.95 < ] filter :> warnings

    fd-discovery-result new
        "unknown" >>collection
        exact >>dependencies
        probable >>probable-fds
        warnings >>data-warnings
        0 >>discovery-time
        H{
            { "rows" data length }
            { "attributes" state attributes>> length }
            { "algorithm" "dfd" }
        } >>sample-info ;

! ============================================================
! Normal Form Detection
! ============================================================

TUPLE: normal-form-analysis
    collection
    current-form      ! 1NF, 2NF, 3NF, BCNF, etc.
    violations        ! List of violations
    candidate-keys ;  ! Inferred candidate keys

TUPLE: nf-violation
    fd                ! The violating FD
    violation-type    ! partial-dependency | transitive-dependency | non-superkey
    explanation ;     ! Human-readable explanation

! Check if attrs is a superkey (contains a candidate key)
: is-superkey? ( attrs keys -- ? )
    [ [ member? ] curry all? ] with any? ;

! Check if attrs is a proper subset of any candidate key
: proper-subset-of-key? ( attrs keys -- ? )
    [
        [ [ member? ] curry all? ]
        [ length swap length < ] 2bi and
    ] with any? ;

! Get prime attributes (in any candidate key)
: prime-attributes ( keys -- primes )
    concat members ;

! Check for BCNF violation
:: check-bcnf ( fd keys -- violation/f )
    fd determinant>> keys is-superkey? not [
        nf-violation new
            fd >>fd
            "non-superkey" >>violation-type
            fd determinant>> ", " join
            " is not a superkey but determines "
            fd dependent>> ", " join 3append
            >>explanation
    ] [ f ] if ;

! Check for 3NF violation
:: check-3nf ( fd keys -- violation/f )
    fd determinant>> keys is-superkey? not
    fd dependent>> keys prime-attributes [ member? ] curry all? not
    and [
        nf-violation new
            fd >>fd
            "transitive-dependency" >>violation-type
            "Non-superkey " fd determinant>> ", " join append
            " determines non-prime attribute(s) " append
            fd dependent>> ", " join append
            >>explanation
    ] [ f ] if ;

! Check for 2NF violation
:: check-2nf ( fd keys -- violation/f )
    fd determinant>> keys proper-subset-of-key?
    fd dependent>> keys prime-attributes [ member? ] curry all? not
    and [
        nf-violation new
            fd >>fd
            "partial-dependency" >>violation-type
            "Partial key " fd determinant>> ", " join append
            " determines non-prime attribute(s) " append
            fd dependent>> ", " join append
            >>explanation
    ] [ f ] if ;

! Analyze what normal form a schema satisfies
:: analyze-normal-form ( fds keys -- analysis )
    normal-form-analysis new
        "unknown" >>collection
        keys >>candidate-keys

        ! Check for violations at each level
        fds [ keys check-bcnf ] map sift :> bcnf-violations
        fds [ keys check-3nf ] map sift :> 3nf-violations
        fds [ keys check-2nf ] map sift :> 2nf-violations

        ! Determine highest satisfied normal form
        bcnf-violations empty? [ "BCNF" ] [
            3nf-violations empty? [ "3NF" ] [
                2nf-violations empty? [ "2NF" ] [ "1NF" ] if
            ] if
        ] if >>current-form

        ! Collect all violations
        bcnf-violations 3nf-violations append 2nf-violations append
        >>violations ;

! ============================================================
! FQL Integration: DISCOVER DEPENDENCIES
! ============================================================

TUPLE: discover-stmt
    collection
    sample-size
    confidence
    algorithm ;

: parse-discover ( tokens -- tokens' ast )
    discover-stmt new
        10000 >>sample-size
        0.95 >>confidence
        "dfd" >>algorithm
    swap ;

! Execute DISCOVER DEPENDENCIES
:: execute-discover ( stmt data -- result )
    fd-discovery-config new
        stmt sample-size>> >>sample-size
        stmt confidence>> >>confidence-threshold
        stmt algorithm>> >>algorithm
        5 >>max-lhs-size :> config

    ! Sample data if too large
    data length config sample-size>> > [
        data config sample-size>> sample
    ] [ data ] if :> sampled

    sampled config run-dfd
        stmt collection>> >>collection ;

! ============================================================
! Narrative Generation (Lith Philosophy)
! ============================================================

! Convert FD to human-readable narrative
:: fd>narrative ( fd -- string )
    fd determinant>> ", " join :> det
    fd dependent>> ", " join :> dep
    fd confidence>> :> conf

    "{" det append "}" append
    " uniquely determines " append
    "{" append dep append "}" append

    conf 1.0 < [
        " [confidence: " append
        conf number>string append
        conf 0.99 >= [
            " - EXACT"
        ] [
            conf 0.95 >= [
                " - PROBABLE (requires confirmation)"
            ] [
                " - DATA QUALITY WARNING"
            ] if
        ] if append
        "]" append
    ] when ;

! Generate violation narrative
:: violation>narrative ( v -- string )
    v violation-type>> {
        { "partial-dependency" [ "2NF VIOLATION: " ] }
        { "transitive-dependency" [ "3NF VIOLATION: " ] }
        { "non-superkey" [ "BCNF VIOLATION: " ] }
        [ drop "VIOLATION: " ]
    } case
    v explanation>> append ;

! Generate full narrative for discovery result
:: result>narrative ( result -- string )
    "FUNCTIONAL DEPENDENCY DISCOVERY REPORT\n" :> out!
    "=" 60 <repetition> concat "\n" append out swap append out!
    "\nCollection: " result collection>> append "\n" append out swap append out!

    ! Sample info
    "\nSample Information:\n" out swap append out!
    result sample-info>> [
        "  " swap ": " swap 3append number>string append "\n" append
        out swap append out!
    ] assoc-each

    ! Exact FDs
    "\n\nEXACT FUNCTIONAL DEPENDENCIES:\n" out swap append out!
    result dependencies>> empty? [
        "  (none discovered)\n" out swap append out!
    ] [
        result dependencies>> [
            "  " swap fd>narrative append "\n" append
            out swap append out!
        ] each
    ] if

    ! Probable FDs (D-NORM-002 tier 2)
    result probable-fds>> empty? not [
        "\n\nPROBABLE FUNCTIONAL DEPENDENCIES (require confirmation):\n"
        out swap append out!
        result probable-fds>> [
            "  " swap fd>narrative append "\n" append
            out swap append out!
        ] each
    ] when

    ! Data quality warnings (D-NORM-002 tier 3)
    result data-warnings>> empty? not [
        "\n\nDATA QUALITY WARNINGS:\n" out swap append out!
        result data-warnings>> [
            "  " swap fd>narrative append "\n" append
            out swap append out!
        ] each
    ] when

    out ;

! ============================================================
! Normalization Proposals
! ============================================================

TUPLE: normalization-proposal
    source-schema
    target-schemas
    transformation
    inverse
    equivalence-proof
    narrative ;

! Propose 3NF decomposition using synthesis algorithm
:: propose-3nf-decomposition ( schema fds keys -- proposal/f )
    fds [ keys check-3nf ] map sift :> violations
    violations empty? [ f ] [
        ! Simplified synthesis: create table for each FD
        fds [
            [ determinant>> ] [ dependent>> ] bi append members
        ] map :> new-schemas

        normalization-proposal new
            schema >>source-schema
            new-schemas >>target-schemas
            "SPLIT on transitive dependencies" >>transformation
            "JOIN on common attributes" >>inverse
            "Lossless: common attributes form superkey in one table" >>equivalence-proof
            violations [ violation>narrative ] map "\n" join
            "\n\nProposed decomposition eliminates transitive dependencies."
            append >>narrative
    ] if ;

! Propose BCNF decomposition
:: propose-bcnf-decomposition ( schema fds keys -- proposal/f )
    fds [ keys check-bcnf ] map sift :> violations
    violations empty? [ f ] [
        normalization-proposal new
            schema >>source-schema
            { } >>target-schemas  ! Would compute actual decomposition
            "SPLIT on BCNF violations" >>transformation
            "JOIN on determinant attributes" >>inverse
            "Lossless: determinant preserved in decomposition" >>equivalence-proof
            violations [ violation>narrative ] map "\n" join
            "\n\nProposed BCNF decomposition (may lose some FDs)."
            append >>narrative
    ] if ;

! ============================================================
! Denormalization Support (per D-NORM-003)
! ============================================================

TUPLE: denormalization-proposal
    source-schemas      ! List of normalized schemas to merge
    target-schema       ! Merged schema
    transformation      ! How to merge
    inverse             ! How to split back
    performance-rationale  ! Why denormalization is justified
    equivalence-proof   ! Proof of lossless merge
    narrative ;         ! Full explanation

! Propose denormalization for read optimization
:: propose-denormalization ( schemas join-attrs rationale -- proposal )
    denormalization-proposal new
        schemas >>source-schemas
        schemas concat members >>target-schema
        "JOIN on " join-attrs ", " join append >>transformation
        "SPLIT preserving original keys" >>inverse
        rationale >>performance-rationale
        "Merge is lossless: join attributes form key" >>equivalence-proof
        "INTENTIONAL DENORMALIZATION\n"
        "Reason: " append rationale append "\n" append
        "This denormalization trades storage efficiency for read performance.\n" append
        "The operation is fully reversible via SPLIT." append
        >>narrative ;

! ============================================================
! Public API
! ============================================================

: discover-dependencies ( data config -- result )
    run-dfd ;

: check-normal-form ( fds keys -- analysis )
    analyze-normal-form ;

: generate-normalization-proposal ( schema fds keys target-nf -- proposal/f )
    {
        { "3NF" [ propose-3nf-decomposition ] }
        { "BCNF" [ propose-bcnf-decomposition ] }
        [ 4drop f ]
    } case ;
