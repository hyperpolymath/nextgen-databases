# Security Policy


We take security seriously. We appreciate your efforts to responsibly disclose vulnerabilities and will make every effort to acknowledge your contributions.

## Table of Contents

- [Reporting a Vulnerability](#reporting-a-vulnerability)
- [What to Include](#what-to-include)
- [Response Timeline](#response-timeline)
- [Disclosure Policy](#disclosure-policy)
- [Scope](#scope)
- [Safe Harbour](#safe-harbour)
- [Security Updates](#security-updates)
- [Security Architecture](#security-architecture)
- [Development Security](#development-security)

---

## Reporting a Vulnerability

### Preferred Method: GitHub Security Advisories

The preferred method for reporting security vulnerabilities is through GitHub's Security Advisory feature:

1. Navigate to [Report a Vulnerability](https://github.com/hyperpolymath/lithoglyph/security/advisories/new)
2. Click **"Report a vulnerability"**
3. Complete the form with as much detail as possible
4. Submit — we'll receive a private notification

This method ensures:

- End-to-end encryption of your report
- Private discussion space for collaboration
- Coordinated disclosure tooling
- Automatic credit when the advisory is published

### Alternative: Email

If you cannot use GitHub Security Advisories, you may email us directly:

| | |
|---|---|
| **Email** | j.d.a.jewell@open.ac.uk |

> **Important:** Do not report security vulnerabilities through public GitHub issues, pull requests, discussions, or social media.

---

## What to Include

A good vulnerability report helps us understand and reproduce the issue quickly.

### Required Information

- **Description**: Clear explanation of the vulnerability
- **Impact**: What an attacker could achieve (confidentiality, integrity, availability)
- **Affected versions**: Which versions/commits are affected
- **Reproduction steps**: Detailed steps to reproduce the issue

### Helpful Additional Information

- **Proof of concept**: Code, scripts, or screenshots demonstrating the vulnerability
- **Attack scenario**: Realistic attack scenario showing exploitability
- **CVSS score**: Your assessment of severity (use [CVSS 3.1 Calculator](https://www.first.org/cvss/calculator/3.1))
- **CWE ID**: Common Weakness Enumeration identifier if known
- **Suggested fix**: If you have ideas for remediation
- **References**: Links to related vulnerabilities, research, or advisories

### Example Report Structure

```markdown
## Summary
[One-sentence description of the vulnerability]

## Vulnerability Type
[e.g., Buffer overflow, Memory corruption, Input validation, etc.]

## Affected Component
[File path, function name, API endpoint, etc.]

## Steps to Reproduce
1. [Step 1]
2. [Step 2]
3. [Step 3]

## Impact
[What could an attacker achieve?]

## Suggested Fix
[Optional: Your ideas for remediation]
```

---

## Response Timeline

| Stage | Target |
|-------|--------|
| Acknowledgement | Within 48 hours |
| Initial assessment | Within 1 week |
| Fix development | Depends on severity |
| Disclosure | Coordinated, after fix available |

**Severity-based response:**

| Severity | Fix Target |
|----------|------------|
| Critical | 72 hours |
| High | 1 week |
| Medium | 2 weeks |
| Low | Next release |

---

## Disclosure Policy

We follow coordinated disclosure:

1. Reporter submits vulnerability privately
2. We acknowledge receipt within 48 hours
3. We develop and test a fix
4. We release the fix and publish an advisory
5. Reporter is credited (unless they prefer anonymity)

We request a 90-day disclosure window. If we cannot fix the issue within 90 days, we will work with the reporter on a reasonable timeline.

---

## Scope

### In Scope

- **core-zig bridge** (core-zig/) — C ABI boundary, memory safety
- **core-forth kernel** (core-forth/) — Block storage, journal integrity
- **Idris2 ABI** (src/Lith/) — Type safety, proof soundness
- **Lean 4 normalizer** (normalizer/) — Proof correctness
- **BEAM NIFs** (beam/) — Native function interface safety
- **lith-http** (lith-http/) — HTTP API, authentication, rate limiting
- **GQL-DT** (gql-dt/) — Query injection, type confusion
- **Container configurations** — Image security, secrets management
- **CI/CD workflows** — Supply chain security

### Out of Scope

- **studio** (Tauri GUI) — Pre-alpha, returns mock data only
- **api** (Zig HTTP) — Known broken, not deployed
- Third-party dependencies (report upstream)
- Social engineering attacks
- Physical access attacks

---

## Safe Harbour

We consider security research conducted consistent with this policy to be:

- Authorized concerning any applicable anti-hacking laws
- Authorized concerning any relevant anti-circumvention laws
- Exempt from restrictions in our Terms of Service that would interfere with conducting security research

We will not pursue legal action against researchers who:

- Act in good faith
- Avoid privacy violations, data destruction, or service disruption
- Report findings promptly
- Do not exploit vulnerabilities beyond proof-of-concept

---

## Security Updates

Security updates are distributed through:

- GitHub Security Advisories
- CHANGELOG.md entries marked `[SECURITY]`
- Git tags with security notes

---

## Security Architecture

Lithoglyph is designed with security as a core principle across its multi-language stack:

### Auditability (Narrative Provenance)
- All mutations are journaled in WAL before commitment to blocks
- Full provenance tracking — every change has who, what, when, why
- Deterministic rendering for human verification
- Cryptographic hashes in provenance chains

### Reversibility
- Every operation has a defined inverse
- Irreversible operations are explicitly marked and require confirmation
- Complete history is preserved in the journal

### Formal Verification
- **Idris2 ABI proofs**: Memory layout, alignment, packing verified with dependent types
- **Zero `believe_me`**: Hard invariant — no trust shortcuts in ABI definitions
- **Lean 4 normalization proofs**: Schema correctness verified at compile time
- **GQL-DT**: Query correctness verified with dependent types

### Memory Safety
- **Zig bridge**: All unsafe casts require `// SAFETY:` comments explaining correctness
- **Rust NIFs**: Safe Rustler 0.35 API, 0 compiler warnings
- **Forth kernel**: Stack-based — bounded memory model

### Constraint Enforcement
- Constraints enforced at the bridge layer (core-zig)
- Rejections include explanations (not silent failures)
- Parameterized query builders — no SQL injection surface

### Container Security
- Base images: Chainguard (`cgr.dev/chainguard/wolfi-base:latest`)
- Image signing: cerro-torre with ML-DSA-87 post-quantum crypto
- Secret rotation: rokur with argon2id
- TLS termination: svalinn gateway with policy enforcement
- Runtime verification: vordr formal proof checking

## Development Security

- Dependencies are pinned to specific versions/SHAs
- All GitHub Actions workflows use SHA-pinned actions
- SPDX license headers on all source files
- Hypatia neurosymbolic scanner runs on every PR
- Echidnabot detects dangerous patterns (`believe_me`, `sorry`, unsafe casts)
- TruffleHog scans for leaked secrets
- OpenSSF Scorecard measures supply chain health

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.0.7 (current) | Development — security fixes applied |
| < 0.0.7 | Not supported |
