%% SPDX-License-Identifier: PMPL-1.0-or-later
%% Lith NIF - Erlang interface to Lith
%%
%% This module loads the Zig NIF and provides Erlang functions
%% to interact with Lith.

-module(lith_nif).
-export([
    version/0,
    db_open/1,
    db_close/1,
    txn_begin/2,
    txn_commit/1,
    txn_abort/1,
    apply/2,
    schema/1,
    journal/2
]).

-on_load(init/0).

-define(NIF_NOT_LOADED, erlang:nif_error(nif_not_loaded)).

%% @doc Initialize the NIF
init() ->
    PrivDir = case code:priv_dir(formbase_server) of
        {error, _} ->
            %% Fallback for development
            case code:which(?MODULE) of
                Filename when is_list(Filename) ->
                    filename:join([filename:dirname(Filename), "..", "priv"]);
                _ ->
                    "priv"
            end;
        Dir ->
            Dir
    end,
    SoPath = filename:join(PrivDir, "lith_nif"),
    erlang:load_nif(SoPath, 0).

%% @doc Get Lith version as {Major, Minor, Patch}
-spec version() -> {non_neg_integer(), non_neg_integer(), non_neg_integer()}.
version() ->
    ?NIF_NOT_LOADED.

%% @doc Open a Lith database
%% @param Path Binary path to the database directory
%% @returns {ok, DbRef} | {error, Reason}
-spec db_open(binary()) -> {ok, reference()} | {error, atom()}.
db_open(_Path) ->
    ?NIF_NOT_LOADED.

%% @doc Close a Lith database
%% @param DbRef Database reference from db_open/1
%% @returns ok | {error, Reason}
-spec db_close(reference()) -> ok | {error, atom()}.
db_close(_DbRef) ->
    ?NIF_NOT_LOADED.

%% @doc Begin a transaction
%% @param DbRef Database reference
%% @param Mode Transaction mode: read_only | read_write
%% @returns {ok, TxnRef} | {error, Reason}
-spec txn_begin(reference(), read_only | read_write) -> {ok, reference()} | {error, atom()}.
txn_begin(_DbRef, _Mode) ->
    ?NIF_NOT_LOADED.

%% @doc Commit a transaction
%% @param TxnRef Transaction reference
%% @returns ok | {error, Reason}
-spec txn_commit(reference()) -> ok | {error, atom()}.
txn_commit(_TxnRef) ->
    ?NIF_NOT_LOADED.

%% @doc Abort a transaction
%% @param TxnRef Transaction reference
%% @returns ok
-spec txn_abort(reference()) -> ok.
txn_abort(_TxnRef) ->
    ?NIF_NOT_LOADED.

%% @doc Apply an operation within a transaction
%% @param TxnRef Transaction reference
%% @param OpCbor CBOR-encoded operation
%% @returns {ok, ResultCbor} | {ok, ResultCbor, ProvenanceCbor} | {error, Reason}
-spec apply(reference(), binary()) ->
    {ok, binary()} |
    {ok, binary(), binary()} |
    {error, atom()} |
    {error, atom(), binary()}.
apply(_TxnRef, _OpCbor) ->
    ?NIF_NOT_LOADED.

%% @doc Get database schema
%% @param DbRef Database reference
%% @returns {ok, SchemaCbor} | {error, Reason}
-spec schema(reference()) -> {ok, binary()} | {error, atom()}.
schema(_DbRef) ->
    ?NIF_NOT_LOADED.

%% @doc Get journal entries since a sequence number
%% @param DbRef Database reference
%% @param Since Sequence number to start from
%% @returns {ok, JournalCbor} | {error, Reason}
-spec journal(reference(), non_neg_integer()) -> {ok, binary()} | {error, atom()}.
journal(_DbRef, _Since) ->
    ?NIF_NOT_LOADED.
