% SPDX-License-Identifier: PMPL-1.0-or-later
% Lithoglyph NIF - Erlang module loader for Rustler

-module(lith_nif).

-export([version/0, db_open/1, db_close/1, txn_begin/2, txn_commit/1, txn_abort/1, apply/2, schema/1, journal/2]).

-on_load(init/0).

init() ->
    SoName = case code:priv_dir(lith_http) of
        {error, bad_name} ->
            case filelib:is_dir(filename:join(["..", priv])) of
                true ->
                    filename:join(["..", priv, native, liblith_nif]);
                _ ->
                    filename:join([priv, native, liblith_nif])
            end;
        Dir ->
            filename:join([Dir, native, liblith_nif])
    end,
    erlang:load_nif(SoName, 0).

%% Stub functions (replaced by NIF)
version() ->
    erlang:nif_error(nif_not_loaded).

db_open(_Path) ->
    erlang:nif_error(nif_not_loaded).

db_close(_Handle) ->
    erlang:nif_error(nif_not_loaded).

txn_begin(_Handle, _Mode) ->
    erlang:nif_error(nif_not_loaded).

txn_commit(_Txn) ->
    erlang:nif_error(nif_not_loaded).

txn_abort(_Txn) ->
    erlang:nif_error(nif_not_loaded).

apply(_Txn, _CborBinary) ->
    erlang:nif_error(nif_not_loaded).

schema(_Handle) ->
    erlang:nif_error(nif_not_loaded).

journal(_Handle, _Since) ->
    erlang:nif_error(nif_not_loaded).
