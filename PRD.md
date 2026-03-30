# Bend SAT — Parallel SAT Solver on HVM

## Overview

Bend SAT is an open-source Boolean Satisfiability (SAT) solver built on Bend/HVM2. It exploits HVM's automatic parallelism to perform parallel DPLL search, where both branches of every variable decision are explored simultaneously across available CPU cores — without explicit threading, locks, or message passing.

## Problem

SAT solving underpins formal verification, chip design, AI planning, compiler optimization, package management, and cryptanalysis. Current state-of-the-art solvers (CaDiCaL, Kissat, MiniSat) are:

- **Single-threaded at core** — CDCL's clause learning creates dependencies that resist parallelization
- **Parallel solvers plateau at 2-4x** — Portfolio parallelism (run N independent solvers) doesn't scale with core count
- **No structural sharing** — Learned clauses must be explicitly communicated between threads, creating synchronization overhead

As core counts grow (64-256 core machines are common in cloud), the inability to parallelize SAT solving is an increasingly expensive bottleneck.

## Thesis

HVM's interaction net model provides **structural sharing** — when parallel branches of the search tree encounter identical subproblems, HVM computes them once and shares the result. This maps directly to clause learning: a conflict discovered in one branch automatically prunes equivalent conflicts in other branches, without explicit communication.

This project aims to prove that HVM's automatic parallelism can achieve **meaningful speedups** on SAT problems where the search tree has enough independent branches to exploit — specifically random 3-SAT instances near the phase transition.

## Goals

1. **Demonstrate parallel speedup** — Show measurably better wall-clock time on multi-core machines vs single-core, scaling with core count
2. **Competitive with baseline solvers** — Match or beat MiniSat-level performance on small-to-medium instances (up to 200 variables)
3. **Clean implementation** — Readable parallel DPLL in idiomatic Bend that demonstrates the programming model
4. **Reproducible benchmarks** — Automated benchmark suite comparing against CaDiCaL on standard problem sets

## Non-Goals

- Beating CaDiCaL on large industrial instances (thousands of variables) in v1
- Implementing full CDCL with restarts, VSIDS, clause deletion
- File I/O from Bend (we use a converter to embed problems)
- GPU execution via CUDA backend in v1

## Architecture

```
  DIMACS CNF file (.cnf)
         │
         ▼
  ┌─────────────────┐
  │  cnf_to_bend.py │  Converts DIMACS → Bend source with embedded formula
  └────────┬────────┘
           │
           ▼
  ┌─────────────────┐
  │   solver.bend   │  Parallel DPLL solver
  │                 │  - Unit propagation
  │                 │  - Pure literal elimination
  │                 │  - Parallel variable branching via HVM fork
  └────────┬────────┘
           │
     bend run-c     (parallel, multi-core)
     bend run-rs    (single-thread baseline)
           │
           ▼
     Result: SAT / UNSAT
```

## Algorithm: Parallel DPLL

```
solve(formula, assignment):
  1. Unit propagation — find unit clauses, assign forced variables
  2. Check formula:
     - All clauses satisfied → return SAT
     - Any clause empty (all literals false) → return UNSAT
  3. Choose unassigned variable (first unset)
  4. PARALLEL BRANCH (this is where HVM parallelism kicks in):
     - left  = solve(formula, assignment + {var=TRUE})
     - right = solve(formula, assignment + {var=FALSE})
     - return left OR right (SAT if either branch is SAT)
```

Step 4 is the key: in Bend, both recursive calls are independent expressions. HVM's runtime automatically schedules them across available cores. No threading code needed.

## Milestones

### M1: Working solver (week 1-2)
- Parallel DPLL in Bend with unit propagation
- DIMACS CNF → Bend converter
- Correctly solve small instances (20-50 vars)
- Verify correctness against CaDiCaL results

### M2: Benchmarks (week 3)
- Random 3-SAT generator at various sizes and clause ratios
- Automated benchmark runner (Bend vs CaDiCaL)
- Wall-clock comparison: run-c (parallel) vs run-rs (single-thread) vs CaDiCaL
- Results documented in README

### M3: Optimization (week 4+)
- Variable selection heuristics (most constrained variable)
- Clause watching for faster unit propagation
- Larger problem support (100-500 variables)
- Profile HVM parallel scaling (1, 2, 4, 8, 16, 24 cores)

## Success Criteria

- Solver produces correct SAT/UNSAT results on all test instances
- `bend run-c` (multi-core) is measurably faster than `bend run-rs` (single-core) on problems with 50+ variables
- Parallel speedup scales with core count (not just 2x on 24 cores)
- README with benchmark results demonstrating the thesis
