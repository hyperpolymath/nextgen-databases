%% SPDX-License-Identifier: MPL-2.0
%% (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
%% Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
%%
%% nqc_highlight_ffi.erl — Erlang FFI for terminal colour detection.

-module(nqc_highlight_ffi).
-export([get_term_env/0]).

%% Get the TERM environment variable.
-spec get_term_env() -> {ok, binary()} | {error, nil}.
get_term_env() ->
    case os:getenv("TERM") of
        false -> {error, nil};
        Value -> {ok, list_to_binary(Value)}
    end.
