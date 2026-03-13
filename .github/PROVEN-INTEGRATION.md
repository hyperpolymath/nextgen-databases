# proven Integration Plan

This document outlines the recommended [proven](https://github.com/hyperpolymath/proven) modules for Glyphbase.

## Recommended Modules

| Module | Purpose | Priority |
|--------|---------|----------|
| SafeTransaction | ACID transactions with isolation proofs for spreadsheet operations | High |
| SafeSchema | Schema migration with compatibility proofs for table structure changes | High |
| SafeOrdering | Temporal ordering with causality proofs for change tracking | High |
| SafeProvenance | Change tracking with audit proofs for "who changed what when" | High |

## Integration Notes

Glyphbase as an open-source Airtable alternative that "remembers everything" requires:

- **SafeTransaction** ensures spreadsheet operations maintain ACID properties. Cell edits, row insertions, and bulk operations are either fully committed or fully rolled back, preventing partial state corruption.

- **SafeSchema** manages table schema evolution with formal compatibility guarantees. The `isBackwardCompatible` check ensures existing data remains readable after schema changes, and `MigrationChain` verifies migration sequences are contiguous.

- **SafeOrdering** tracks the ordering of changes with verified causality. When multiple users edit concurrently, vector clocks determine the correct merge order.

- **SafeProvenance** is core to Glyphbase's value proposition - tracking who made what change when. The `ProvenanceChain` provides tamper-evident history, and `Lineage` tracks how each cell value was derived.

These modules together enable Glyphbase's promise of complete change tracking with mathematical guarantees.

## Related

- [proven library](https://github.com/hyperpolymath/proven)
- [Idris 2 documentation](https://idris2.readthedocs.io/)
