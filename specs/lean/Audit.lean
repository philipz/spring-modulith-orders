/-
Axiom audit for the headline theorems (Rule 3 guardrail).

Run from the Lean project directory:

    export PATH="$HOME/.elan/bin:$PATH"
    lake env lean Audit.lean

Every line below must print `'<theorem>' depends on axioms: [propext, Classical.choice,
Quot.sound]` (or `does not depend on any axioms`). Any other name -- in particular
`sorryAx`, `Lean.ofReduceBool`, `Lean.trustCompiler` -- is a guardrail failure. A
missing theorem line means the audit did not run, which is also a failure.
-/
import Specs

open Specs

/-! ## R1 - creation -/
#print axioms r1_create_none
#print axioms r1_create_new
#print axioms r1_create_other_rejected
#print axioms r1_create_iff
#print axioms r1_created_initial_write
#print axioms r1_all_statuses

/-! ## R2 - normal flow is single steps -/
#print axioms r2_permitted_normal_iff_rank_succ

/-! ## R3 - cancellation -/
#print axioms r3_permitted_cancel_iff

/-! ## R4 - error -/
#print axioms r4_permitted_error_iff

/-! ## R5 - terminal states, same-state writes, transition table -/
#print axioms r5_terminal_no_outgoing
#print axioms r5_same_state_rejected
#print axioms r5_to_new_rejected
#print axioms r5_permitted_iff_allowedPairs

/-! ## R6 - versioned writes and committed histories -/
#print axioms r6_commit_implies_permitted_and_bumped
#print axioms r6_stale_commit_rejected
#print axioms r6_stale_commit_keeps_state
#print axioms r6_same_version_cannot_both_commit
#print axioms r6_terminal_commit_rejected
#print axioms r6_trace_commits_permitted
#print axioms r6_trace_fresh_reads
#print axioms r6_trace_versions_increment
#print axioms r6_trace_consecutive_fresh
#print axioms r6_trace_no_commit_from_terminal
