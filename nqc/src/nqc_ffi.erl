%% SPDX-License-Identifier: MPL-2.0
%% (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
%% Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
%%
%% nqc_ffi.erl — Erlang FFI helpers for the NextGen Query Client.
%%
%% Provides ad-hoc dynamic value manipulation that Gleam's type system
%% cannot express directly: map key extraction, field access, JSON
%% encoding, list coercion, and stdin reading. These operate on raw
%% Erlang terms (maps, lists, binaries) without static type guarantees.

-module(nqc_ffi).
-export([
    extract_keys/1,
    json_encode/1,
    read_line/1,
    extract_field_or_self/2,
    extract_list/1,
    extract_field_string/2
]).

%% ---------------------------------------------------------------------------
%% Key extraction
%% ---------------------------------------------------------------------------

%% Extract keys from an Erlang map, returning them as a list of binaries.
%% If the value is not a map, returns an empty list.
-spec extract_keys(term()) -> [binary()].
extract_keys(Map) when is_map(Map) ->
    Keys = maps:keys(Map),
    %% Convert atom keys to binaries, keep binary keys as-is.
    lists:filtermap(
        fun(K) when is_binary(K) -> {true, K};
           (K) when is_atom(K) -> {true, atom_to_binary(K, utf8)};
           (_) -> false
        end,
        Keys
    );
extract_keys(_) ->
    [].

%% ---------------------------------------------------------------------------
%% Field extraction
%% ---------------------------------------------------------------------------

%% Extract a named field from a map. If the field doesn't exist or the
%% value is not a map, return the original value unchanged.
-spec extract_field_or_self(term(), binary()) -> term().
extract_field_or_self(Map, Key) when is_map(Map), is_binary(Key) ->
    %% Try binary key first, then atom key.
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error ->
            try
                AtomKey = binary_to_existing_atom(Key, utf8),
                case maps:find(AtomKey, Map) of
                    {ok, Value} -> Value;
                    error -> Map
                end
            catch
                _:_ -> Map
            end
    end;
extract_field_or_self(Value, _Key) ->
    Value.

%% Extract a dynamic value as a list. Returns empty list if not a list.
-spec extract_list(term()) -> [term()].
extract_list(L) when is_list(L) -> L;
extract_list(_) -> [].

%% Extract a field from a map and convert to a display string.
%% Tries the field as binary key, then atom key. Formats the value
%% as a human-readable string suitable for table/CSV display.
-spec extract_field_string(term(), binary()) -> binary().
extract_field_string(Map, Key) when is_map(Map), is_binary(Key) ->
    Value = case maps:find(Key, Map) of
        {ok, V} -> V;
        error ->
            try
                AtomKey = binary_to_existing_atom(Key, utf8),
                case maps:find(AtomKey, Map) of
                    {ok, V2} -> V2;
                    error -> null
                end
            catch
                _:_ -> null
            end
    end,
    value_to_string(Value);
extract_field_string(_, _) ->
    <<"null">>.

%% Convert a term to a human-readable display string.
-spec value_to_string(term()) -> binary().
value_to_string(null) -> <<"null">>;
value_to_string(nil) -> <<"null">>;
value_to_string(true) -> <<"true">>;
value_to_string(false) -> <<"false">>;
value_to_string(B) when is_binary(B) -> B;
value_to_string(N) when is_integer(N) -> integer_to_binary(N);
value_to_string(F) when is_float(F) ->
    float_to_binary(F, [{decimals, 6}, compact]);
value_to_string(A) when is_atom(A) -> atom_to_binary(A, utf8);
value_to_string(Term) ->
    %% For complex values (lists, maps), encode as JSON.
    json_encode(Term).

%% ---------------------------------------------------------------------------
%% JSON encoding
%% ---------------------------------------------------------------------------

%% Encode a term as a JSON string (binary).
%% Uses OTP 27's built-in json module if available, otherwise falls
%% back to a simple recursive encoder.
-spec json_encode(term()) -> binary().
json_encode(Term) ->
    try
        iolist_to_binary(json:encode(Term))
    catch
        _:_ -> simple_encode(Term)
    end.

%% ---------------------------------------------------------------------------
%% stdin reading
%% ---------------------------------------------------------------------------

%% Read a line from stdin, returning {ok, Line} or {error, eof}.
-spec read_line(binary()) -> {ok, binary()} | {error, eof}.
read_line(Prompt) ->
    case io:get_line(binary_to_list(Prompt)) of
        eof -> {error, eof};
        {error, _} -> {error, eof};
        Line when is_list(Line) -> {ok, list_to_binary(Line)};
        Line when is_binary(Line) -> {ok, Line}
    end.

%% ---------------------------------------------------------------------------
%% Simple JSON encoder (fallback when OTP json module unavailable)
%% ---------------------------------------------------------------------------

simple_encode(null) -> <<"null">>;
simple_encode(nil) -> <<"null">>;
simple_encode(true) -> <<"true">>;
simple_encode(false) -> <<"false">>;
simple_encode(N) when is_integer(N) -> integer_to_binary(N);
simple_encode(F) when is_float(F) ->
    float_to_binary(F, [{decimals, 6}, compact]);
simple_encode(B) when is_binary(B) ->
    <<"\"", (escape_string(B))/binary, "\"">>;
simple_encode(A) when is_atom(A) ->
    <<"\"", (atom_to_binary(A, utf8))/binary, "\"">>;
simple_encode(L) when is_list(L) ->
    Items = lists:map(fun simple_encode/1, L),
    <<"[", (join_with_comma(Items))/binary, "]">>;
simple_encode(M) when is_map(M) ->
    Pairs = maps:fold(
        fun(K, V, Acc) ->
            Key = case K of
                B when is_binary(B) -> B;
                A when is_atom(A) -> atom_to_binary(A, utf8);
                _ -> <<"unknown">>
            end,
            [<<"\"", Key/binary, "\":", (simple_encode(V))/binary>> | Acc]
        end,
        [],
        M
    ),
    <<"{", (join_with_comma(lists:reverse(Pairs)))/binary, "}">>;
simple_encode(_) -> <<"null">>.

escape_string(B) ->
    binary:replace(
        binary:replace(B, <<"\"">>, <<"\\\"">>, [global]),
        <<"\n">>, <<"\\n">>, [global]
    ).

join_with_comma([]) -> <<>>;
join_with_comma([H]) -> H;
join_with_comma([H|T]) ->
    lists:foldl(fun(Item, Acc) -> <<Acc/binary, ",", Item/binary>> end, H, T).
