#!/usr/bin/env python3
"""
Converts a DIMACS CNF file to a Bend program that solves it.

Usage: python3 cnf_to_bend.py input.cnf > problem.bend

The output is a complete Bend program containing:
  1. The solver library (from solver.bend)
  2. A main() function with the formula embedded
"""

import sys
import os

def parse_dimacs(filename):
    """Parse a DIMACS CNF file. Returns (num_vars, num_clauses, clauses)."""
    clauses = []
    num_vars = 0
    num_clauses = 0
    current_clause = []

    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('c'):
                continue
            if line.startswith('p'):
                parts = line.split()
                num_vars = int(parts[2])
                num_clauses = int(parts[3])
                continue
            # Parse literals
            for token in line.split():
                lit = int(token)
                if lit == 0:
                    if current_clause:
                        clauses.append(current_clause)
                        current_clause = []
                else:
                    current_clause.append(lit)

    if current_clause:
        clauses.append(current_clause)

    return num_vars, num_clauses, clauses

def encode_literal(lit):
    """Encode a DIMACS literal to our format: var*2 for positive, var*2+1 for negative."""
    if lit > 0:
        return lit * 2
    else:
        return (-lit) * 2 + 1

def clause_to_bend(clause):
    """Convert a clause to Bend list syntax."""
    encoded = [str(encode_literal(lit)) for lit in clause]
    return "[" + ", ".join(encoded) + "]"

def formula_to_bend(clauses):
    """Convert the entire formula to Bend nested list syntax."""
    bend_clauses = [clause_to_bend(c) for c in clauses]
    return "[" + ", ".join(bend_clauses) + "]"

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} input.cnf", file=sys.stderr)
        sys.exit(1)

    cnf_file = sys.argv[1]
    num_vars, num_clauses, clauses = parse_dimacs(cnf_file)

    # Read solver library
    solver_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'solver.bend')
    with open(solver_path, 'r') as f:
        solver_code = f.read()

    # Remove the comment about main() being appended
    solver_code = solver_code.rstrip()
    if solver_code.endswith("# main() is appended by cnf_to_bend.py with the specific formula"):
        solver_code = solver_code[:solver_code.rfind("#")].rstrip()

    # Generate the Bend program
    print(solver_code)
    print()
    print(f"# Generated from: {cnf_file}")
    print(f"# Variables: {num_vars}, Clauses: {num_clauses}")
    print()
    print("def main():")
    print(f"  formula = {formula_to_bend(clauses)}")
    print(f"  asgn = zeros({num_vars + 1})")
    print(f"  return dpll(formula, asgn, {num_vars})")

if __name__ == "__main__":
    main()
