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

Uses Map-based assignments (O(log n) per access) with DIMACS literal encoding.

| Vars | Clauses | CaDiCaL | Bend (parallel) | Bend (single) | Result | Parallel Speedup |
|------|---------|---------|-----------------|----------------|--------|-----------------|
| 10 | 43 | 10ms | 741ms | 400ms | SAT | 0.54x |
| 10 | 43 | 5ms | 919ms | 532ms | SAT | 0.58x |
| 10 | 43 | 7ms | 865ms | 613ms | SAT | 0.71x |
| 15 | 64 | 8ms | 3,411ms | 2,027ms | UNSAT | 0.59x |
| 15 | 64 | 6ms | 2,619ms | 1,933ms | SAT | 0.74x |
| 15 | 64 | 6ms | 1,761ms | 1,266ms | UNSAT | 0.72x |
| 20 | 85 | 5ms | 5,421ms | 4,017ms | SAT | 0.74x |
| 20 | 85 | 7ms | 6,746ms | 5,221ms | SAT | 0.77x |
| 20 | 85 | 7ms | 8,299ms | 7,083ms | SAT | 0.85x |
| 25 | 107 | 7ms | 19,697ms | 21,570ms | SAT | **1.10x** |
| 25 | 107 | 10ms | 20,906ms | 22,259ms | SAT | **1.06x** |
| 30 | 128 | 9ms | 39,504ms | 46,897ms | SAT | **1.19x** |
| 30 | 128 | 8ms | 53,241ms | 58,534ms | SAT | **1.10x** |

**Correctness: 13/13** (all results match CaDiCaL)

### Parallel scaling trend

The key finding: **parallel speedup increases with problem size**.

| Problem size | Avg parallel speedup (run-c / run-rs) |
|-------------|--------------------------------------|
| 10 vars | 0.61x (overhead dominates) |
| 15 vars | 0.68x |
| 20 vars | 0.79x |
| **25 vars** | **1.08x** (crossover — parallel wins) |
| **30 vars** | **1.15x** |

At 25+ variables, `bend run-c` (multi-core) consistently outperforms `bend run-rs` (single-core). The trend suggests larger problems would show more significant speedups as the search tree grows wider and provides more independent work for parallel cores.

## Analysis

### What works

- **Correctness** — The solver produces correct SAT/UNSAT results on all test instances
- **Clean parallel code** — The branching logic is genuinely parallel with zero synchronization code
- **Demonstrated parallel speedup** — At 25+ variables, multi-core consistently beats single-core
- **Scaling trend** — Speedup improves with problem size, suggesting the approach has legs

### What limits performance

**CaDiCaL is ~1000-5000x faster.** Expected — CaDiCaL has:
- CDCL with clause learning (our solver has none)
- VSIDS variable selection heuristic (we use first-unset)
- Two-watched-literal scheme for O(1) unit propagation (we scan all clauses)
- Decades of engineering in cache-friendly C++

**HVM compilation overhead.** `bend run-c` compiles Bend -> HVM -> C -> binary on every run. This ~200-500ms overhead is why small problems show negative speedup — the compilation cost dwarfs solve time.

**Unit propagation serializes.** Each propagation step depends on the previous one, creating a sequential chain that limits parallelism in the early stages of solving.

### Bend/HVM gotcha: Map initialization

A non-obvious Bend behavior: `Map/get` on a missing key returns `unreachable` (ERA/erased value), not `0`. This ERA propagates through arithmetic, silently corrupting results. The fix: **always pre-initialize all Map keys** before use.

```bend
# BROKEN: missing keys return 'unreachable'
a = {}
val = a[1]    # → 'unreachable', not 0
x = val + 1   # → * (corrupted)

# CORRECT: pre-initialize all keys
def init_map(n):
  if n == 0:
    return {0: 0}
  else:
    m = init_map(n - 1)
    m[n] = 0
    return m

a = init_map(3)
val = a[1]    # → 0
x = val + 1   # → 1
```

### Path to bigger speedups

1. **Larger problems (50-200 vars)** — The scaling trend predicts 1.5-3x at 50+ vars. Need to test, but solve times may exceed 60s timeout.
2. **Pre-compiled binary** — Using `bend gen-c` + `gcc` once would eliminate the per-run compilation overhead, making speedups visible even on small problems.
3. **CDCL with clause learning** — Would close the gap with CaDiCaL while leveraging HVM's structural sharing for automatic parallel clause propagation.
4. **Variable selection heuristics** — VSIDS or similar activity-based heuristics would dramatically reduce the search tree size.

## Project Structure

```
bend-sat-solver/
├── solver.bend      # Core DPLL solver in Bend (Map-based)
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
