// SPDX-License-Identifier: PMPL-1.0-or-later
// Erlang NIF helpers - C wrappers for inline functions
//
// These wrappers allow Zig to call Erlang NIF inline functions
// without dealing with C varargs compatibility issues.

#include <erl_nif.h>

// Wrapper for enif_make_tuple2 (inline function in erl_nif.h)
ERL_NIF_TERM nif_make_tuple2(ErlNifEnv* env, ERL_NIF_TERM t1, ERL_NIF_TERM t2) {
    return enif_make_tuple2(env, t1, t2);
}

// Wrapper for enif_make_tuple3 (inline function in erl_nif.h)
ERL_NIF_TERM nif_make_tuple3(ErlNifEnv* env, ERL_NIF_TERM t1, ERL_NIF_TERM t2, ERL_NIF_TERM t3) {
    return enif_make_tuple3(env, t1, t2, t3);
}
