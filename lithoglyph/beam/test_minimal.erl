#!/usr/bin/env escript
%% SPDX-License-Identifier: PMPL-1.0-or-later
%% Minimal NIF test - just version()

main(_) ->
    io:format("~n=== Minimal Lith NIF Test ===~n~n"),

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
    Version = lith_nif:version(),
    io:format("  ✓ Version: ~p~n~n", [Version]),

    io:format("=== Test passed! ===~n~n"),
    halt(0).
