# bend-sat-solver

A parallel SAT solver built on [Bend](https://github.com/HigherOrderCO/Bend) / [HVM2](https://github.com/HigherOrderCO/HVM), exploring whether HVM's automatic parallelism can accelerate Boolean satisfiability solving.

## Thesis

SAT solvers explore a binary search tree of variable assignments. Current state-of-the-art solvers (CaDiCaL, Kissat) are single-threaded at core. Parallel SAT solvers plateau at 2-4x speedup on 64 cores due to clause-sharing overhead.

HVM's interaction net model provides **structural sharing** — when parallel branches encounter identical subproblems, they're computed once. This maps to clause learning: a conflict discovered in one branch could automatically prune equivalent conflicts in other branches, without explicit synchronization.

This project tests that thesis with a concrete implementation.

## How it works

The solver implements **parallel DPLL** (Davis-Putnam-Logemann-Loveland) with unit propagation:

1. **Unit propagation** — Find clauses with exactly one unset literal, force that literal
2. **Evaluate** — Check if all clauses are satisfied (SAT) or any clause is violated (UNSAT)
3. **Branch** — Pick an unassigned variable, explore both `TRUE` and `FALSE` assignments **in parallel** via HVM's automatic scheduling

```python
def dpll(formula, assignment, num_vars):
    assignment = unit_propagate(assignment, formula)
    status = eval_formula(assignment, formula)
    if status == SAT:  return 1
    if status == UNSAT: return 0

    var = pick_unassigned_variable(assignment)

    # HVM evaluates BOTH branches across available CPU cores
    left  = dpll(formula, set(assignment, var, TRUE),  num_vars)
    right = dpll(formula, set(assignment, var, FALSE), num_vars)

    return left OR right
```

Since Bend is a pure functional language, both branches are independent expressions with no shared mutable state. HVM's runtime distributes them across cores automatically — no threads, no locks, no message passing.

## Usage

```bash
# Generate a random 3-SAT instance (20 vars, 85 clauses, phase transition ratio)
python3 gen_cnf.py 20 85 3 42 > problem.cnf

# Convert DIMACS CNF to Bend program
python3 cnf_to_bend.py problem.cnf > problem.bend

# Solve (parallel, multi-core)
bend run-c problem.bend

# Solve (single-thread baseline)
bend run-rs problem.bend

# Output: "Result: 1" (SAT) or "Result: 0" (UNSAT)
```

### Run benchmarks

```bash
# Requires CaDiCaL (built from source)
./benchmark.sh ~/.local/bin/cadical
```

## Benchmark Results

**System:** 24-core machine, Bend 0.2.38, HVM 2.0.22, CaDiCaL 3.0.0

| Vars | Clauses | CaDiCaL | Bend (parallel) | Bend (single) | Result | Parallel Speedup |
|------|---------|---------|-----------------|----------------|--------|-----------------|
| 10 | 43 | 5ms | 329ms | 285ms | SAT | 0.87x |
| 10 | 43 | 4ms | 313ms | 346ms | SAT | 1.11x |
| 10 | 43 | 5ms | 491ms | 411ms | SAT | 0.84x |
| 15 | 64 | 6ms | 1,164ms | 1,209ms | UNSAT | 1.04x |
| 15 | 64 | 8ms | 1,632ms | 1,259ms | SAT | 0.77x |
| 15 | 64 | 6ms | 1,057ms | 970ms | UNSAT | 0.92x |
| 20 | 85 | 6ms | 2,798ms | 2,443ms | SAT | 0.87x |
| 20 | 85 | 10ms | 3,839ms | 3,062ms | SAT | 0.80x |
| 20 | 85 | 8ms | 4,150ms | 3,844ms | SAT | 0.93x |
| 25 | 107 | 6ms | 6,806ms | 10,293ms | SAT | **1.51x** |
| 25 | 107 | 9ms | 13,028ms | 12,367ms | SAT | 0.95x |
| 30 | 128 | 7ms | 30,109ms | 28,087ms | SAT | 0.93x |
| 30 | 128 | 8ms | 39,194ms | 24,948ms | SAT | 0.64x |

**Correctness: 13/13** (all results match CaDiCaL)

**Average parallel speedup: 0.94x** (effectively no speedup)

## Honest Assessment

### What works

- **Correctness** — The solver produces correct SAT/UNSAT results on all test instances
- **Clean parallel code** — The branching logic is genuinely parallel with zero synchronization code
- **Proof of concept** — Demonstrates that a functional SAT solver on HVM is viable

### What doesn't work (yet)

**CaDiCaL is ~500-5000x faster.** Expected — CaDiCaL has:
- CDCL with clause learning (our solver has none)
- VSIDS variable selection heuristic (we use first-unset)
- Two-watched-literal scheme for O(1) unit propagation (we scan all clauses)
- Decades of engineering in cache-friendly C++

**No meaningful parallel speedup.** The `run-c` (multi-core) backend is NOT consistently faster than `run-rs` (single-core). One instance showed 1.51x at 25 variables, but most show no improvement or slight slowdowns. Root causes:

1. **List-based assignments are O(n) per access** — We can't use Bend's built-in `Map` type because it fails on duplication (an HVM limitation). The list-based fallback serializes variable lookups, creating sequential bottlenecks that prevent parallel branches from running independently.

2. **Unit propagation serializes the computation** — Each propagation step depends on the previous one, creating a sequential chain that dominates small instances.

3. **HVM compilation overhead** — `bend run-c` compiles Bend → HVM → C → binary on every run. This overhead (~200-500ms) is significant relative to solve time.

4. **Search trees are too small** — At 10-30 variables, the search tree isn't wide enough for 24 cores to stay busy. The 1.51x speedup at 25 vars suggests parallelism starts helping with larger trees.

### Path to real speedups

To actually demonstrate HVM's parallel advantage, the solver needs:

1. **Tree-based assignments** — A custom balanced binary tree (not Bend's Map) that supports O(log n) access AND is duplicable in HVM. This is the single biggest bottleneck.

2. **Larger problem support** — 100+ variables, where the search tree is wide enough to saturate multiple cores. Requires solving the assignment duplication problem first.

3. **CDCL with interaction-net clause sharing** — The theoretical advantage of HVM is that learned clauses could be shared between parallel branches via the interaction net's structural sharing. This requires implementing full CDCL, which is a significant effort.

4. **Pre-compiled binary** — Eliminate the compile-on-every-run overhead by using `bend gen-c` to generate C code and compiling once.

## Project Structure

```
bend-sat-solver/
├── solver.bend      # Core DPLL solver in Bend
├── cnf_to_bend.py   # DIMACS CNF → Bend converter
├── gen_cnf.py       # Random k-SAT instance generator
├── benchmark.sh     # Benchmark runner (vs CaDiCaL)
├── results.csv      # Raw benchmark data
├── PRD.md           # Product requirements document
└── README.md        # This file
```

## Requirements

- [Bend](https://github.com/HigherOrderCO/Bend) 0.2.x
- [HVM](https://github.com/HigherOrderCO/HVM) 2.x
- Python 3.8+
- [CaDiCaL](https://github.com/arminbiere/cadical) (for benchmarking)

## License

MIT
