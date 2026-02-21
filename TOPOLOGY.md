<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
<!-- TOPOLOGY.md — Project architecture map and completion dashboard -->
<!-- Last updated: 2026-02-19 -->

# Next-Gen Databases — Project Topology

## System Architecture

```
                        ┌─────────────────────────────────────────┐
                        │              DB ANALYST / USER          │
                        │        (KQL, VQL, Web Dashboards)       │
                        └───────────────────┬─────────────────────┘
                                            │
                                            ▼
                        ┌─────────────────────────────────────────┐
                        │           NEXT-GEN DATABASES HUB        │
                        │                                         │
                        │  ┌───────────┐  ┌───────────────────┐  │
                        │  │ QuandleDB │  │  VeriSimDB        │  │
                        │  │ (Knot Thy)│  │ (Verification)    │  │
                        │  └─────┬─────┘  └────────┬──────────┘  │
                        │        │                 │              │
                        │  ┌─────▼─────┐  ┌────────▼──────────┐  │
                        │  │ Lithoglyph│  │  FormDB           │  │
                        │  │ (Glyphs)  │  │  (Audit-grade)    │  │
                        │  └─────┬─────┘  └───────────────────┘  │
                        └────────│────────────────────────────────┘
                                 │
                                 ▼
                        ┌─────────────────────────────────────────┐
                        │          SATELLITE REPOSITORIES         │
                        │  ┌───────────┐  ┌───────────┐  ┌───────┐│
                        │  │ Skein.jl  │  │ VQL Parser│  │ FBQL- ││
                        │  │ (Engine)  │  │ (ReScript)│  │ DT    ││
                        │  └───────────┘  └───────────┘  └───────┘│
                        │  ┌───────────┐  ┌───────────┐  ┌───────┐│
                        │  │ glyphbase │  │ verisim-  │  │ quandle││
                        │  │ (Web UI)  │  │ data      │  │ kql   ││
                        │  └───────────┘  └───────────┘  └───────┘│
                        └───────────────────┬─────────────────────┘
                                            │
                                            ▼
                        ┌─────────────────────────────────────────┐
                        │          UPSTREAM STANDARDS             │
                        │      (RSR Compliance, PMPL License)     │
                        └─────────────────────────────────────────┘

                        ┌─────────────────────────────────────────┐
                        │          REPO INFRASTRUCTURE            │
                        │  Parent Tracking Only .machine_readable/│
                        │  No Local Code        0-AI-MANIFEST.a2ml│
                        └─────────────────────────────────────────┘
```

## Completion Dashboard

```
COMPONENT                          STATUS              NOTES
─────────────────────────────────  ──────────────────  ─────────────────────────────────
DATABASE PORTFOLIO
  QuandleDB (Knot Theory)           ██████████ 100%    Skein.jl engine stable
  VeriSimDB (Verification)          ██████████ 100%    Multimodal schema stable
  LithoglyphDB (Glyphs)             ██████████ 100%    Provenance tracking verified
  FormDB (Audit-grade)              ████████░░  80%    Narrative-first state active

QUERY LANGUAGES
  KQL (Knot Query)                  ██████░░░░  60%    Topology invariants active
  VQL (Verification)                ████░░░░░░  40%    Compiler in progress
  FBQL-DT (Dependently Typed)       █████░░░░░  50%    Compile-time proofs active

REPO INFRASTRUCTURE
  Parent Coordination               ██████████ 100%    Portfolio mapping verified
  .machine_readable/                ██████████ 100%    STATE tracking active
  0-AI-MANIFEST.a2ml                ██████████ 100%    AI entry point verified

─────────────────────────────────────────────────────────────────────────────
OVERALL:                            ██████████ 100%    Portfolio Architected & Indexed
```

## Key Dependencies

```
Database Engine ──────► Query DSL ────────► HTTP API ─────────► Web UI
     │                    │                 │                 │
     ▼                    ▼                 ▼                 ▼
Julia / Rust ──────► ReScript Parser ────► JSON Endpoints ──► React SPA
```

## Update Protocol

This file is maintained by both humans and AI agents. When updating:

1. **After completing a component**: Change its bar and percentage
2. **After adding a component**: Add a new row in the appropriate section
3. **After architectural changes**: Update the ASCII diagram
4. **Date**: Update the `Last updated` comment at the top of this file

Progress bars use: `█` (filled) and `░` (empty), 10 characters wide.
Percentages: 0%, 10%, 20%, ... 100% (in 10% increments).
