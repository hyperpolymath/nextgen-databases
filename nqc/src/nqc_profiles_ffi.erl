%% SPDX-License-Identifier: MPL-2.0
%% (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
%% Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
%%
%% nqc_profiles_ffi.erl — Erlang FFI for profile JSON field extraction.
%%
%% Extracts typed fields from dynamic JSON maps for the custom profile loader.

-module(nqc_profiles_ffi).
-export([
    extract_string_field/2,
    extract_int_field/2,
    extract_bool_field/2,
    extract_string_list_field/2,
    get_home_dir/0
]).

%% Extract a string field from a map.
-spec extract_string_field(term(), binary()) -> {ok, binary()} | {error, nil}.
extract_string_field(Map, Key) when is_map(Map), is_binary(Key) ->
    case get_field(Map, Key) of
        {ok, Value} when is_binary(Value) -> {ok, Value};
        {ok, Value} when is_atom(Value) -> {ok, atom_to_binary(Value, utf8)};
        _ -> {error, nil}
    end;
extract_string_field(_, _) ->
    {error, nil}.

%% Extract an integer field from a map.
-spec extract_int_field(term(), binary()) -> {ok, integer()} | {error, nil}.
extract_int_field(Map, Key) when is_map(Map), is_binary(Key) ->
    case get_field(Map, Key) of
        {ok, Value} when is_integer(Value) -> {ok, Value};
        _ -> {error, nil}
    end;
extract_int_field(_, _) ->
    {error, nil}.

%% Extract a boolean field from a map.
-spec extract_bool_field(term(), binary()) -> {ok, boolean()} | {error, nil}.
extract_bool_field(Map, Key) when is_map(Map), is_binary(Key) ->
    case get_field(Map, Key) of
        {ok, true} -> {ok, true};
        {ok, false} -> {ok, false};
        _ -> {error, nil}
    end;
extract_bool_field(_, _) ->
    {error, nil}.

%% Extract a list of strings from a map field.
-spec extract_string_list_field(term(), binary()) -> {ok, [binary()]} | {error, nil}.
extract_string_list_field(Map, Key) when is_map(Map), is_binary(Key) ->
    case get_field(Map, Key) of
        {ok, Value} when is_list(Value) ->
            Strings = lists:filtermap(
                fun(B) when is_binary(B) -> {true, B};
                   (A) when is_atom(A) -> {true, atom_to_binary(A, utf8)};
                   (_) -> false
                end,
                Value
            ),
            {ok, Strings};
        _ -> {error, nil}
    end;
extract_string_list_field(_, _) ->
    {error, nil}.

%% Get home directory from environment.
-spec get_home_dir() -> {ok, binary()} | {error, nil}.
get_home_dir() ->
    case os:getenv("HOME") of
        false -> {error, nil};
        Home -> {ok, list_to_binary(Home)}
    end.

%% --- Internal helpers ---

%% Try binary key first, then atom key.
get_field(Map, Key) ->
    case maps:find(Key, Map) of
        {ok, Value} -> {ok, Value};
        error ->
            try
                AtomKey = binary_to_existing_atom(Key, utf8),
                maps:find(AtomKey, Map)
            catch
                _:_ -> error
            end
    end.
