;; SPDX-License-Identifier: PMPL-1.0-or-later
;; Lith Security Requirements
;; Comprehensive cryptographic and security standards

(define user-security-requirements
  '(
    ;; =================================================================
    ;; CRYPTOGRAPHIC PRIMITIVES
    ;; =================================================================

    ;; Password Hashing
    (PasswordHashing
      (algorithm "Argon2id")
      (memory-cost "512 MiB")
      (iterations 8)
      (parallelism 4)
      (rationale "Maximum memory/iterations for GPU/ASIC resistance; aligns with proactive security stance."))

    ;; General Hashing
    (GeneralHashing
      (algorithm "SHAKE3-512")
      (output-size "512-bit")
      (standard "FIPS 202")
      (use-cases ("provenance" "key-derivation" "long-term-storage"))
      (rationale "Post-quantum secure; use for all hash operations."))

    ;; Post-Quantum Signatures
    (PQSignatures
      (primary "Dilithium5-AES")
      (standard "ML-DSA-87 (FIPS 204)")
      (mode "hybrid")
      (classical-component "AES-256")
      (fallback "SPHINCS+")
      (rationale "Hybrid with AES-256 for belt-and-suspenders security. SPHINCS+ as conservative backup."))

    ;; Post-Quantum Key Exchange
    (PQKeyExchange
      (primary "Kyber-1024")
      (standard "ML-KEM-1024 (FIPS 203)")
      (kdf "SHAKE256-KDF")
      (fallback "SPHINCS+")
      (rationale "Kyber-1024 for KEM, SHAKE256 for key derivation. SPHINCS+ as backup."))

    ;; Classical Signatures (Transition)
    (ClassicalSignatures
      (primary "Ed448")
      (hybrid-mode "Ed448 + Dilithium5")
      (fallback "SPHINCS+")
      (deprecated ("Ed25519" "SHA-1"))
      (terminate-immediately ("Ed25519" "SHA-1"))
      (rationale "Ed448 for classical compatibility; Dilithium5 for PQ. Terminate Ed25519/SHA-1 immediately."))

    ;; Symmetric Encryption
    (SymmetricEncryption
      (algorithm "XChaCha20-Poly1305")
      (key-size "256-bit")
      (rationale "Larger nonce space; 256-bit keys for quantum margin."))

    ;; Key Derivation
    (KeyDerivation
      (algorithm "HKDF-SHAKE512")
      (standard "FIPS 202")
      (use-cases ("all-secret-key-material"))
      (rationale "Post-quantum KDF; use with all secret key material."))

    ;; Random Number Generation
    (RNG
      (algorithm "ChaCha20-DRBG")
      (seed-size "512-bit")
      (standard "SP 800-90Ar1")
      (rationale "CSPRNG for deterministic, high-entropy needs."))

    ;; =================================================================
    ;; USER-FRIENDLY FEATURES
    ;; =================================================================

    (UserFriendlyHashNames
      (algorithm "Base32(SHAKE256(hash)) → Wordlist")
      (purpose "Memorable, deterministic mapping")
      (example "Gigantic-Giraffe-7 for drivers")
      (rationale "Human-readable identifiers derived from cryptographic hashes."))

    ;; =================================================================
    ;; DATABASE & STORAGE
    ;; =================================================================

    (DatabaseHashing
      (performance "BLAKE3 (512-bit)")
      (long-term-storage "SHAKE3-512")
      (semantic-tags ("XML" "ARIA"))
      (rationale "BLAKE3 for speed, SHAKE3-512 for long-term storage (semantic XML/ARIA tags)."))

    (SemanticXMLGraphQL
      (database "Virtuoso (VOS)")
      (query-language "SPARQL 1.2")
      (accessibility ("WCAG 2.3 AAA" "ARIA"))
      (formal-verification true)
      (rationale "Supports WCAG 2.3 AAA, ARIA, and formal verification for accessibility/compliance."))

    ;; =================================================================
    ;; EXECUTION ENVIRONMENT
    ;; =================================================================

    (VMExecution
      (platform "GraalVM")
      (formal-verification true)
      (rationale "Aligns with preference for introspective, reversible design."))

    ;; =================================================================
    ;; NETWORK & PROTOCOL
    ;; =================================================================

    (ProtocolStack
      (transport "QUIC")
      (http "HTTP/3")
      (ip "IPv6")
      (disabled ("HTTP/1.1" "IPv4" "SHA-1"))
      (danger-zone-termination ("HTTP/1.1" "IPv4" "SHA-1"))
      (rationale "Terminate HTTP/1.1, IPv4, and SHA-1 per \"danger zone\" policy."))

    ;; =================================================================
    ;; ACCESSIBILITY & UI
    ;; =================================================================

    (Accessibility
      (standard "WCAG 2.3 AAA")
      (aria true)
      (semantic-xml true)
      (design-approach "CSS-first, HTML-second")
      (rationale "Full compliance with accessibility requirements."))

    ;; =================================================================
    ;; CRYPTOGRAPHIC FALLBACK
    ;; =================================================================

    (Fallback
      (algorithm "SPHINCS+")
      (purpose "Conservative PQ backup for all hybrid classical+PQ systems")
      (use-case "If primary PQ algorithm is ever compromised")
      (rationale "Belt-and-suspenders approach to post-quantum security."))

    ;; =================================================================
    ;; FORMAL VERIFICATION
    ;; =================================================================

    (FormalVerification
      (tools ("Coq" "Isabelle"))
      (purpose "Crypto primitives verification")
      (principles ("proactive-attestation" "transparent-logic"))
      (rationale "Aligns with system design principles for formal correctness."))

    ;; =================================================================
    ;; SECURITY POLICY
    ;; =================================================================

    (SecurityPolicy
      (stance "Proactive")
      (quantum-resistance "Required")
      (hybrid-approach "Classical + PQ for all critical operations")
      (termination-policy "Immediate removal of deprecated algorithms")
      (belt-and-suspenders "Multiple layers of security (primary + fallback)"))
  ))

;; =================================================================
;; IMPLEMENTATION PRIORITIES FOR LITHOGLYPH
;; =================================================================

(define lith-security-implementation
  '(
    ;; M11: Current Milestone
    (M11
      (focus "HTTP API security")
      (requirements
        (https "TLS 1.3 with QUIC")
        (authentication "JWT with HMAC-SHA256 (transition to SHAKE512)")
        (rate-limiting "Redis-backed distributed rate limiting")
        (cbor-validation "Strict CBOR major type checking")))

    ;; M12: Production Security
    (M12
      (focus "Post-quantum cryptography integration")
      (requirements
        (signatures "Ed448 + Dilithium5 hybrid")
        (key-exchange "Kyber-1024 with SHAKE256-KDF")
        (symmetric "XChaCha20-Poly1305")
        (password-hashing "Argon2id (512 MiB, 8 iter, 4 lanes)")
        (provenance-hashing "SHAKE3-512")))

    ;; M13: Full PQ Migration
    (M13
      (focus "Complete post-quantum migration")
      (requirements
        (terminate ("Ed25519" "SHA-1" "SHA-256"))
        (upgrade-all-systems "Dilithium5 + SPHINCS+ fallback")
        (formal-verification "Coq proofs for all crypto primitives")))

    ;; M14: Advanced Security
    (M14
      (focus "GraalVM integration + formal verification")
      (requirements
        (vm "GraalVM with formal verification")
        (accessibility "WCAG 2.3 AAA + ARIA")
        (semantic-web "Virtuoso VOS + SPARQL 1.2")
        (network "QUIC + HTTP/3 + IPv6 only")))
  ))

;; =================================================================
;; LITHOGLYPH CRYPTO LIBRARY STACK
;; =================================================================

(define lith-crypto-stack
  '(
    (layer "Password Hashing")
      (library "rust-argon2")
      (config "512 MiB memory, 8 iterations, 4 lanes")

    (layer "General Hashing")
      (library "tiny-keccak (SHAKE3)")
      (config "512-bit output")

    (layer "Post-Quantum Signatures")
      (library "pqcrypto-dilithium (ML-DSA)")
      (variant "Dilithium5-AES")
      (fallback "pqcrypto-sphincsplus (SPHINCS+)")

    (layer "Post-Quantum KEM")
      (library "pqcrypto-kyber (ML-KEM)")
      (variant "Kyber-1024")
      (kdf "tiny-keccak (SHAKE256)")

    (layer "Symmetric Encryption")
      (library "chacha20poly1305")
      (variant "XChaCha20-Poly1305")
      (key-size "256-bit")

    (layer "Classical Signatures")
      (library "ed25519-dalek")
      (variant "Ed448")
      (note "Transition to hybrid Ed448 + Dilithium5")

    (layer "Key Derivation")
      (library "hkdf + tiny-keccak")
      (algorithm "HKDF-SHAKE512")

    (layer "Random Number Generation")
      (library "rand_chacha")
      (algorithm "ChaCha20-DRBG")
      (seed-size "512-bit")
  ))

;; =================================================================
;; DANGER ZONE - IMMEDIATE TERMINATION
;; =================================================================

(define algorithms-to-terminate-immediately
  '(
    "SHA-1"       ;; Broken
    "Ed25519"     ;; Inadequate for PQ era
    "MD5"         ;; Completely broken
    "HTTP/1.1"    ;; Replaced by HTTP/3
    "IPv4"        ;; Replaced by IPv6
  ))

;; =================================================================
;; EXPORT
;; =================================================================

(provide 'user-security-requirements
         'lith-security-implementation
         'lith-crypto-stack
         'algorithms-to-terminate-immediately)
