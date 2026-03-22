%% SPDX-License-Identifier: MPL-2.0
%% Test helper — coerce any Erlang term to Dynamic for formatter tests.
%% On the Erlang target, Dynamic is just any term — this is identity.
-module(test_ffi).
-export([to_dynamic/1]).

-spec to_dynamic(term()) -> term().
to_dynamic(X) -> X.
