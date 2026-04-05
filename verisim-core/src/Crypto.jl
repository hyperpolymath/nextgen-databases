# SPDX-License-Identifier: PMPL-1.0-or-later
#
# Crypto.jl — Ed25519 signing for VeriSimCore / federation peers.
#
# Thin wrapper over libsodium's crypto_sign_ed25519 primitives (via
# Sodium.jl's LibSodium submodule). Replaces the Phase 3 placeholder
# SHA-256-based signing scheme with real cryptographic signatures.
#
# Grounded in TeX §7.1 (Multi-Party Signature Verification) and
# thm:attestation: "Ed25519 Verification: ~10ms per signature".
#
# Key sizes (libsodium Ed25519):
#   public key:  32 bytes
#   secret key:  64 bytes (private component + public component)
#   signature:   64 bytes

module Crypto

using Sodium: LibSodium

export Ed25519KeyPair, generate_keypair, sign_detached, verify_detached,
       ED25519_PK_BYTES, ED25519_SK_BYTES, ED25519_SIG_BYTES

const ED25519_PK_BYTES  = 32
const ED25519_SK_BYTES  = 64
const ED25519_SIG_BYTES = 64

"""
Ed25519 keypair. `pk` is the public key (32 bytes); `sk` is the secret
key (64 bytes — libsodium packs the private seed + derived public key).
"""
struct Ed25519KeyPair
    pk::Vector{UInt8}
    sk::Vector{UInt8}
    function Ed25519KeyPair(pk::Vector{UInt8}, sk::Vector{UInt8})
        length(pk) == ED25519_PK_BYTES || throw(ArgumentError(
            "Ed25519 public key must be $ED25519_PK_BYTES bytes, got $(length(pk))"))
        length(sk) == ED25519_SK_BYTES || throw(ArgumentError(
            "Ed25519 secret key must be $ED25519_SK_BYTES bytes, got $(length(sk))"))
        new(pk, sk)
    end
end

"""
    generate_keypair() -> Ed25519KeyPair

Generate a fresh Ed25519 keypair via libsodium's CSPRNG.
"""
function generate_keypair()::Ed25519KeyPair
    pk = zeros(UInt8, ED25519_PK_BYTES)
    sk = zeros(UInt8, ED25519_SK_BYTES)
    r = LibSodium.crypto_sign_ed25519_keypair(pk, sk)
    r == 0 || error("Crypto.generate_keypair: libsodium returned $r")
    Ed25519KeyPair(pk, sk)
end

"""
    sign_detached(kp, msg) -> Vector{UInt8}

Produce a detached Ed25519 signature (64 bytes) over `msg` using the
secret key in `kp`.
"""
function sign_detached(kp::Ed25519KeyPair, msg::AbstractVector{UInt8})::Vector{UInt8}
    sig = zeros(UInt8, ED25519_SIG_BYTES)
    siglen = Ref{UInt64}(0)
    msg_copy = collect(msg)  # ensure contiguous Vector{UInt8}
    r = LibSodium.crypto_sign_ed25519_detached(
        sig, siglen, msg_copy, UInt64(length(msg_copy)), kp.sk,
    )
    r == 0 || error("Crypto.sign_detached: libsodium returned $r")
    siglen[] == ED25519_SIG_BYTES || error(
        "Crypto.sign_detached: unexpected sig length $(siglen[])")
    sig
end

"""
    verify_detached(pk, sig, msg) -> Bool

Verify a detached Ed25519 signature. Returns true iff the signature
was produced by the holder of the secret key corresponding to `pk`
over the given `msg`.
"""
function verify_detached(pk::AbstractVector{UInt8},
                         sig::AbstractVector{UInt8},
                         msg::AbstractVector{UInt8})::Bool
    length(pk) == ED25519_PK_BYTES || return false
    length(sig) == ED25519_SIG_BYTES || return false
    pk_copy  = collect(pk)
    sig_copy = collect(sig)
    msg_copy = collect(msg)
    r = LibSodium.crypto_sign_ed25519_verify_detached(
        sig_copy, msg_copy, UInt64(length(msg_copy)), pk_copy,
    )
    r == 0
end

end # module
