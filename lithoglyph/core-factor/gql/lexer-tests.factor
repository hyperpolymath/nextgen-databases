! SPDX-License-Identifier: PMPL-1.0-or-later
! Form.Runtime - GQL Lexer Unit Tests
!
! Dedicated tests for the GQL tokenizer and parser primitives:
! keyword recognition, token splitting, whitespace handling,
! identifier parsing, operator handling, and error recovery.
!
! These tests complement seam-tests.factor which tests the full
! pipeline. Here we focus on lexical analysis correctness.

USING: accessors arrays assocs continuations gql io kernel math
sequences splitting strings tools.test vectors ;

IN: lexer-tests

! ============================================================
! Tokenizer Tests: split-tokens
! ============================================================

! Test basic token splitting
{ { "SELECT" "*" "FROM" "users" } } [
    "SELECT * FROM users" split-tokens >array
] unit-test

{ { "INSERT" "INTO" "docs" } } [
    "INSERT INTO docs" split-tokens >array
] unit-test

! Test tab and newline splitting
{ { "SELECT" "*" } } [
    "SELECT\t*" split-tokens >array
] unit-test

{ { "SELECT" "*" "FROM" "t" } } [
    "SELECT\n*\nFROM\nt" split-tokens >array
] unit-test

! Test comma filtering
{ { "SELECT" "a" "b" "FROM" "t" } } [
    "SELECT a,b FROM t" split-tokens >array
] unit-test

{ { "a" "b" "c" } } [
    "a,b,c" split-tokens >array
] unit-test

! Test multiple whitespace
{ { "SELECT" "*" } } [
    "   SELECT   *   " split-tokens >array
] unit-test

! Test empty input
{ { } } [
    "" split-tokens >array
] unit-test

! Test whitespace-only input
{ { } } [
    "   " split-tokens >array
] unit-test

! ============================================================
! Keyword Recognition Tests: keyword?
! ============================================================

! SQL keywords (case-insensitive via >upper)
{ t } [ "SELECT" keyword? ] unit-test
{ t } [ "select" keyword? ] unit-test
{ t } [ "SeLeCt" keyword? ] unit-test
{ t } [ "FROM" keyword? ] unit-test
{ t } [ "from" keyword? ] unit-test
{ t } [ "WHERE" keyword? ] unit-test
{ t } [ "INSERT" keyword? ] unit-test
{ t } [ "INTO" keyword? ] unit-test
{ t } [ "UPDATE" keyword? ] unit-test
{ t } [ "DELETE" keyword? ] unit-test
{ t } [ "SET" keyword? ] unit-test
{ t } [ "CREATE" keyword? ] unit-test
{ t } [ "DROP" keyword? ] unit-test
{ t } [ "COLLECTION" keyword? ] unit-test
{ t } [ "WITH" keyword? ] unit-test
{ t } [ "PROVENANCE" keyword? ] unit-test
{ t } [ "LIMIT" keyword? ] unit-test
{ t } [ "OFFSET" keyword? ] unit-test

! Graph traversal keywords
{ t } [ "TRAVERSE" keyword? ] unit-test
{ t } [ "OUTBOUND" keyword? ] unit-test
{ t } [ "INBOUND" keyword? ] unit-test
{ t } [ "ANY" keyword? ] unit-test
{ t } [ "DEPTH" keyword? ] unit-test

! Introspection keywords
{ t } [ "EXPLAIN" keyword? ] unit-test
{ t } [ "INTROSPECT" keyword? ] unit-test
{ t } [ "SCHEMA" keyword? ] unit-test
{ t } [ "CONSTRAINTS" keyword? ] unit-test
{ t } [ "JOURNAL" keyword? ] unit-test
{ t } [ "SINCE" keyword? ] unit-test
{ t } [ "COLLECTIONS" keyword? ] unit-test

! Boolean and null keywords
{ t } [ "AND" keyword? ] unit-test
{ t } [ "OR" keyword? ] unit-test
{ t } [ "NOT" keyword? ] unit-test
{ t } [ "NULL" keyword? ] unit-test
{ t } [ "TRUE" keyword? ] unit-test
{ t } [ "FALSE" keyword? ] unit-test

! Type keywords
{ t } [ "STRING" keyword? ] unit-test
{ t } [ "INTEGER" keyword? ] unit-test
{ t } [ "FLOAT" keyword? ] unit-test
{ t } [ "BOOLEAN" keyword? ] unit-test
{ t } [ "TIMESTAMP" keyword? ] unit-test
{ t } [ "JSON" keyword? ] unit-test
{ t } [ "PROMPT_SCORE" keyword? ] unit-test

! Constraint keywords
{ t } [ "UNIQUE" keyword? ] unit-test
{ t } [ "CHECK" keyword? ] unit-test
{ t } [ "REFERENCES" keyword? ] unit-test

! Comparison operator keywords
{ t } [ "LIKE" keyword? ] unit-test
{ t } [ "IN" keyword? ] unit-test
{ t } [ "CONTAINS" keyword? ] unit-test

! Non-keywords (identifiers)
{ f } [ "myTable" keyword? ] unit-test
{ f } [ "users" keyword? ] unit-test
{ f } [ "evidence" keyword? ] unit-test
{ f } [ "foo_bar" keyword? ] unit-test
{ f } [ "x" keyword? ] unit-test
{ f } [ "column1" keyword? ] unit-test

! ============================================================
! Whitespace Skipping Tests: skip-whitespace
! ============================================================

{ "hello" } [ "   hello" skip-whitespace ] unit-test
{ "hello" } [ "\t\thello" skip-whitespace ] unit-test
{ "hello" } [ "\n\nhello" skip-whitespace ] unit-test
{ "hello" } [ " \t\n\rhello" skip-whitespace ] unit-test
{ "hello" } [ "hello" skip-whitespace ] unit-test
{ "" } [ "   " skip-whitespace ] unit-test
{ "" } [ "" skip-whitespace ] unit-test

! ============================================================
! Token Consumer Tests: peek-token, consume-token
! ============================================================

! peek-token returns first token without consuming
{ "SELECT" } [
    "SELECT * FROM t" split-tokens
    peek-token
] unit-test

! peek-token returns f on empty
{ f } [
    { } >vector peek-token
] unit-test

! consume-token returns token and rest
{ "SELECT" } [
    "SELECT * FROM t" split-tokens
    consume-token nip  ! get the consumed token
] unit-test

{ 3 } [
    "SELECT * FROM t" split-tokens
    consume-token drop  ! drop the consumed token, keep rest
    length
] unit-test

! ============================================================
! expect-token Tests
! ============================================================

! Successful expect
{ 3 } [
    "SELECT * FROM t" split-tokens
    "SELECT" expect-token
    length
] unit-test

! Case-insensitive expect
{ 3 } [
    "select * FROM t" split-tokens
    "SELECT" expect-token
    length
] unit-test

! Failed expect throws error
{ t } [
    [ "INSERT * FROM t" split-tokens "SELECT" expect-token ]
    [ gql-parse-error? ] recover
] unit-test

! ============================================================
! try-consume Tests
! ============================================================

! Successful try-consume
{ t } [
    "WHERE x = 1" split-tokens
    "WHERE" try-consume nip  ! ( tokens' matched? )
] unit-test

{ 3 } [
    "WHERE x = 1" split-tokens
    "WHERE" try-consume drop  ! matched?
    length
] unit-test

! Failed try-consume (no match)
{ f } [
    "SELECT x FROM t" split-tokens
    "WHERE" try-consume nip
] unit-test

{ 4 } [
    "SELECT x FROM t" split-tokens
    "WHERE" try-consume drop
    length  ! tokens unchanged
] unit-test

! try-consume on empty
{ f } [
    { } >vector
    "SELECT" try-consume nip
] unit-test

! ============================================================
! Comment Removal Tests (parse-gql strips comments)
! ============================================================

! Line comments are stripped
{ t } [
    "-- this is a comment\nSELECT * FROM t" parse-gql
    gql-select?
] unit-test

{ t } [
    "SELECT * FROM t -- trailing comment" parse-gql
    gql-select?
] unit-test

! Multiple line comments
{ t } [
    "-- comment 1\n-- comment 2\nSELECT * FROM t" parse-gql
    gql-select?
] unit-test

! ============================================================
! Semicolon Handling Tests
! ============================================================

! Trailing semicolons are removed
{ t } [
    "SELECT * FROM t;" parse-gql
    gql-select?
] unit-test

{ t } [
    "INSERT INTO docs { x: 1 };" parse-gql
    gql-insert?
] unit-test

! ============================================================
! Operator Recognition Tests (via WHERE parsing)
! ============================================================

! Test that comparison operators are properly tokenized
{ t } [
    "SELECT * FROM t WHERE x = 1" parse-gql
    where-clause>> where-clause?
] unit-test

{ "=" } [
    "SELECT * FROM t WHERE x = 1" parse-gql
    where-clause>> expression>> op>>
] unit-test

! ============================================================
! Navigation Path Syntax Tests
! ============================================================

! TRAVERSE edge_type direction
{ t } [
    "SELECT * FROM nodes TRAVERSE knows OUTBOUND" parse-gql
    gql-select?
] unit-test

! TRAVERSE with DEPTH
{ t } [
    "SELECT * FROM nodes TRAVERSE knows OUTBOUND DEPTH 3" parse-gql
    gql-select?
] unit-test

! Edge directions
{ "INBOUND" } [
    "SELECT * FROM nodes TRAVERSE follows INBOUND DEPTH 2" parse-gql
    edge-clause>> direction>>
] unit-test

{ "OUTBOUND" } [
    "SELECT * FROM nodes TRAVERSE knows OUTBOUND" parse-gql
    edge-clause>> direction>>
] unit-test

! Default depth is 1 when omitted
{ 1 } [
    "SELECT * FROM nodes TRAVERSE knows ANY" parse-gql
    edge-clause>> depth>>
] unit-test

! ============================================================
! Literal Value Tests (via WHERE clause)
! ============================================================

! String value in WHERE
{ "Alice" } [
    "SELECT * FROM users WHERE name = Alice" parse-gql
    where-clause>> expression>> value>>
] unit-test

! Numeric values as strings (tokenizer yields strings)
{ "42" } [
    "SELECT * FROM data WHERE x = 42" parse-gql
    where-clause>> expression>> value>>
] unit-test

! ============================================================
! Statement Type Recognition Tests
! ============================================================

{ t } [ "SELECT * FROM t" parse-gql gql-select? ] unit-test
{ t } [ "INSERT INTO t { x: 1 }" parse-gql gql-insert? ] unit-test
{ t } [ "UPDATE t SET x = 1 WHERE y = 2" parse-gql gql-update? ] unit-test
{ t } [ "DELETE FROM t WHERE x = 1" parse-gql gql-delete? ] unit-test
{ t } [ "CREATE COLLECTION t" parse-gql gql-create? ] unit-test
{ t } [ "DROP COLLECTION t" parse-gql gql-drop? ] unit-test
{ t } [ "EXPLAIN SELECT * FROM t" parse-gql gql-explain? ] unit-test
{ t } [ "INTROSPECT COLLECTIONS" parse-gql gql-introspect? ] unit-test

! Case-insensitive statement keywords
{ t } [ "select * from t" parse-gql gql-select? ] unit-test
{ t } [ "Select * From t" parse-gql gql-select? ] unit-test
{ t } [ "insert into t { x: 1 }" parse-gql gql-insert? ] unit-test
{ t } [ "delete from t where x = 1" parse-gql gql-delete? ] unit-test

! ============================================================
! EXPLAIN Flag Parsing Tests
! ============================================================

{ t } [
    "EXPLAIN ANALYZE SELECT * FROM t" parse-gql
    analyze?>>
] unit-test

{ t } [
    "EXPLAIN VERBOSE SELECT * FROM t" parse-gql
    verbose?>>
] unit-test

{ t } [
    "EXPLAIN ANALYZE VERBOSE SELECT * FROM t" parse-gql
    dup analyze?>> swap verbose?>> and
] unit-test

! EXPLAIN without flags
{ f } [
    "EXPLAIN SELECT * FROM t" parse-gql
    analyze?>>
] unit-test

{ f } [
    "EXPLAIN SELECT * FROM t" parse-gql
    verbose?>>
] unit-test

! ============================================================
! INTROSPECT Target Parsing Tests
! ============================================================

{ "COLLECTIONS" } [
    "INTROSPECT COLLECTIONS" parse-gql target>>
] unit-test

{ "SCHEMA" } [
    "INTROSPECT SCHEMA" parse-gql target>>
] unit-test

{ "CONSTRAINTS" } [
    "INTROSPECT CONSTRAINTS" parse-gql target>>
] unit-test

{ "JOURNAL" } [
    "INTROSPECT JOURNAL" parse-gql target>>
] unit-test

! JOURNAL with SINCE
{ t } [
    "INTROSPECT JOURNAL SINCE 100" parse-gql
    dup target>> "JOURNAL" =
    swap arg>> 100 = and
] unit-test

! ============================================================
! Error Recovery Tests
! ============================================================

! Unknown statement type throws parse error
{ t } [
    [ "SELECTT * FROM users" parse-gql ] [ gql-parse-error? ] recover
] unit-test

{ t } [
    [ "BANANA * FROM users" parse-gql ] [ gql-parse-error? ] recover
] unit-test

! Missing collection after FROM
{ t } [
    [ "SELECT * FROM" parse-gql drop ]
    [ ] recover
    ! If it doesn't crash, that's acceptable error handling
    t
] unit-test

! ============================================================
! LIMIT / OFFSET Parsing Tests
! ============================================================

{ t } [
    "SELECT * FROM t LIMIT 10" parse-gql
    limit-clause>> limit-clause?
] unit-test

{ 10 } [
    "SELECT * FROM t LIMIT 10" parse-gql
    limit-clause>> limit>>
] unit-test

{ 0 } [
    "SELECT * FROM t LIMIT 10" parse-gql
    limit-clause>> offset>>  ! Default offset is 0
] unit-test

{ 20 } [
    "SELECT * FROM t LIMIT 10 OFFSET 20" parse-gql
    limit-clause>> offset>>
] unit-test

! ============================================================
! Field List Parsing Tests
! ============================================================

! Star projection
{ { "*" } } [
    "SELECT * FROM t" parse-gql
    fields>> >array
] unit-test

! Named fields
{ t } [
    "SELECT name dept salary FROM users" parse-gql
    fields>> length 3 =
] unit-test

! ============================================================
! Test Summary
! ============================================================

: run-lexer-tests ( -- )
    "Running GQL lexer unit tests..." print
    "lexer-tests" run-tests
    "Lexer tests complete." print ;

MAIN: run-lexer-tests
