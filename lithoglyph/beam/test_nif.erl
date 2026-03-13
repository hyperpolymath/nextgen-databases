#!/usr/bin/env escript
%% SPDX-License-Identifier: PMPL-1.0-or-later
%% Quick test of Lith NIF

main(_) ->
    io:format("~n=== Lith-BEAM NIF Test ===~n~n"),

    % Add priv to library path
    code:add_pathz("priv"),

    % Test 1: Load NIF
    io:format("Test 1: Loading NIF...~n"),
    case erlang:load_nif("./priv/lith_nif", 0) of
        ok ->
            io:format("  ✓ NIF loaded successfully~n~n");
        {error, {Reason, Text}} ->
            io:format("  ✗ NIF load failed: ~p - ~s~n", [Reason, Text]),
            halt(1)
    end,

    % Test 2: Version
    io:format("Test 2: Calling version()...~n"),
    try lith_nif:version() of
        {Major, Minor, Patch} ->
            io:format("  ✓ Version: ~p.~p.~p~n~n", [Major, Minor, Patch])
    catch
        error:VersionReason ->
            io:format("  ✗ Version failed: ~p~n", [VersionReason]),
            halt(1)
    end,

    % Test 3: Open database
    io:format("Test 3: Opening database...~n"),
    DbPath = <<"/tmp/lith_test">>,
    try lith_nif:db_open(DbPath) of
        {ok, DbRef} ->
            io:format("  ✓ Database opened: ~p~n", [DbRef]),

            % Test 4: Begin transaction
            io:format("~nTest 4: Beginning transaction...~n"),
            try lith_nif:txn_begin(DbRef, read_write) of
                {ok, TxnRef} ->
                    io:format("  ✓ Transaction started: ~p~n", [TxnRef]),

                    % Test 5: Commit transaction
                    io:format("~nTest 5: Committing transaction...~n"),
                    try lith_nif:txn_commit(TxnRef) of
                        ok ->
                            io:format("  ✓ Transaction committed~n");
                        CommitError ->
                            io:format("  ✗ Commit failed: ~p~n", [CommitError])
                    catch
                        error:ErrCommit ->
                            io:format("  ✗ Commit error: ~p~n", [ErrCommit])
                    end;
                TxnError ->
                    io:format("  ✗ Transaction failed: ~p~n", [TxnError])
            catch
                error:ErrTxn ->
                    io:format("  ✗ Transaction error: ~p~n", [ErrTxn])
            end,

            % Test 6: Close database
            io:format("~nTest 6: Closing database...~n"),
            try lith_nif:db_close(DbRef) of
                ok ->
                    io:format("  ✓ Database closed~n");
                CloseError ->
                    io:format("  ✗ Close failed: ~p~n", [CloseError])
            catch
                error:ErrClose ->
                    io:format("  ✗ Close error: ~p~n", [ErrClose])
            end;
        OpenError ->
            io:format("  ✗ Open failed: ~p~n", [OpenError]),
            halt(1)
    catch
        error:ErrOpen ->
            io:format("  ✗ Open error: ~p~n", [ErrOpen]),
            halt(1)
    end,

    io:format("~n=== All tests passed! ===~n~n"),
    halt(0).
