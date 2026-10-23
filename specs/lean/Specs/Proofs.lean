/-
Shared proof library (Rule 9): model-level lemmas reused by the rule theorems.

Nothing here states a business rule by itself; the rule statements and their complete
proofs live in `Specs/Rules.lean`. This module only records mechanical facts about
creation, the commit operation and the committed-trace datatype.
-/

import Specs.Model

namespace Specs

open OrderStatus

/-! ## R1: creation mechanics -/

/-- A successful creation always produces the NEW status. -/
theorem createStatus_created_new (requested : Option OrderStatus) (s : OrderStatus)
    (h : createStatus requested = some s) : s = NEW := by
  cases requested with
  | none =>
      simp only [createStatus, Option.some.injEq] at h
      exact h.symm
  | some r => cases r <;> simp_all [createStatus]

/-! ## R6: commit mechanics -/

/-- Characterisation of a successful commit. -/
theorem commit?_eq_some_iff (s : OrderState) (t : Txn) (s' : OrderState) :
    s.commit? t = some s' ↔
      t.readVersion = s.version ∧ t.readStatus = s.status ∧
        isPermitted t.readStatus t.writeStatus = true ∧
          s' = { status := t.writeStatus, version := s.version + 1 } := by
  unfold OrderState.commit?
  split
  · rename_i hc
    simp only [Option.some.injEq]
    constructor
    · intro h
      exact ⟨hc.1, hc.2.1, hc.2.2, h.symm⟩
    · rintro ⟨_, _, _, hs⟩
      exact hs.symm
  · rename_i hc
    constructor
    · intro h
      cases h
    · rintro ⟨h1, h2, h3, _⟩
      exact absurd ⟨h1, h2, h3⟩ hc

/-- A successful commit read the current version. -/
theorem commit?_readVersion {s : OrderState} {t : Txn} {s' : OrderState}
    (h : s.commit? t = some s') : t.readVersion = s.version :=
  ((commit?_eq_some_iff s t s').1 h).1

/-- A successful commit read the current status. -/
theorem commit?_readStatus {s : OrderState} {t : Txn} {s' : OrderState}
    (h : s.commit? t = some s') : t.readStatus = s.status :=
  ((commit?_eq_some_iff s t s').1 h).2.1

/-- A successful commit applied a permitted transition. -/
theorem commit?_permitted {s : OrderState} {t : Txn} {s' : OrderState}
    (h : s.commit? t = some s') : isPermitted t.readStatus t.writeStatus = true :=
  ((commit?_eq_some_iff s t s').1 h).2.2.1

/-- A successful commit wrote the transaction's target status. -/
theorem commit?_status {s : OrderState} {t : Txn} {s' : OrderState}
    (h : s.commit? t = some s') : s'.status = t.writeStatus := by
  rw [((commit?_eq_some_iff s t s').1 h).2.2.2]

/-- A successful commit incremented the version. -/
theorem commit?_version {s : OrderState} {t : Txn} {s' : OrderState}
    (h : s.commit? t = some s') : s'.version = s.version + 1 := by
  rw [((commit?_eq_some_iff s t s').1 h).2.2.2]

/-- A commit is rejected exactly when its snapshot is stale or its transition is not
permitted. -/
theorem commit?_eq_none_iff (s : OrderState) (t : Txn) :
    s.commit? t = none ↔
      ¬ (t.readVersion = s.version ∧ t.readStatus = s.status ∧
          isPermitted t.readStatus t.writeStatus = true) := by
  by_cases hc :
      t.readVersion = s.version ∧ t.readStatus = s.status ∧
        isPermitted t.readStatus t.writeStatus = true
  · have hsome : s.commit? t = some { status := t.writeStatus, version := s.version + 1 } := by
      unfold OrderState.commit?
      split
      · rfl
      · rename_i hnc
        exact absurd hc hnc
    rw [hsome]
    have hperm : isPermitted s.status t.writeStatus = true := by
      rw [← hc.2.1]
      exact hc.2.2
    simp [hc, hperm]
  · unfold OrderState.commit?
    split
    · rename_i h
      exact absurd h hc
    · simp [hc]

/-! ## R6: trace mechanics -/

/-- Decomposition of a valid committed history at its head. -/
theorem traceValid_cons {s : OrderState} {c : CommitStep} {cs : List CommitStep}
    (h : TraceValid s (c :: cs)) :
    c.before = s ∧ c.before.commit? c.txn = some c.after ∧ TraceValid c.after cs := by
  simpa [TraceValid] using h

end Specs
