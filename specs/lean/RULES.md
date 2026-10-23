# Business rules to verify (owner-confirmed)

> Phase 0 output. The rules below are the owner-confirmed R1-R6 of
> `specs/order-lifecycle/source.md` (the approved Chinese rule text, translated here into
> English); this file adds no rule and changes none. The Lean model and theorem statements
> are derived from these rules, not from the implementation. Phase 0 was run by the Lead;
> the owner confirmed on 2026-10-23 that the rules are R1-R6 exactly as approved, no
> changes.

- **Module / entry point:** `src/main/java/com/sivalabs/bookstore/orders/domain/OrderService.java` (read-only)
- **Rule source of truth:** `specs/order-lifecycle/source.md` lines 8-13 (CI-written snapshot; the file must not be modified)
- **Owner:** philipz
- **Owner decisions:** rules are R1-R6 exactly as approved in `specs/order-lifecycle/source.md`; no rule changes since approval
- **confirmed-by:** philipz (owner)
- **Date:** 2026-10-23
- **Channel:** this session
- **Status:** confirmed
- **Acceptance:** the six rules covered by headline theorems with complete proofs, zero
  `sorry`/axioms, a guardrail+axiom audit, a terminal dashboard, and this model map.
- **Sign-off (rules):** philipz (owner), 2026-10-23 — rules R1-R6 confirmed unchanged.
- **Sign-off (statement review):** **pending** — the 23 headline theorem signatures are
  listed in `MODEL-MAP.md` -> "Statement snapshots"; the owner has not yet read them.

## Scope

**In scope:** the order status lifecycle R1-R6: the status set and creation initial status
(R1), the forward single-step normal flow (R2), cancellation (R3), the ERROR transition
(R4), terminal states plus the complete permitted-transition table (R5), and the
optimistic-lock write rule for concurrent status changes (R6).

**Out of scope (explicit):** database isolation levels; Hibernate flush/dirty-checking
details; transaction retry policy and caller handling of
`ObjectOptimisticLockingFailureException`; caching (`@Cacheable`/`@CachePut`, Hazelcast
`OrderMapStore`); Spring events; logging; order-number generation; non-status order
fields; multiple simultaneous orders; concurrency liveness (deadlock/starvation/blocking);
performance; crash recovery; nullable/unknown enumeration values from the database.

## Rules

### R1 - status set and creation initial status

- **Statement:** An order's status is always one of exactly eight values: `NEW`,
  `PENDING`, `CONFIRMED`, `IN_PROCESS`, `SHIPPED`, `DELIVERED`, `CANCELLED`, `ERROR`. A
  newly created order has status `NEW`.
- **Source of truth:** `specs/order-lifecycle/source.md:8` (§R1).
- **Positive example:** create an order without an explicit status -> committed status is
  `NEW`; create an order that explicitly requests `NEW` -> committed status is `NEW`.
- **Negative example (violation):** an order is created directly in `PENDING` (or any
  status other than `NEW`); a created order's first committed write is not `NEW`; a
  status value outside the eight-value set appears.
- **Boundaries (confirmed in phase 0):** a creation request that carries no status
  (`null`) starts the order as `NEW`; a request that already says `NEW` is accepted;
  a request for any other status is **rejected** rather than silently coerced, because
  otherwise the "new order starts as NEW" rule could not hold. An order number has no
  effect on the rule.

### R2 - forward normal flow advances one step at a time

- **Statement:** The normal flow is `NEW -> PENDING -> CONFIRMED -> IN_PROCESS -> SHIPPED
  -> DELIVERED`, one-directional. A transition between two normal-flow statuses is
  permitted exactly when the target's position is the source's position plus one: no
  jumps, no backwards moves.
- **Source of truth:** `specs/order-lifecycle/source.md:9` (§R2).
- **Positive example:** `NEW -> PENDING`, `CONFIRMED -> IN_PROCESS`,
  `SHIPPED -> DELIVERED`.
- **Negative example (violation):** `NEW -> CONFIRMED` (jump), `PENDING -> NEW`
  (backwards), `SHIPPED -> CONFIRMED`.
- **Boundaries:** `DELIVERED` is the last normal-flow status and has no outgoing
  transition (R5); `CANCELLED`/`ERROR` are off the normal flow; staying in the same state
  is not a transition and is rejected (R5).

### R3 - cancellation only from NEW or PENDING

- **Statement:** An order may transition to `CANCELLED` exactly when its current status is
  `NEW` or `PENDING`.
- **Source of truth:** `specs/order-lifecycle/source.md:10` (§R3).
- **Positive example:** `NEW -> CANCELLED`, `PENDING -> CANCELLED`.
- **Negative example (violation):** `CONFIRMED -> CANCELLED`, `SHIPPED -> CANCELLED` (the
  shipped-order-cancelled scenario named in the rule text), `CANCELLED -> CANCELLED`.
- **Boundaries:** `CANCELLED` is terminal after the transition (R5); the cancellation
  guard must not accept any other source status, whether it is reached through the
  generic status-update path or the dedicated cancel path.

### R4 - ERROR only from NEW, PENDING, CONFIRMED or IN_PROCESS

- **Statement:** An order may transition to `ERROR` exactly when its current status is
  `NEW`, `PENDING`, `CONFIRMED` or `IN_PROCESS`.
- **Source of truth:** `specs/order-lifecycle/source.md:11` (§R4).
- **Positive example:** `NEW -> ERROR`, `CONFIRMED -> ERROR`.
- **Negative example (violation):** `SHIPPED -> ERROR`, `DELIVERED -> ERROR`,
  `ERROR -> ERROR`.
- **Boundaries:** `ERROR` is terminal after the transition (R5).

### R5 - terminal states and the complete permitted-transition table

- **Statement:** `DELIVERED`, `CANCELLED` and `ERROR` are terminal: once entered, no
  transition (including a same-state write) is permitted. Transitions other than R2-R4
  are never permitted. Consequently the permitted transition relation is exactly this
  table: `NEW->PENDING`, `PENDING->CONFIRMED`, `CONFIRMED->IN_PROCESS`,
  `IN_PROCESS->SHIPPED`, `SHIPPED->DELIVERED`, `NEW->CANCELLED`, `PENDING->CANCELLED`,
  `NEW->ERROR`, `PENDING->ERROR`, `CONFIRMED->ERROR`, `IN_PROCESS->ERROR`.
- **Source of truth:** `specs/order-lifecycle/source.md:12` (§R5).
- **Positive example:** every pair of the table above is permitted; a pending order stays
  cancellable.
- **Negative example (violation):** `DELIVERED -> PENDING`, `CANCELLED -> NEW`,
  `ERROR -> IN_PROCESS`, `NEW -> DELIVERED`, `NEW -> NEW` (same-state write),
  `SHIPPED -> SHIPPED` (same-state write), `PENDING -> NEW` (write to `NEW`).
- **Boundaries:** `NEW` is only produced by creation (R1), never by a transition. A write
  whose source and target status are equal is rejected, even though it would not change
  the committed value.

### R6 - concurrency: committed writes are sequential and fresh (optimistic locking)

- **Statement:** When several status changes target the same order, the committed result
  must be equivalent to executing those changes one at a time in some order. A status
  change must not overwrite the committed status based on a stale read (for example, a
  `SHIPPED` order must not be overwritten to `CANCELLED` through a snapshot taken while it
  was still `PENDING`). Operationally each status-change transaction reads
  `(status, version)` and its commit succeeds only if the read version is still the
  current version and the intended transition is permitted; a successful commit writes the
  new status and increments the version by one. A commit on a stale version is rejected
  and leaves the committed state unchanged.
- **Source of truth:** `specs/order-lifecycle/source.md:13` (§R6), together with the
  optimistic-locking design in `OrderEntity.java:79-87` and
  `docs/orders-optimistic-locking.md:5-28`.
- **Positive example:** a transaction that read `(NEW, version 0)` commits
  `NEW -> PENDING` and the order becomes `(PENDING, version 1)`; a transaction that read
  `(PENDING, version 1)` then commits `PENDING -> CONFIRMED`.
- **Negative example (violation):** an order is committed at `(SHIPPED, version 5)`, a
  transaction holds the stale snapshot `(PENDING, version 2)` and writes `CANCELLED`; the
  stale commit must be rejected and the committed status must remain `SHIPPED`. Likewise,
  two transactions that both read the same version must not both commit.
- **Boundaries:** the rules constrain the committed history, not real-time scheduling;
  callers may retry a rejected transaction after re-reading (retry policy and exception
  handling are out of scope); different orders are independent; the version starts at 0 on
  the creation INSERT and increases by one per committed update.

## Open questions (answered from the approved rule text before proving)

> Provenance: Q1-Q5 were answered by the Lead from `specs/order-lifecycle/source.md` and
> the approved optimistic-locking design; the owner confirmed on 2026-10-23 that the
> rules themselves are R1-R6 unchanged. These are interpretations consistent with that
> text, not a separate owner interview - challenge them before relying on the artifact.

| # | Question | Answer (source) | Date |
|---|---|---|---|
| Q1 | Are same-state writes (`status -> same status`) permitted? | No; rejected. The approved rule text says all transitions outside R2-R4 are not permitted, and R2-R4 never include a same-state step. | 2026-10-23 |
| Q2 | What is the observable effect of a rejected write? | None: it commits no state change. A rejected transaction is not part of the committed history (a rolled-back transaction has no committed effect). | 2026-10-23 |
| Q3 | What happens when creation is asked for a non-NEW initial status? | Rejected; a created order must start `NEW` (the rule text requires new orders to be `NEW`). | 2026-10-23 |
| Q4 | Are retries, caches, events, logging or the database isolation level in scope? | No (out of scope, listed above). | 2026-10-23 |
| Q5 | May a theorem statement be weakened if a proof fails? | No. Stop, report the rule/statement and a counterexample, and get owner re-confirmation. | 2026-10-23 |

## Change policy

When the code changes and a theorem breaks: **never weaken a confirmed theorem to get
green.** Stop, report which rule/statement changed and why, give a concrete counterexample
if the statement is false, and get owner re-confirmation before editing any theorem.
Re-sync steps are in `README.md` and the re-sync log in `MODEL-MAP.md`.
