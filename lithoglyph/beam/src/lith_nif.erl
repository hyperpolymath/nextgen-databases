%% SPDX-License-Identifier: PMPL-1.0-or-later
%% Lith NIF module - Erlang wrapper

-module(lith_nif).
-export([version/0, db_open/1, db_close/1, txn_begin/2, txn_commit/1, txn_abort/1, apply/2, schema/1, journal/2]).
-on_load(init/0).

-define(NOT_LOADED, erlang:nif_error({not_loaded, ?MODULE})).

%% Load the NIF
init() ->
    PrivDir = case code:priv_dir(?MODULE) of
        {error, _} ->
            EbinDir = filename:dirname(code:which(?MODULE)),
            AppPath = filename:dirname(EbinDir),
            filename:join(AppPath, "priv");
        Path ->
            Path
    end,
    erlang:load_nif(filename:join(PrivDir, "lith_nif"), 0).

%% NIF function stubs (replaced when NIF loads)
version() -> ?NOT_LOADED.
db_open(_Path) -> ?NOT_LOADED.
db_close(_DbRef) -> ?NOT_LOADED.
txn_begin(_DbRef, _Mode) -> ?NOT_LOADED.
txn_commit(_TxnRef) -> ?NOT_LOADED.
txn_abort(_TxnRef) -> ?NOT_LOADED.
apply(_TxnRef, _OpCbor) -> ?NOT_LOADED.
schema(_DbRef) -> ?NOT_LOADED.
journal(_DbRef, _Since) -> ?NOT_LOADED.
