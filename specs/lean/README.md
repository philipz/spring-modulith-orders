# Lean 4 verification of the order lifecycle rules R1-R6

This directory is the formal-verification artifact for the business rules R1-R6 that
`specs/order-lifecycle/source.md` (owner-confirmed on 2026-10-23) specifies for
`OrderService` in `philipz/spring-modulith-orders`. It follows the
`lean-formal-verification` skill (Carl M. Kadie's nine rules): confirmed rules, a model of
the decisions, theorem statements written from the rules, human + adversarial review, and
a machine-checked proof with guardrails.

**What Lean checks is the model, not the Java code.** The model<->code correspondence is a
manual audit, recorded with file:line references in `MODEL-MAP.md`; there is no automatic
Java->Lean bridge.

## What is verified

| Rule | Property proved about the model | Theorems |
|---|---|---|
| R1 | The status set has exactly eight statuses; creation with no status or with `NEW` yields `NEW`, every other requested status is rejected; a created order's first committed write is `NEW` at version 0. | `r1_create_none`, `r1_create_new`, `r1_create_other_rejected`, `r1_create_iff`, `r1_created_initial_write`, `r1_all_statuses` |
| R2 | For normal-flow targets, a transition is permitted exactly when the target rank is the source rank plus one (no jumps, no backwards moves). | `r2_permitted_normal_iff_rank_succ` |
| R3 | `CANCELLED` is permitted exactly from `NEW` and `PENDING`. | `r3_permitted_cancel_iff` |
| R4 | `ERROR` is permitted exactly from `NEW`, `PENDING`, `CONFIRMED`, `IN_PROCESS`. | `r4_permitted_error_iff` |
| R5 | `DELIVERED`/`CANCELLED`/`ERROR` are terminal; same-state writes and writes to `NEW` are rejected; the permitted relation is exactly the 11-pair state-machine table. | `r5_terminal_no_outgoing`, `r5_same_state_rejected`, `r5_to_new_rejected`, `r5_permitted_iff_allowedPairs` |
| R6 | A commit succeeds only on a fresh read of a permitted transition and bumps the version; stale-version commits are rejected and leave the committed state unchanged (no lost update); two transactions that read the same version cannot both commit; every committed history is sequential and fresh (each committed write read the immediately previous committed status/version), by induction over the trace. | `r6_commit_implies_permitted_and_bumped`, `r6_stale_commit_rejected`, `r6_stale_commit_keeps_state`, `r6_same_version_cannot_both_commit`, `r6_terminal_commit_rejected`, `r6_trace_commits_permitted`, `r6_trace_fresh_reads`, `r6_trace_versions_increment`, `r6_trace_consecutive_fresh`, `r6_trace_no_commit_from_terminal` |

`Specs/Examples.lean` instantiates every rule and every theorem's hypotheses with concrete
values (non-vacuity), including a committed history that reaches `DELIVERED` and the stale
shipped-order-cancelled scenario from `docs/orders-optimistic-locking.md`.

## How to run

Requires the pinned toolchain (elan will fetch it from `lean-toolchain`; no Mathlib, no
network needed after the toolchain is installed):

```bash
export PATH="$HOME/.elan/bin:$PATH"
cd specs/lean
lake build                  # full build; includes Specs/Examples via Specs.lean
lake env lean Audit.lean    # #print axioms for all headline theorems
```

Expected audit output: 23 lines, each `'Specs.<theorem>' depends on axioms: [propext]`
(or `[propext, Quot.sound]` for `r6_same_version_cannot_both_commit`). Only `propext`,
`Classical.choice` and `Quot.sound` are allowed; `sorryAx`, `Lean.ofReduceBool` and
`Lean.trustCompiler` would be guardrail failures.

Guardrail scan (all must print nothing):

```bash
grep -rnE '\b(sorry|admit|native_decide)\b' --include='*.lean' specs/lean
grep -rnE '^[[:space:]]*(axiom|constant|unsafe|extern)[[:space:]]|@\[implemented_by' --include='*.lean' specs/lean
grep -rn 'warn.sorry' --include='*.lean' specs/lean
```

The verification script is installed with the skill. Run it from the repo root:

```bash
bash ~/.agents/skills/lean-formal-verification/scripts/verify-lean.sh \
  --dir specs/lean --main Specs/Rules.lean --audit Audit.lean \
  --theorems headline-theorems.txt [--baseline metrics-baseline.txt]
```

It gates on clean build, direct compile of the main file, compile coverage of every
other `.lean` file, the comment-stripped guardrail scan, the axiom audit and audit
completeness (`headline-theorems.txt`), then prints the Rule-4 terminal dashboard
(`--watch` for continuous runs, `--json` for machines). `metrics-baseline.txt` is the
first green baseline; re-runs compare against it.

## Files

| File | Purpose |
|---|---|
| `RULES.md` | Owner-confirmed rules R1-R6 (phase 0 output): statements, examples, boundaries, out-of-scope, change policy. |
| `MODEL-MAP.md` | Honesty ledger: verified commit, source line ranges, rule -> theorem -> model-def -> source-lines table, abstraction ledger, not-covered list, review and re-sync logs. |
| `Specs/Model.lean` | The abstraction: statuses, transition predicates, creation result, versioned write model and committed-trace datatypes. |
| `Specs/Proofs.lean` | Shared proof library used by the rule theorems. |
| `Specs/Rules.lean` | Rule statements R1-R6 with complete proofs (no placeholders). |
| `Specs/Examples.lean` | Concrete non-vacuity examples and the delivered committed history. |
| `Specs.lean` | Root import of all modules. |
| `Audit.lean` | `#print axioms` for every headline theorem. |
| `headline-theorems.txt` | Fully-qualified headline theorem names for the audit completeness gate. |
| `metrics-baseline.txt` | Rule-4 dashboard baseline from the first green run. |

## Re-syncing after a code change

Follow the procedure in `MODEL-MAP.md` (`Re-sync procedure`): diff the verified sources,
map each changed decision, update the model then statements then proofs, and re-run the
build/audit/guardrails. Never weaken a confirmed theorem to make it pass - if a rule
changed, stop and re-run phase 0 with the owner.

## Scope limits

This is a safety verification of the model's state machine and versioned-write rule. It
does not cover database isolation/transaction mechanics, retry policy, caches, events,
logging, performance, cross-order behaviour, concurrency liveness, or null/unknown status
values; the full list is in `MODEL-MAP.md` ("Explicitly not covered"). The model<->code
link is a reviewed claim, not a mechanically checked one.
