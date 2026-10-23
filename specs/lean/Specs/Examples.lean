/-
Non-vacuity examples.

These are tests for the artifact, not the verification claim: every rule is proved for
all inputs in `Specs/Rules.lean`. Here each rule and each headline theorem gets at least
one concrete instantiation, so no theorem merely holds because its hypotheses can never
occur. The last examples show a concrete committed history that really reaches
DELIVERED, and the stale-reader scenario from `docs/orders-optimistic-locking.md`.
-/

import Specs.Rules

namespace Specs

open OrderStatus

/-! ## R1 - creation -/

example : createStatus none = some NEW := by decide

example : createStatus (some NEW) = some NEW := by decide

example : createStatus (some CONFIRMED) = none := by decide

example : createStatus (some DELIVERED) = none := by decide

/-- The hypothesis of `r1_created_initial_write` is satisfiable. -/
example : createInitialState none = some { status := NEW, version := 0 } := by decide

example : createInitialState (some NEW) = some { status := NEW, version := 0 } := by decide

example : createInitialState (some CANCELLED) = none := by decide

/-- R1 status set: exactly eight statuses. -/
example : allStatuses.length = 8 := by decide

example : CANCELLED ∈ allStatuses := by decide

example : ({ status := NEW, version := 0 } : OrderState).status = NEW ∧
    ({ status := NEW, version := 0 } : OrderState).version = 0 :=
  r1_created_initial_write none _ (by decide)

/-! ## R2 - adjacent steps accepted, jumps and backwards moves rejected -/

example : isPermitted NEW PENDING = true := by decide
example : isPermitted PENDING CONFIRMED = true := by decide
example : isPermitted CONFIRMED IN_PROCESS = true := by decide
example : isPermitted IN_PROCESS SHIPPED = true := by decide
example : isPermitted SHIPPED DELIVERED = true := by decide

example : isPermitted NEW CONFIRMED = false := by decide
example : isPermitted PENDING IN_PROCESS = false := by decide
example : isPermitted PENDING NEW = false := by decide
example : isPermitted DELIVERED SHIPPED = false := by decide

/-- The hypothesis of `r2_permitted_normal_iff_rank_succ` (a normal-flow target) is
satisfiable, and the statement gives both directions on a concrete pair. -/
example : isNormal PENDING = true := by decide

example : isPermitted NEW PENDING = true ∧ rankStep NEW PENDING := by
  have h := r2_permitted_normal_iff_rank_succ NEW PENDING (by decide)
  exact ⟨by decide, h.mp (by decide)⟩

example : ¬ rankStep PENDING NEW := by simp [rankStep, normalRank, rankSucc?]

/-! ## R3 - cancellation only from NEW/PENDING -/

example : isPermitted NEW CANCELLED = true := by decide
example : isPermitted PENDING CANCELLED = true := by decide
example : isPermitted CONFIRMED CANCELLED = false := by decide
example : isPermitted SHIPPED CANCELLED = false := by decide
example : isPermitted DELIVERED CANCELLED = false := by decide

/-! ## R4 - ERROR only from NEW/PENDING/CONFIRMED/IN_PROCESS -/

example : isPermitted NEW ERROR = true := by decide
example : isPermitted IN_PROCESS ERROR = true := by decide
example : isPermitted SHIPPED ERROR = false := by decide
example : isPermitted DELIVERED ERROR = false := by decide
example : isPermitted CANCELLED ERROR = false := by decide

/-! ## R5 - terminal states, same-state writes, target NEW, transition table -/

example : isPermitted DELIVERED PENDING = false := by decide
example : isPermitted CANCELLED NEW = false := by decide
example : isPermitted ERROR IN_PROCESS = false := by decide
example : isPermitted NEW NEW = false := by decide
example : isPermitted SHIPPED SHIPPED = false := by decide
example : isPermitted PENDING NEW = false := by decide

example : (NEW, PENDING) ∈ allowedPairs := by decide
example : (PENDING, CANCELLED) ∈ allowedPairs := by decide
example : (NEW, CONFIRMED) ∉ allowedPairs := by decide
example : (CONFIRMED, NEW) ∉ allowedPairs := by decide
example : (SHIPPED, CANCELLED) ∉ allowedPairs := by decide

/-- The hypothesis of `r5_terminal_no_outgoing` is satisfiable. -/
example : isTerminal DELIVERED = true := by decide

example : isPermitted DELIVERED NEW = false :=
  r5_terminal_no_outgoing DELIVERED NEW (by decide)

/-! ## R6 - versioned writes -/

/-- The committed state of a freshly created order: NEW at version 0. -/
def freshOrder : OrderState := { status := NEW, version := 0 }

/-- The committed state after NEW -> PENDING. -/
def pendingOrder : OrderState := { status := PENDING, version := 1 }

/-- A status-change transaction from a fresh snapshot. -/
def pendingTxn : Txn := { readStatus := NEW, readVersion := 0, writeStatus := PENDING }

/-- The hypothesis of `r6_commit_implies_permitted_and_bumped` is satisfiable. -/
example : freshOrder.commit? pendingTxn = some pendingOrder := by decide

example : pendingOrder.version = freshOrder.version + 1 ∧
    pendingOrder.status = pendingTxn.writeStatus :=
  (r6_commit_implies_permitted_and_bumped freshOrder pendingTxn pendingOrder
    (by decide)).2.2.2

/-- The stale-reader scenario from `docs/orders-optimistic-locking.md`: an order has
already moved on to SHIPPED/version 5, while a reader holds PENDING/version 2 and wants
to write CANCELLED. -/
def shippedOrder : OrderState := { status := SHIPPED, version := 5 }

def staleCancelTxn : Txn := { readStatus := PENDING, readVersion := 2, writeStatus := CANCELLED }

/-- The hypothesis of `r6_stale_commit_rejected` is satisfiable. -/
example : staleCancelTxn.readVersion ≠ shippedOrder.version := by decide

example : shippedOrder.commit? staleCancelTxn = none :=
  r6_stale_commit_rejected shippedOrder staleCancelTxn (by decide)

/-- No lost update: the rejected stale write leaves SHIPPED/version 5 untouched. -/
example : shippedOrder.commitOrKeep staleCancelTxn = shippedOrder :=
  r6_stale_commit_keeps_state shippedOrder staleCancelTxn (by decide)

/-- Two transactions that read the same version cannot both commit: both read
NEW/version 0, one wants PENDING and one wants CANCELLED. -/
def pendingTxnA : Txn := { readStatus := NEW, readVersion := 0, writeStatus := PENDING }
def cancelTxnB : Txn := { readStatus := NEW, readVersion := 0, writeStatus := CANCELLED }

example : pendingTxnA.readVersion = cancelTxnB.readVersion := by decide

example : (freshOrder.commit? pendingTxnA).bind (fun s => s.commit? cancelTxnB) = none :=
  (r6_same_version_cannot_both_commit freshOrder pendingTxnA cancelTxnB (by decide)).1

/-- The hypothesis of `r6_terminal_commit_rejected` is satisfiable: a delivered order
cannot accept any further commit (here the pending transaction from earlier). -/
def deliveredOrder : OrderState := { status := DELIVERED, version := 5 }

example : deliveredOrder.commit? pendingTxn = none :=
  r6_terminal_commit_rejected deliveredOrder pendingTxn (by decide)

/-! ## R6 - a concrete committed history reaching DELIVERED -/

def confirmedOrder : OrderState := { status := CONFIRMED, version := 2 }
def inProcessOrder : OrderState := { status := IN_PROCESS, version := 3 }
def shippedAtVersionFour : OrderState := { status := SHIPPED, version := 4 }

def toPending : CommitStep :=
  { before := freshOrder, txn := pendingTxn, after := pendingOrder }

def toConfirmed : CommitStep :=
  { before := pendingOrder,
    txn := { readStatus := PENDING, readVersion := 1, writeStatus := CONFIRMED },
    after := confirmedOrder }

def toInProcess : CommitStep :=
  { before := confirmedOrder,
    txn := { readStatus := CONFIRMED, readVersion := 2, writeStatus := IN_PROCESS },
    after := inProcessOrder }

def toShipped : CommitStep :=
  { before := inProcessOrder,
    txn := { readStatus := IN_PROCESS, readVersion := 3, writeStatus := SHIPPED },
    after := shippedAtVersionFour }

def toDelivered : CommitStep :=
  { before := shippedAtVersionFour,
    txn := { readStatus := SHIPPED, readVersion := 4, writeStatus := DELIVERED },
    after := deliveredOrder }

def deliveredTrace : List CommitStep :=
  [toPending, toConfirmed, toInProcess, toShipped, toDelivered]

/-- Reachability: the full normal flow can be executed and committed step by step. -/
theorem deliveredTraceValid : TraceValid freshOrder deliveredTrace := by
  simp [TraceValid, deliveredTrace, toPending, toConfirmed, toInProcess, toShipped,
    toDelivered, pendingTxn, freshOrder, pendingOrder, confirmedOrder, inProcessOrder,
    shippedAtVersionFour, deliveredOrder, OrderState.commit?, isPermitted]

/-- Non-vacuity for the committed-trace theorems: the trace hypothesis holds. -/
example : TraceValid freshOrder deliveredTrace := deliveredTraceValid

example : toDelivered ∈ deliveredTrace := by decide

example : isPermitted toDelivered.txn.readStatus toDelivered.txn.writeStatus = true :=
  r6_trace_commits_permitted freshOrder deliveredTrace deliveredTraceValid toDelivered
    (by decide)

example : toDelivered.txn.readVersion = toDelivered.before.version ∧
    toDelivered.txn.readStatus = toDelivered.before.status :=
  r6_trace_fresh_reads freshOrder deliveredTrace deliveredTraceValid toDelivered (by decide)

example : toDelivered.after.version = toDelivered.before.version + 1 :=
  r6_trace_versions_increment freshOrder deliveredTrace deliveredTraceValid toDelivered
    (by decide)

example : ConsecutiveFresh deliveredTrace :=
  r6_trace_consecutive_fresh freshOrder deliveredTrace deliveredTraceValid

/-- In this history every committed write starts from a non-terminal status (the last
step is SHIPPED, not yet terminal; the theorem covers all five steps). -/
example : isTerminal toDelivered.before.status = false :=
  r6_trace_no_commit_from_terminal freshOrder deliveredTrace deliveredTraceValid toDelivered
    (by decide)

/-! ## Reachability by running the transaction list -/

def deliveredTxns : List Txn :=
  [pendingTxn,
    { readStatus := PENDING, readVersion := 1, writeStatus := CONFIRMED },
    { readStatus := CONFIRMED, readVersion := 2, writeStatus := IN_PROCESS },
    { readStatus := IN_PROCESS, readVersion := 3, writeStatus := SHIPPED },
    { readStatus := SHIPPED, readVersion := 4, writeStatus := DELIVERED }]

example : runTxns freshOrder deliveredTxns = some deliveredOrder := by decide

example : runTxns freshOrder [pendingTxn, cancelTxnB] = none := by decide

end Specs
