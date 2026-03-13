% SPDX-License-Identifier: PMPL-1.0-or-later
% SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (@hyperpolymath)
%
% lithoglyph_nif.erl - NIF loader module

-module(lithoglyph_nif).
-export([init/0, open/1, create/2, txn_begin/1, txn_commit/1, query_execute/3, cursor_next/1]).
-on_load(load_nif/0).

load_nif() ->
    PrivDir = case code:priv_dir(?MODULE) of
        {error, _} ->
            %% Development mode - priv is in current directory
            "./priv";
        Dir ->
            Dir
    end,
    NifPath = filename:join(PrivDir, "lithoglyph_nif"),
    erlang:load_nif(NifPath, 0).

%% Stub functions that will be replaced by NIF
init() ->
    erlang:nif_error(nif_not_loaded).

open(_Path) ->
    erlang:nif_error(nif_not_loaded).

create(_Path, _BlockCount) ->
    erlang:nif_error(nif_not_loaded).

txn_begin(_Db) ->
    erlang:nif_error(nif_not_loaded).

txn_commit(_Txn) ->
    erlang:nif_error(nif_not_loaded).

query_execute(_Db, _Query, _Provenance) ->
    erlang:nif_error(nif_not_loaded).

cursor_next(_Cursor) ->
    erlang:nif_error(nif_not_loaded).
