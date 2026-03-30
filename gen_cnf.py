#!/usr/bin/env python3
"""
Generates random k-SAT instances in DIMACS CNF format.

Usage: python3 gen_cnf.py <num_vars> <num_clauses> [clause_width] [seed]

The phase transition for 3-SAT occurs at ratio ~4.26 clauses/variables.
At this ratio, problems are hardest (roughly 50% SAT, 50% UNSAT).

Examples:
  python3 gen_cnf.py 20 85          # 20 vars, 85 clauses (ratio 4.25), 3-SAT
  python3 gen_cnf.py 50 213         # 50 vars, 213 clauses, 3-SAT
  python3 gen_cnf.py 100 426 3 42   # 100 vars, seed=42
"""

import random
import sys

def gen_random_ksat(num_vars, num_clauses, k=3, seed=None):
    """Generate a random k-SAT instance."""
    if seed is not None:
        random.seed(seed)

    clauses = []
    for _ in range(num_clauses):
        # Pick k distinct variables
        vars_in_clause = random.sample(range(1, num_vars + 1), min(k, num_vars))
        # Random polarity
        clause = []
        for v in vars_in_clause:
            if random.random() < 0.5:
                clause.append(v)
            else:
                clause.append(-v)
        clauses.append(clause)

    return clauses

def write_dimacs(num_vars, clauses, outfile=sys.stdout):
    """Write clauses in DIMACS CNF format."""
    print(f"c Random {len(clauses[0])}-SAT instance", file=outfile)
    print(f"c {num_vars} variables, {len(clauses)} clauses", file=outfile)
    print(f"c ratio: {len(clauses)/num_vars:.2f}", file=outfile)
    print(f"p cnf {num_vars} {len(clauses)}", file=outfile)
    for clause in clauses:
        print(" ".join(str(lit) for lit in clause) + " 0", file=outfile)

def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <num_vars> <num_clauses> [clause_width=3] [seed]", file=sys.stderr)
        sys.exit(1)

    num_vars = int(sys.argv[1])
    num_clauses = int(sys.argv[2])
    k = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    seed = int(sys.argv[4]) if len(sys.argv) > 4 else None

    clauses = gen_random_ksat(num_vars, num_clauses, k, seed)
    write_dimacs(num_vars, clauses)

if __name__ == "__main__":
    main()
