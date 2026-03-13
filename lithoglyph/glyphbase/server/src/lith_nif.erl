% SPDX-License-Identifier: PMPL-1.0-or-later
% SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (@hyperpolymath)
%
% lith_nif.erl - Erlang NIF loader module for Lithoglyph
%
% This module loads the Zig-compiled shared library and provides stub
% functions that are replaced by the NIF at load time. The module name
% must match the .name field in the Zig ErlNifEntry ("lith_nif").

-module(lith_nif).
-export([version/0, db_open/1, db_close/1, txn_begin/2, txn_commit/1,
         txn_abort/1, apply/2, schema/1, journal/2]).
-on_load(load_nif/0).

load_nif() ->
    PrivDir = case code:priv_dir(glyphbase_server) of
        {error, _} ->
            %% Development fallback — check native/priv and ./priv
            case filelib:is_dir("native/priv") of
                true -> "native/priv";
                false -> "./priv"
            end;
        Dir ->
            Dir
    end,
    NifPath = filename:join(PrivDir, "liblithoglyph_nif"),
    erlang:load_nif(NifPath, 0).

%% Stub functions replaced by NIF at load time.
%% If these are called, the NIF failed to load.

version() ->
    erlang:nif_error(nif_not_loaded).

db_open(_Path) ->
    erlang:nif_error(nif_not_loaded).

db_close(_Db) ->
    erlang:nif_error(nif_not_loaded).

txn_begin(_Db, _Mode) ->
    erlang:nif_error(nif_not_loaded).

txn_commit(_Txn) ->
    erlang:nif_error(nif_not_loaded).

txn_abort(_Txn) ->
    erlang:nif_error(nif_not_loaded).

apply(_Txn, _OpCbor) ->
    erlang:nif_error(nif_not_loaded).

schema(_Db) ->
    erlang:nif_error(nif_not_loaded).

journal(_Db, _Since) ->
    erlang:nif_error(nif_not_loaded).
