/-
Root module of the Lean verification artifact for the order lifecycle rules R1-R6.

`Specs.Model` is the abstraction (statuses, permitted transitions, creation status rule,
versioned write model). `Specs.Proofs` is the shared proof library. `Specs.Rules` states
and proves one theorem set per confirmed rule. `Specs.Examples` instantiates every rule
concretely (non-vacuity).
-/

import Specs.Model
import Specs.Proofs
import Specs.Rules
import Specs.Examples
