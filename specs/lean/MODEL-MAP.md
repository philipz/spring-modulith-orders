# Model map - Lean model <-> verified sources

> The honesty ledger for the verification. If a claim is not recorded here, it is not
> covered. Lean proves properties of the model in `Specs/`; the link from that model to the
> Java code is the manual review recorded in this file (there is no automatic
> implementation<->Lean bridge).

- **Target repo:** `philipz/spring-modulith-orders`
- **Verified at commit:** `4f7cf95` (`4f7cf95187828d998e88b1422d521d76d2893d36`, branch `main`, commit date 2026-09-27); verification run 2026-10-23
- **Rules of record:** `RULES.md` (confirmed 2026-10-23 by `philipz (owner)`)
- **Toolchain:** Lean `4.35.0` (from `lean-toolchain`), Lake `5.0.0-src+eb6cafb`, **no Mathlib** (core Lean only)

## Artifact layout

| File | Lines | Purpose |
|---|---|---|
| `Specs/Model.lean` | 190 | The abstraction: `OrderStatus` (8 constructors), transition predicates, `createStatus`/`createInitialState`, versioned write model (`OrderState`, `Txn`, `commit?`, `commitOrKeep`, `CommitStep`, `TraceValid`, `ConsecutiveFresh`). |
| `Specs/Proofs.lean` | 109 | Shared proof library (Rule 9): commit characterisation/projection lemmas, `traceValid_cons`, `createStatus_created_new`. |
| `Specs/Rules.lean` | 275 | One section per rule R1-R6: headline theorem statements (written from `RULES.md`) with complete proofs. |
| `Specs/Examples.lean` | 233 | Non-vacuity: concrete instances of every rule and of every theorem's hypotheses; the delivered history `deliveredTraceValid`. |
| `Specs.lean` | 13 | Root module importing Model, Proofs, Rules, Examples (so `lake build` checks all modules, including Examples). |
| `Audit.lean` | 51 | `#print axioms` for all 23 headline theorems. |
| `RULES.md`, `MODEL-MAP.md`, `README.md` | - | Rules of record, this ledger, usage/re-sync notes. |

## Verified sources (what the Lean model claims to describe)

| File | Lines | What is modeled |
|---|---|---|
| `src/main/java/com/sivalabs/bookstore/orders/domain/OrderService.java` | 31-58 | `createOrder`: no status -> `NEW` (40-41); requested non-`NEW` status rejected (42-44); persist (46). |
| `src/main/java/com/sivalabs/bookstore/orders/domain/OrderService.java` | 96-115 | `updateOrderStatus`: read current status (101-103); `isPermittedTransition` guard (105-109); write new status (110-111). |
| `src/main/java/com/sivalabs/bookstore/orders/domain/OrderService.java` | 117-136 | `cancelOrder`: read current status (124-126); `canBeCancelled` guard (128-131); write `CANCELLED` (133-134). |
| `src/main/java/com/sivalabs/bookstore/orders/domain/OrderService.java` | 138-140 | `canBeCancelled`: source-status decision for cancellation (R3). |
| `src/main/java/com/sivalabs/bookstore/orders/domain/OrderService.java` | 142-166 | `isPermittedTransition`: same-state rejection (149-151); switch decisions for target `PENDING`/`CONFIRMED`/`IN_PROCESS`/`SHIPPED`/`DELIVERED` (153-157), `CANCELLED` (158), `ERROR` (159-163), `NEW` (164). |
| `src/main/java/com/sivalabs/bookstore/orders/domain/OrderEntity.java` | 79-87 | `@Version` optimistic-lock discriminator `version` (`Long`, nullable only while unpersisted); a stale write fails instead of overwriting the row. |
| `src/main/java/com/sivalabs/bookstore/orders/api/model/OrderStatus.java` | 6-30 | The eight status constants (`NEW` 8, `PENDING` 11, `CONFIRMED` 14, `IN_PROCESS` 17, `SHIPPED` 20, `DELIVERED` 23, `CANCELLED` 26, `ERROR` 29). |
| `specs/order-lifecycle/source.md` | 8-13 | Authoritative rule text R1-R6 (approved snapshot; read-only). |
| `docs/orders-optimistic-locking.md` | 5-28 | Stale-read overwrite scenario (7-14) and the versioned update semantics (`UPDATE ... WHERE id = ? AND version = ?`, version increment, stale writer fails) (26-28). |
| `docs/orders-optimistic-locking.md` | 46-50 | Caller retry/exception guidance (informative; out of scope). |
| `specs/order-lifecycle/invariants.qnt` | 39-87 | The project's existing transition terminology and invariants (read-only reference for vocabulary, not modified). |

## Rule coverage

Every headline theorem is in this table and maps to a rule in `RULES.md`. Lean line
numbers refer to the current working tree.

| Rule | Theorem (`Specs/Rules.lean`) | Model definition (`Specs/Model.lean`) | Source evidence |
|---|---|---|---|
| R1 | `r1_create_none` (23) | `createStatus` (120-124) | source.md:8; OrderService.java:40-41 |
| R1 | `r1_create_new` (26) | `createStatus` (120-124) | source.md:8; OrderService.java:42-44 |
| R1 | `r1_create_other_rejected` (29) | `createStatus` (120-124) | OrderService.java:42-44 |
| R1 | `r1_create_iff` (35) | `createStatus` (120-124) | source.md:8; OrderService.java:40-44 |
| R1 | `r1_created_initial_write` (43) | `createInitialState` (158-160), `OrderState` (129-132) | OrderService.java:40-46; OrderEntity.java:79-87; docs:26-28 |
| R1 | `r1_all_statuses` (57) | `OrderStatus` (18-27), `allStatuses` (32-33) | source.md:8; OrderStatus.java:6-30 |
| R2 | `r2_permitted_normal_iff_rank_succ` (64) | `isNormal` (38-47), `normalRank` (49-58), `rankSucc?` (60-63), `rankStep` (65-67), `isPermitted` (94-106) | source.md:9; OrderService.java:152-157 |
| R3 | `r3_permitted_cancel_iff` (73) | `canCancelFrom` (69-73), `isPermitted` (104) | source.md:10; OrderService.java:138-140, 158 |
| R4 | `r4_permitted_error_iff` (81) | `canErrorFrom` (75-81), `isPermitted` (105) | source.md:11; OrderService.java:159-163 |
| R5 | `r5_terminal_no_outgoing` (90) | `isTerminal` (83-87), `isPermitted` (94-106) | source.md:12; OrderService.java:148-166 |
| R5 | `r5_same_state_rejected` (96) | `isPermitted` (95-96) | source.md:12; OrderService.java:149-151 |
| R5 | `r5_to_new_rejected` (100) | `isPermitted` (106) | source.md:12; OrderService.java:164 |
| R5 | `r5_permitted_iff_allowedPairs` (105) | `isPermitted` (94-106), `allowedPairs` (109-113) | source.md:12; OrderService.java:148-166 |
| R6 | `r6_commit_implies_permitted_and_bumped` (114) | `commit?` (145-151), `OrderState` (129-132), `Txn` (136-142) | source.md:13; OrderService.java:100-111; OrderEntity.java:85-87; docs:26-28 |
| R6 | `r6_stale_commit_rejected` (123) | `commit?` (145-151) | source.md:13; OrderEntity.java:79-87; docs:7-14, 26-28 |
| R6 | `r6_stale_commit_keeps_state` (134) | `commit?` (145-151), `commitOrKeep` (153-155) | source.md:13; docs:10-14, 26-28 |
| R6 | `r6_same_version_cannot_both_commit` (142) | `commit?` (145-151), version field (131) | source.md:13; docs:7-14 |
| R6 | `r6_terminal_commit_rejected` (175) | `commit?` (145-151), `isTerminal` (83-87) | source.md:12-13; OrderService.java:148-166; OrderEntity.java:79-87 |
| R6 | `r6_trace_commits_permitted` (187) | `CommitStep` (162-167), `TraceValid` (170-173) | source.md:13; OrderService.java:96-115 |
| R6 | `r6_trace_fresh_reads` (204) | `TraceValid` (170-173), `commit?` (145-151) | source.md:13; docs:10-14, 26-28 |
| R6 | `r6_trace_versions_increment` (222) | `TraceValid` (170-173), `commit?` (145-151) | source.md:13; docs:26-28 |
| R6 | `r6_trace_consecutive_fresh` (239) | `TraceValid` (170-173), `ConsecutiveFresh` (176-182) | source.md:13 |
| R6 | `r6_trace_no_commit_from_terminal` (262) | `TraceValid` (170-173), `isTerminal` (83-87) | source.md:12-13 |

Coverage argument in one sentence per rule: R1 is covered by creation results/initial
write plus the status-set enumeration; R2 by the rank-step iff for normal targets; R3 and
R4 by the cancellation/ERROR iff characterisations; R5 by terminal-state rejection,
same-state rejection, target-`NEW` rejection, and the full 11-pair table equivalence; R6
by the commit rule (fresh read + permitted transition + version bump), stale-version
rejection with unchanged committed state, impossibility of two same-version commits, and
the trace theorems (sequential and fresh committed histories) proved by induction.

## Statement snapshots (phase-2 contract)

Recorded 2026-10-23 from the completed `Specs/Rules.lean`. Note: the snapshots were
reconstructed after the proofs were finished (the artifact was produced before the skill
gate required snapshots); a reviewer should re-read them against `RULES.md`. Refactoring
must not change them; any change needs an owner-approved delta in the review log.

| Theorem | Statement (signature) |
|---|---|
| `r1_create_none` | `createStatus none = some NEW` |
| `r1_create_new` | `createStatus (some NEW) = some NEW` |
| `r1_create_other_rejected` | `s ≠ NEW → createStatus (some s) = none` |
| `r1_create_iff` | `createStatus requested = some s ↔ s = NEW ∧ (requested = none ∨ requested = some NEW)` |
| `r1_created_initial_write` | `createInitialState requested = some st → st.status = NEW ∧ st.version = 0` |
| `r1_all_statuses` | `s ∈ allStatuses` |
| `r2_permitted_normal_iff_rank_succ` | `isNormal nxt = true → (isPermitted prev nxt = true ↔ rankStep prev nxt)` |
| `r3_permitted_cancel_iff` | `isPermitted prev CANCELLED = true ↔ prev = NEW ∨ prev = PENDING` |
| `r4_permitted_error_iff` | `isPermitted prev ERROR = true ↔ prev = NEW ∨ prev = PENDING ∨ prev = CONFIRMED ∨ prev = IN_PROCESS` |
| `r5_terminal_no_outgoing` | `isTerminal s = true → isPermitted s nxt = false` |
| `r5_same_state_rejected` | `isPermitted s s = false` |
| `r5_to_new_rejected` | `isPermitted prev NEW = false` |
| `r5_permitted_iff_allowedPairs` | `isPermitted prev nxt = true ↔ (prev, nxt) ∈ allowedPairs` |
| `r6_commit_implies_permitted_and_bumped` | `s.commit? t = some s' → t.readVersion = s.version ∧ t.readStatus = s.status ∧ isPermitted t.readStatus t.writeStatus = true ∧ s'.version = s.version + 1 ∧ s'.status = t.writeStatus` |
| `r6_stale_commit_rejected` | `t.readVersion ≠ s.version → s.commit? t = none` |
| `r6_stale_commit_keeps_state` | `t.readVersion ≠ s.version → s.commitOrKeep t = s` |
| `r6_same_version_cannot_both_commit` | `t1.readVersion = t2.readVersion → (s.commit? t1).bind (·.commit? t2) = none ∧ (s.commit? t2).bind (·.commit? t1) = none` |
| `r6_terminal_commit_rejected` | `isTerminal s.status = true → s.commit? t = none` |
| `r6_trace_commits_permitted` | `TraceValid s cs → ∀ c ∈ cs, isPermitted c.txn.readStatus c.txn.writeStatus = true` |
| `r6_trace_fresh_reads` | `TraceValid s cs → ∀ c ∈ cs, c.txn.readVersion = c.before.version ∧ c.txn.readStatus = c.before.status` |
| `r6_trace_versions_increment` | `TraceValid s cs → ∀ c ∈ cs, c.after.version = c.before.version + 1` |
| `r6_trace_consecutive_fresh` | `TraceValid s cs → ConsecutiveFresh cs` |
| `r6_trace_no_commit_from_terminal` | `TraceValid s cs → ∀ c ∈ cs, isTerminal c.before.status = false` |

## Verification gate (honest status as of 2026-10-23)

- [x] `RULES.md` confirmed with provenance (`philipz`, 2026-10-23)
- [x] Verified sources mapped to `file:line`; abstraction ledger complete
- [ ] Statement snapshots recorded; ownership review of the statements is **pending** (the
      owner confirmed the rules and the acceptance criteria, not the Lean signatures —
      listed above for sign-off)
- [x] Non-vacuity witness for every headline theorem with hypotheses (`Specs/Examples.lean`)
- [ ] **Independent** adversarial review (fresh context / different model): not performed —
      the teammate could not delegate at depth 1, so only the in-session self-review in the
      review log exists; a human or a fresh reviewer should repeat it
- [ ] Owner read the top-level statements and signed off: **pending** (see above)
- [x] Mechanical checks green: clean build, direct compile, compile coverage, guardrail
      scan, axiom audit (23/23 lines, `propext`/`Quot.sound` only), audit completeness —
      `verify-lean.sh` `RESULT: PASS`
- [x] Dashboard baseline recorded (`metrics-baseline.txt`, generated by the installed skill
      script; re-runs show zero delta)
- [x] Bounded port audit (guards, order, outcomes, boundaries, dropped details) per rule

**Claim status: partial verification.** The model-level proofs are complete and
machine-checked, but the gate's human items (statement sign-off, independent adversarial
review) are outstanding. Do not present this as "verified" until they are closed.

## Abstraction ledger - dropped details and why they cannot affect the proven properties

| Dropped detail | Where (source file:lines) | Safety argument |
|---|---|---|
| JPA entity persistence, dirty checking, SQL `INSERT`/`UPDATE` mechanics | OrderService.java:46, 111, 134; OrderEntity.java:26-88 | The rules constrain only the committed `(status, version)` and whether a write is accepted. The model records exactly the accepted writes (INSERT -> `(NEW, 0)`, UPDATE -> `(newStatus, version+1)`); persistence mechanics do not add or remove decisions. |
| Hibernate `@Version` check (`UPDATE ... WHERE id = ? AND version = ?`) and `ObjectOptimisticLockingFailureException` type | OrderEntity.java:79-87; docs:26-28 | Modeled as the `commit?` guard `readVersion = current version` plus rejection without a committed state change. This is precisely the decision that prevents the lost update; the SQL text, flush timing and exception class do not change the accept/reject outcome. |
| Transaction begin/commit/rollback boundaries, flush timing | OrderService.java:31, 96, 117 (`@Transactional`), docs:26-28 | Modeled as atomic commit: a transaction either adds one committed write (with fresh read) or contributes nothing. Rollback equals "no result"; a rejected transaction is absent from the committed history. |
| Exception classes and messages (`InvalidOrderException`, `IllegalStateException`, `OrderNotFoundException`) | OrderService.java:3, 43, 103, 107-109, 126, 129-131 | Mapped to rejection (no committed write). The rules say when a transition is not permitted; how the failure is reported is not part of R1-R6. "Order not found" assumes the order exists (creation is the only entry point) and is outside the confirmed rules. |
| Caching annotations and Hazelcast write-through store | OrderService.java:32-34, 68, 75, 97-99, 118-122; docs:35-44 | Caches affect read paths/performance, not the committed status/version decisions. A cache read cannot create a permitted transition or change the version guard. |
| Spring events (`OrderCreatedEvent`, after-commit listener) | OrderService.java:49-55, 60-65 | Post-commit side effects; they cannot change the committed status or version that the rules constrain. |
| Logging | OrderService.java:47, 70, 113, 135 | No state effect. |
| Order-number generation (UUID) and lookup by order number | OrderService.java:36-38, 101-103, 124-126 | Identity/plumbing for finding the row; the model reasons about one order. Rules are per-order; identity does not affect the transition/version decisions. |
| Other entity fields: `id`, `orderNumber`, `customer`, `deliveryAddress`, `orderItem` | OrderEntity.java:44-77 | Never consulted by the status-transition/version decisions; changing them cannot make a forbidden transition permitted or defeat the version guard. |
| Nullable `version` (`Long`) for not-yet-persisted entities | OrderEntity.java:79-87 | A committed row always has a version (INSERT initializes 0). The model starts committed orders at version 0; `null` never occurs in a committed history. |
| Database isolation level, lock manager behavior, real interleaving/scheduling | docs:5-14; OrderEntity.java:79-87 | Abstracted to snapshot `(readStatus, readVersion)` + atomic commit. The proven property is safety of every committed history; scheduling only decides whether a commit succeeds or is rejected, and both outcomes satisfy the model. Liveness/throughput are explicitly not covered. |
| Retry policy / caller handling of lock failures | docs:46-50 | Caller behavior; not part of `OrderService`. A retry is a new transaction with a fresh read and must pass the same guard. |
| Multiple orders / cross-order independence | OrderService.java (whole) | The service reads/writes one order per call; R1-R6 are per-order. Proving one order's lifecycle covers every order, since no rule relates two orders. |
| Null or unknown status values (e.g. from deserialization) | OrderStatus.java:6-30; OrderEntity.java:74-77 | Java enum typing + non-null column constrain committed values to the eight statuses; R1's status set is exactly those eight. Malformed external input is out of scope. |

Note on one modeling choice: `commit?` checks both `readVersion = version` **and**
`readStatus = status`. In the real system the version check alone already implies the row
(hence status) is unchanged, so the read-status conjunct never rejects a write that
Hibernate would accept; it only makes the model reject abstract states that cannot arise
from real commits. This over-approximation cannot hide a real lost update; the safety
theorems therefore still cover every real committed history.

## Explicitly not covered

- Actual database isolation level, locking order, deadlock/starvation, transaction
  retry/backoff, and any concurrency *liveness* property.
- Hibernate dirty-checking details, entity identity/`persist` vs `merge` behavior, and
  actual SQL execution.
- Cache consistency/read-your-writes semantics of `@Cacheable`/`@CachePut` and the
  Hazelcast `OrderMapStore`.
- Spring Modulith event publication and delivery guarantees.
- Cross-order atomicity, batch operations, and anything about order data other than
  `status`/`version`.
- Caller-side retry logic and exception presentation (documented in
  `docs/orders-optimistic-locking.md:46-50` as the caller's responsibility).
- Null/unknown enum values arriving from outside the typed Java code (e.g. corrupted DB
  data or unchecked deserialization).
- Performance, memory, logging output, and all IO.
- An automatic Java<->Lean bridge: the model<->code correspondence is the manual audit
  recorded above (skill default; no oracle/differential harness was requested).

## Non-vacuity

`Specs/Examples.lean` gives at least one concrete instance of every theorem's hypotheses
(and of every negative case): permitted/rejected transition pairs, all creation branches,
a fresh commit, a stale-reader rejection that leaves `(SHIPPED, 5)` unchanged, two
same-version transactions that cannot both commit, a terminal-state commit rejection, and
the committed history `deliveredTraceValid` that reaches `DELIVERED` through all five
normal-flow steps (`Specs/Examples.lean:189-193`). The delivered history is also reached
by executing the transaction list (`runTxns`, `Specs/Examples.lean:222-229`).

## Dashboard snapshot (Rule 4)

The skill's `scripts/verify-lean.sh` is installed and was run from the repo root; the
first green run was saved as the baseline (`metrics-baseline.txt`):

```bash
bash ~/.agents/skills/lean-formal-verification/scripts/verify-lean.sh \
  --dir specs/lean --main Specs/Rules.lean --audit Audit.lean \
  --theorems headline-theorems.txt --save-baseline metrics-baseline.txt
```

Observed: `RESULT: PASS` — build, direct compile, coverage, guardrails and axiom audit
all PASS, `23/23 expected theorem(s) reported`. Re-runs with `--baseline` show zero delta.
Comments and string contents are stripped before counting, so the counts below differ
from a naive line count.

| Metric | Main proof file (`Specs/Rules.lean`) | Whole project (all `.lean`) |
|---|---|---|
| lean_files | - | 6 |
| total_lines | 275 | 871 |
| lean_code_lines | 185 | 528 |
| proof_api.public | 23 | - |
| proof_api.private | 0 | - |
| proof_branching.cases | 22 | - |
| proof_branching.by_cases | 0 | - |
| proof_branching.induction | 4 | - |
| proof_plumbing.have | 10 | - |
| proof_plumbing.show | 0 | - |
| proof_plumbing.suffices | 0 | - |
| proof_plumbing.rw | 15 | - |
| automation.simp | 20 | - |
| automation.simpa | 0 | - |
| automation.omega | 2 | - |
| automation.linarith | 0 | - |
| automation.grind | 0 | - |
| representation machinery (`List.span`/`takeWhile`/`dropWhile`/`getLast?`/`dropLast`) | 0 | 0 |

Notes: the whole-project lean-code count includes `Specs/Examples.lean` (166 lines), whose
`decide` calls are closed concrete non-vacuity instances, not proof search; `by decide` is
used only there, never in `Specs/Model.lean`, `Specs/Proofs.lean` or `Specs/Rules.lean`.
There is no before/after refactoring comparison yet (no prior baseline); the numbers above
are the baseline to compare against after future proof refactors.

## Review log

| Date | Reviewer | Kind | Findings | Resolution |
|---|---|---|---|---|
| 2026-10-23 | lead (phase 0) | human (owner via Lead, this session) | Owner confirmed the rules are R1-R6 exactly as approved in `specs/order-lifecycle/source.md`, no changes. | `RULES.md` written as the rules of record; no open questions remain. |
| 2026-10-23 | proof-engineer | port audit (model vs code) | Re-read `createOrder` (OrderService.java:31-58), `updateOrderStatus` (96-115), `cancelOrder` (117-136), `canBeCancelled` (138-140), `isPermittedTransition` (142-166) and the `@Version` design (OrderEntity.java:79-87). Every branch is preserved: default-missing-status to NEW, rejection of non-NEW creation, same-state rejection, target-NEW rejection, the five forward cases, cancel set {NEW, PENDING}, error set {NEW, PENDING, CONFIRMED, IN_PROCESS}, version compare and increment. No divergence found in scope. | Divergences: none. Abstracted details are all listed in the ledger above with safety arguments. |
| 2026-10-23 | proof-engineer | adversarial self-review (fresh-eyes checklist from `references/workflow-prompts.md`; the `subagent` tool is unavailable at delegation depth 1, so the checklist was run in-session) | (a) Behaviour mismatch model vs code: none found; see port audit row. (b) Unreachable hypotheses: every hypothesis-bearing theorem instantiated in `Examples.lean`; R2's `isNormal nxt = true` is necessary (without it the equivalence fails for `CANCELLED`/`ERROR` targets) and satisfiable (`PENDING` shown). (c) Too-weak statements: R3/R4 characterisations are close to unfolding the model's helper predicates by design; the non-definitional content is carried by the R5 full-table equivalence and the R6 commit/trace theorems. R2 is stated only for normal-flow targets, as the rule text requires; other targets are covered by R3/R4/R5. (d) Silently dropped decisions: none in the ledger's scope; the commit model adds a redundant read-status conjunct (explained above), which can only reject unrealisable abstract states. (e) Missing rule/case: full 8x8 transition table covered by `r5_permitted_iff_allowedPairs`; terminal, same-state and target-NEW cases all have dedicated theorems; creation paths all covered by `r1_create_iff`. Residual risk: the theorems are about the Lean model; the code<->model link is manual review (no automatic bridge), and liveness is out of scope. | No theorem weakened. No `sorry`/axiom/`native_decide`/`unsafe` used. Findings documented rather than "fixed" by weakening; residual risks listed in "Explicitly not covered". |

## Re-sync log

| Date | Commit | Sources changed | Rule affected | Theorems touched | Notes |
|---|---|---|---|---|---|
| 2026-10-23 | 4f7cf95 | none (initial verification) | - | all | Initial artifact. Re-run `lake build`, `lake env lean Audit.lean`, guardrail greps (see `README.md`). |

### Re-sync procedure (after a code change)

1. Diff the verified sources listed above (`git log --oneline -- <files>`; `git diff <commit>..HEAD -- <files>`).
2. Map each changed line to a modeled decision using the rule-coverage table; if the
   *rule* changed, stop and re-run phase 0 with the owner before touching any theorem.
3. Update `Specs/Model.lean` first, then theorem statements, then proofs. Never weaken a
   confirmed theorem to get green.
4. Re-run: clean `lake build`, `lake env lean Audit.lean`, the guardrail greps from
   `references/guardrails.md`, and (when available) the skill's `scripts/verify-lean.sh`.
5. Update the "Verified at commit" line and add a row to this re-sync log and to the
   review log when a mapping review was repeated.
