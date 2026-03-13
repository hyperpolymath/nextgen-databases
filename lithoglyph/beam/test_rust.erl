#!/usr/bin/env escript
%% SPDX-License-Identifier: PMPL-1.0-or-later
%% Test Lith Rust NIF

main(_) ->
    io:format("~n=== Lith Rust NIF Test ===~n~n"),

    % Add paths
    true = code:add_patha("ebin"),

    % Test 1: Version
    io:format("Test 1: Calling version()...~n"),
    Version = lith_nif:version(),
    io:format("  ✓ Version: ~p~n~n", [Version]),

    % Test 2: Open database
    io:format("Test 2: Opening database...~n"),
    DbRef = lith_nif:db_open(<<"/tmp/lith_test">>),
    io:format("  ✓ Database opened~n~n", []),

    % Test 3: Begin transaction
    io:format("Test 3: Beginning transaction...~n"),
    {ok, TxnRef} = lith_nif:txn_begin(DbRef, <<"read_write">>),
    io:format("  ✓ Transaction started~n~n", []),

    % Test 4: Apply operation (with CBOR map)
    io:format("Test 4: Applying operation...~n"),
    CborMap = <<16#a1, 16#01, 16#02>>, % CBOR map {1: 2}
    {ok, BlockId} = lith_nif:apply(TxnRef, CborMap),
    io:format("  ✓ Operation applied, block ID: ~p~n~n", [BlockId]),

    % Test 5: Commit transaction
    io:format("Test 5: Committing transaction...~n"),
    ok = lith_nif:txn_commit(TxnRef),
    io:format("  ✓ Transaction committed~n~n", []),

    % Test 6: Schema
    io:format("Test 6: Getting schema...~n"),
    Schema = lith_nif:schema(DbRef),
    io:format("  ✓ Schema: ~p~n~n", [Schema]),

    % Test 7: Journal
    io:format("Test 7: Getting journal...~n"),
    Journal = lith_nif:journal(DbRef, 0),
    io:format("  ✓ Journal: ~p~n~n", [Journal]),

    % Test 8: Close database
    io:format("Test 8: Closing database...~n"),
    ok = lith_nif:db_close(DbRef),
    io:format("  ✓ Database closed~n~n", []),

    io:format("=== All tests passed! ===~n~n"),
    halt(0).
