/-
Rule theorems: the owner-confirmed business rules R1-R6 as Lean theorems.

Each statement is written from `RULES.md` (the confirmed rule text), not from the
implementation; `MODEL-MAP.md` maps every theorem to its rule and to the model
definitions that encode the decisions. Each proof is complete: the final project
contains no placeholder proofs, no axioms of its own and no compiler-trust escape
hatches.

The file is organised one section per rule, in rule order (Rule 9: prove related
results in sequence, sharing the lemmas in `Specs/Proofs.lean`).
-/

import Specs.Proofs

namespace Specs

open OrderStatus

/-! ## R1 - creation -/

/-- R1 (positive): creating an order with no requested status starts it as NEW. -/
theorem r1_create_none : createStatus none = some NEW := rfl

/-- R1 (positive): a request that already says NEW is accepted as NEW. -/
theorem r1_create_new : createStatus (some NEW) = some NEW := rfl

/-- R1 (negative): any other requested initial status is rejected. -/
theorem r1_create_other_rejected (s : OrderStatus) (h : s ≠ NEW) :
    createStatus (some s) = none := by
  cases s <;> simp_all [createStatus]

/-- R1 (characterisation): creation succeeds with NEW exactly when the request is absent
or explicitly NEW. -/
theorem r1_create_iff (requested : Option OrderStatus) (s : OrderStatus) :
    createStatus requested = some s ↔
      s = NEW ∧ (requested = none ∨ requested = some NEW) := by
  cases requested with
  | none => simp [createStatus, eq_comm]
  | some r => cases r <;> simp [createStatus, eq_comm]

/-- R1 (initial write): a created order's first committed write is NEW at version 0. -/
theorem r1_created_initial_write (requested : Option OrderStatus) (st : OrderState)
    (h : createInitialState requested = some st) : st.status = NEW ∧ st.version = 0 := by
  unfold createInitialState at h
  cases hc : createStatus requested with
  | none =>
      rw [hc] at h
      simp at h
  | some s =>
      rw [hc] at h
      simp only [Option.map_some, Option.some.injEq] at h
      rw [← h]
      exact ⟨createStatus_created_new requested s hc, rfl⟩

/-- R1 (status set): every status is one of the eight listed values. -/
theorem r1_all_statuses (s : OrderStatus) : s ∈ allStatuses := by
  cases s <;> simp [allStatuses]

/-! ## R2 - the normal flow advances one step at a time -/

/-- R2: for a normal-flow target, a transition is permitted exactly when the target's
rank is the source's rank plus one. This rules out jumps and backwards moves. -/
theorem r2_permitted_normal_iff_rank_succ (prev nxt : OrderStatus)
    (hnxt : isNormal nxt = true) :
    isPermitted prev nxt = true ↔ rankStep prev nxt := by
  cases prev <;> cases nxt <;>
    simp [isPermitted, isNormal, rankStep, normalRank, rankSucc?] at hnxt ⊢

/-! ## R3 - cancellation -/

/-- R3: cancellation is permitted exactly from NEW or PENDING. -/
theorem r3_permitted_cancel_iff (prev : OrderStatus) :
    isPermitted prev CANCELLED = true ↔ prev = NEW ∨ prev = PENDING := by
  cases prev <;> simp [isPermitted, canCancelFrom]

/-! ## R4 - error -/

/-- R4: a move to ERROR is permitted exactly from NEW, PENDING, CONFIRMED or
IN_PROCESS. -/
theorem r4_permitted_error_iff (prev : OrderStatus) :
    isPermitted prev ERROR = true ↔
      prev = NEW ∨ prev = PENDING ∨ prev = CONFIRMED ∨ prev = IN_PROCESS := by
  cases prev <;> simp [isPermitted, canErrorFrom]

/-! ## R5 - terminal states, same-state writes and the full transition table -/

/-- R5: a terminal status (DELIVERED, CANCELLED, ERROR) has no outgoing permitted
transition. -/
theorem r5_terminal_no_outgoing (s nxt : OrderStatus) (h : isTerminal s = true) :
    isPermitted s nxt = false := by
  cases s <;> cases nxt <;>
    simp [isPermitted, isTerminal, canCancelFrom, canErrorFrom] at h ⊢

/-- R5: writing the status an order already has is never permitted. -/
theorem r5_same_state_rejected (s : OrderStatus) : isPermitted s s = false := by
  cases s <;> simp [isPermitted]

/-- R5: no transition may target NEW (an order only starts as NEW at creation). -/
theorem r5_to_new_rejected (prev : OrderStatus) : isPermitted prev NEW = false := by
  cases prev <;> simp [isPermitted]

/-- R5 (full characterisation): the permitted transitions are exactly the eleven pairs
of the state-machine table; every other pair is rejected. -/
theorem r5_permitted_iff_allowedPairs (prev nxt : OrderStatus) :
    isPermitted prev nxt = true ↔ (prev, nxt) ∈ allowedPairs := by
  cases prev <;> cases nxt <;>
    simp [isPermitted, canCancelFrom, canErrorFrom, allowedPairs]

/-! ## R6 - versioned writes: commit rule and no lost update -/

/-- R6 (commit): a successful commit read the current version and status, applied a
permitted transition, wrote the target status and incremented the version. -/
theorem r6_commit_implies_permitted_and_bumped (s : OrderState) (t : Txn) (s' : OrderState)
    (h : s.commit? t = some s') :
    t.readVersion = s.version ∧ t.readStatus = s.status ∧
      isPermitted t.readStatus t.writeStatus = true ∧
        s'.version = s.version + 1 ∧ s'.status = t.writeStatus :=
  ⟨commit?_readVersion h, commit?_readStatus h, commit?_permitted h,
    commit?_version h, commit?_status h⟩

/-- R6 (stale read): a commit whose read version is no longer current is rejected. -/
theorem r6_stale_commit_rejected (s : OrderState) (t : Txn)
    (h : t.readVersion ≠ s.version) : s.commit? t = none := by
  unfold OrderState.commit?
  split
  · rename_i hc
    exact absurd hc.1 h
  · rfl

/-- R6 (no lost update): a rejected stale commit leaves the committed state exactly as
it was, so it cannot overwrite a newer status (e.g. a shipped order cannot be cancelled
through an old snapshot). -/
theorem r6_stale_commit_keeps_state (s : OrderState) (t : Txn)
    (h : t.readVersion ≠ s.version) : s.commitOrKeep t = s := by
  unfold OrderState.commitOrKeep
  rw [r6_stale_commit_rejected s t h]
  rfl

/-- R6 (serialisation): two transactions that read the same version cannot both commit,
in either order. -/
theorem r6_same_version_cannot_both_commit (s : OrderState) (t1 t2 : Txn)
    (h : t1.readVersion = t2.readVersion) :
    (s.commit? t1).bind (fun s1 => s1.commit? t2) = none ∧
      (s.commit? t2).bind (fun s1 => s1.commit? t1) = none := by
  constructor
  · cases h1 : s.commit? t1 with
    | none => simp only [Option.bind_none]
    | some s1 =>
        have hv1 := commit?_readVersion h1
        have hv2 := commit?_version h1
        have h2v : t2.readVersion = s.version := by
          rw [← h]
          exact hv1
        have hstale : t2.readVersion ≠ s1.version := by
          rw [h2v, hv2]
          omega
        simp only [Option.bind_some]
        exact r6_stale_commit_rejected s1 t2 hstale
  · cases h2 : s.commit? t2 with
    | none => simp only [Option.bind_none]
    | some s2 =>
        have hv1 := commit?_readVersion h2
        have hv2 := commit?_version h2
        have h1v : t1.readVersion = s.version := by
          rw [h]
          exact hv1
        have hstale : t1.readVersion ≠ s2.version := by
          rw [h1v, hv2]
          omega
        simp only [Option.bind_some]
        exact r6_stale_commit_rejected s2 t1 hstale

/-- R6 + R5: once an order is in a terminal status, no commit on it can succeed. -/
theorem r6_terminal_commit_rejected (s : OrderState) (t : Txn)
    (h : isTerminal s.status = true) : s.commit? t = none := by
  rw [commit?_eq_none_iff]
  rintro ⟨_, hread, hperm⟩
  rw [hread] at hperm
  rw [r5_terminal_no_outgoing s.status t.writeStatus h] at hperm
  simp at hperm

/-! ## R6 - committed histories: sequential and fresh (induction over the trace) -/

/-- R6 (traces): every committed write in a valid committed history is a permitted
transition. -/
theorem r6_trace_commits_permitted (s : OrderState) (cs : List CommitStep) :
    TraceValid s cs →
      ∀ c ∈ cs, isPermitted c.txn.readStatus c.txn.writeStatus = true := by
  revert s
  induction cs with
  | nil =>
      intro s h c hc
      cases hc
  | cons c rest ih =>
      intro s h d hd
      obtain ⟨_, hstep, hrest⟩ := traceValid_cons h
      rcases List.mem_cons.mp hd with rfl | hd
      · exact commit?_permitted hstep
      · exact ih c.after hrest d hd

/-- R6 (traces): in a valid committed history every committed write read exactly the
state it wrote against (it did not read a stale snapshot). -/
theorem r6_trace_fresh_reads (s : OrderState) (cs : List CommitStep) :
    TraceValid s cs →
      ∀ c ∈ cs,
        c.txn.readVersion = c.before.version ∧ c.txn.readStatus = c.before.status := by
  revert s
  induction cs with
  | nil =>
      intro s h c hc
      cases hc
  | cons c rest ih =>
      intro s h d hd
      obtain ⟨_, hstep, hrest⟩ := traceValid_cons h
      rcases List.mem_cons.mp hd with rfl | hd
      · exact ⟨commit?_readVersion hstep, commit?_readStatus hstep⟩
      · exact ih c.after hrest d hd

/-- R6 (traces): every committed write increments the version by one, so committed
writes are ordered sequentially. -/
theorem r6_trace_versions_increment (s : OrderState) (cs : List CommitStep) :
    TraceValid s cs →
      ∀ c ∈ cs, c.after.version = c.before.version + 1 := by
  revert s
  induction cs with
  | nil =>
      intro s h c hc
      cases hc
  | cons c rest ih =>
      intro s h d hd
      obtain ⟨_, hstep, hrest⟩ := traceValid_cons h
      rcases List.mem_cons.mp hd with rfl | hd
      · exact commit?_version hstep
      · exact ih c.after hrest d hd

/-- R6 (traces): each committed write read the status and version that were committed
immediately before it, so a committed history is sequential and fresh. -/
theorem r6_trace_consecutive_fresh (s : OrderState) (cs : List CommitStep) :
    TraceValid s cs → ConsecutiveFresh cs := by
  revert s
  induction cs with
  | nil =>
      intro s h
      simp [ConsecutiveFresh]
  | cons c rest ih =>
      intro s h
      cases rest with
      | nil => simp [ConsecutiveFresh]
      | cons c2 rest2 =>
          obtain ⟨_, _, hrest⟩ := traceValid_cons h
          obtain ⟨hlink, hstep2, _⟩ := traceValid_cons hrest
          unfold ConsecutiveFresh
          refine ⟨?_, ?_, ih c.after hrest⟩
          · rw [← hlink]
            exact commit?_readStatus hstep2
          · rw [← hlink]
            exact commit?_readVersion hstep2

/-- R6 + R5 (traces): in a valid committed history no committed write starts from a
terminal status. -/
theorem r6_trace_no_commit_from_terminal (s : OrderState) (cs : List CommitStep)
    (h : TraceValid s cs) :
    ∀ c ∈ cs, isTerminal c.before.status = false := by
  intro c hc
  have hread := r6_trace_fresh_reads s cs h c hc
  have hperm := r6_trace_commits_permitted s cs h c hc
  rw [hread.2] at hperm
  cases ht : isTerminal c.before.status with
  | false => rfl
  | true =>
      rw [r5_terminal_no_outgoing c.before.status c.txn.writeStatus ht] at hperm
      simp at hperm

end Specs
