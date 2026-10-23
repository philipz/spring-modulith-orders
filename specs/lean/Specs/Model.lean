/-
Model layer: the order lifecycle state machine (R1-R5) and the versioned write model (R6).

The rules of record are `RULES.md` (owner-confirmed, derived from
`specs/order-lifecycle/source.md`, not from the implementation). This module keeps every
decision that can change a verified property: the eight statuses, the permitted
transition relation (same-state and target-NEW rejection included), the creation status
rule, and the optimistic-lock commit rule. It drops persistence, JPA, caches, events,
logging and retries; `MODEL-MAP.md` records why each dropped detail cannot affect the
proven properties.
-/

namespace Specs

/-! ## R1: the order status set -/

/-- The eight order statuses of R1. -/
inductive OrderStatus where
  | NEW
  | PENDING
  | CONFIRMED
  | IN_PROCESS
  | SHIPPED
  | DELIVERED
  | CANCELLED
  | ERROR
  deriving DecidableEq, Repr

open OrderStatus

/-- R1: the complete status set (all eight statuses). -/
def allStatuses : List OrderStatus :=
  [NEW, PENDING, CONFIRMED, IN_PROCESS, SHIPPED, DELIVERED, CANCELLED, ERROR]

/-! ## R2-R5: permitted transitions -/

/-- R2: `true` for the six statuses on the forward normal-flow chain. -/
def isNormal : OrderStatus → Bool
  | NEW => true
  | PENDING => true
  | CONFIRMED => true
  | IN_PROCESS => true
  | SHIPPED => true
  | DELIVERED => true
  | CANCELLED => false
  | ERROR => false

/-- R2: position on the normal-flow chain; `none` for statuses off the chain. -/
def normalRank : OrderStatus → Option Nat
  | NEW => some 0
  | PENDING => some 1
  | CONFIRMED => some 2
  | IN_PROCESS => some 3
  | SHIPPED => some 4
  | DELIVERED => some 5
  | CANCELLED => none
  | ERROR => none

/-- Successor of an optional rank (`none` stays `none`). -/
def rankSucc? : Option Nat → Option Nat
  | none => none
  | some n => some (n + 1)

/-- R2: `nxt` is exactly one forward step after `prev` on the normal-flow chain. -/
def rankStep (prev nxt : OrderStatus) : Prop :=
  normalRank nxt = rankSucc? (normalRank prev)

/-- R3: statuses from which cancellation is permitted. -/
def canCancelFrom : OrderStatus → Bool
  | NEW => true
  | PENDING => true
  | _ => false

/-- R4: statuses from which a move to ERROR is permitted. -/
def canErrorFrom : OrderStatus → Bool
  | NEW => true
  | PENDING => true
  | CONFIRMED => true
  | IN_PROCESS => true
  | _ => false

/-- R5: terminal statuses; once entered, no further transition is permitted. -/
def isTerminal : OrderStatus → Bool
  | DELIVERED => true
  | CANCELLED => true
  | ERROR => true
  | _ => false

/-- R2-R5: the permitted state transitions. The decisions are exactly:
* R2: the forward chain advances by one step only (no jumps, no backwards);
* R3: only NEW/PENDING orders may be cancelled;
* R4: only NEW/PENDING/CONFIRMED/IN_PROCESS orders may move to ERROR;
* R5: everything else is forbidden, including same-state writes and writes to NEW. -/
def isPermitted (prev nxt : OrderStatus) : Bool :=
  if prev = nxt then
    false
  else
    match nxt with
    | PENDING => prev = NEW
    | CONFIRMED => prev = PENDING
    | IN_PROCESS => prev = CONFIRMED
    | SHIPPED => prev = IN_PROCESS
    | DELIVERED => prev = SHIPPED
    | CANCELLED => canCancelFrom prev
    | ERROR => canErrorFrom prev
    | NEW => false

/-- R5: the complete table of permitted `(prev, nxt)` pairs. -/
def allowedPairs : List (OrderStatus × OrderStatus) :=
  [ (NEW, PENDING), (PENDING, CONFIRMED), (CONFIRMED, IN_PROCESS),
    (IN_PROCESS, SHIPPED), (SHIPPED, DELIVERED),
    (NEW, CANCELLED), (PENDING, CANCELLED),
    (NEW, ERROR), (PENDING, ERROR), (CONFIRMED, ERROR), (IN_PROCESS, ERROR) ]

/-! ## R1: order creation -/

/-- R1: result of creating an order with a requested initial status. `none` means the
caller supplied no status (the order starts NEW); `some NEW` is accepted; any other
requested status is rejected. -/
def createStatus (requested : Option OrderStatus) : Option OrderStatus :=
  match requested with
  | none => some NEW
  | some NEW => some NEW
  | some _ => none

/-! ## R6: versioned writes (optimistic locking) -/

/-- The committed observable state of one order: status and optimistic-lock version. -/
structure OrderState where
  status : OrderStatus
  version : Nat
  deriving DecidableEq, Repr

/-- One prepared status-change transaction: it read `(readStatus, readVersion)` from a
snapshot and intends to write `writeStatus`. -/
structure Txn where
  readStatus : OrderStatus
  readVersion : Nat
  writeStatus : OrderStatus
  deriving DecidableEq, Repr

/-- R6: a commit succeeds iff the snapshot is still fresh (same version and same status)
and the intended transition is permitted by R2-R5. A successful commit writes the new
status and increments the version. -/
def OrderState.commit? (s : OrderState) (t : Txn) : Option OrderState :=
  if t.readVersion = s.version ∧ t.readStatus = s.status ∧
      isPermitted t.readStatus t.writeStatus = true then
    some { status := t.writeStatus, version := s.version + 1 }
  else
    none

/-- R6: a rejected commit leaves the state exactly as it was (no lost update). -/
def OrderState.commitOrKeep (s : OrderState) (t : Txn) : OrderState :=
  (s.commit? t).getD s

/-- R1: the initial committed state after a successful creation: NEW, version 0 (the
INSERT). A rejected creation has no initial state. -/
def createInitialState (requested : Option OrderStatus) : Option OrderState :=
  (createStatus requested).map (fun s => { status := s, version := 0 })

/-- One committed write in a committed history. -/
structure CommitStep where
  before : OrderState
  txn : Txn
  after : OrderState
  deriving DecidableEq, Repr

/-- R6: a valid committed history: it starts from the given committed state, every step is
a successful commit, and each step's after-state is the next step's before-state. -/
def TraceValid : OrderState → List CommitStep → Prop
  | _, [] => True
  | s, c :: cs => c.before = s ∧ c.before.commit? c.txn = some c.after ∧ TraceValid c.after cs

/-- R6: consecutive committed writes - the second one read the status and version that
were written immediately before it. -/
def ConsecutiveFresh : List CommitStep → Prop
  | [] => True
  | [_] => True
  | c1 :: c2 :: rest =>
      c2.txn.readStatus = c1.after.status ∧
      c2.txn.readVersion = c1.after.version ∧
      ConsecutiveFresh (c2 :: rest)

/-- Run a list of transactions from a committed state; every transaction must commit
successfully. Used by the non-vacuity examples. -/
def runTxns : OrderState → List Txn → Option OrderState
  | s, [] => some s
  | s, t :: ts => (s.commit? t).bind (fun s' => runTxns s' ts)

end Specs
