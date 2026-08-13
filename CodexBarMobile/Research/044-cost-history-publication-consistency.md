# Cost History Publication Consistency

Status: implemented

## Problem

A bounded Codex history rebuild could publish a partially reconciled day. The
day still carried aggregate tokens, but a model whose Standard/Fast pricing was
not reconciled yet had no cost. The Mac sync mapper omitted that model and the
iPhone accepted the newer, smaller model mix and dollar total.

## Contract

- The Mac scanner retains the last complete report while a bounded rebuild is
  pending and promotes the replacement only after the rebuild converges.
- `SyncCostSummary.historyCoverageIsEstablished` carries scan completeness as
  an additive optional field. Pricing estimation remains a separate signal.
- Cost-history quality is ordered as complete, legacy/unknown, then partial.
  A lower-quality incoming snapshot cannot overwrite or remove higher-quality
  daily points, though it may add a previously absent day.
- A later complete snapshot is authoritative, including legitimate downward
  corrections.
- Mobile reconciles history in its live snapshot cache and before SwiftData
  persistence. Existing opaque JSON blobs carry the new field, so no CloudKit
  or SwiftData schema migration is required.

## Verification

- Scanner regression coverage exercises an automatically captured previous
  report through bounded rebuild and convergence.
- Shared wire tests cover old payload decoding and complete/partial/legacy
  reconciliation.
- Mobile cache tests cover incremental rejection of a partial downgrade and
  later complete replacement.
- CloudKit merge tests cover tri-state completeness propagation.

