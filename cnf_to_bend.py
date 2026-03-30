#!/usr/bin/env python3
"""
Converts a DIMACS CNF file to a Bend program that solves it.

Usage: python3 cnf_to_bend.py [--cdcl] input.cnf > problem.bend

Options:
  --cdcl   Use the CDCL-lite solver (solver_cdcl.bend) instead of
           the basic parallel DPLL solver (solver.bend).

The output is a complete Bend program containing:
  1. The solver library (from solver.bend or solver_cdcl.bend)
  2. For CDCL mode: a generated negate() function
  3. A main() function with the formula embedded
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

def clause_to_bend(clause):
    """Convert a clause to Bend list syntax using DIMACS literals directly."""
    return "[" + ", ".join(str(lit) for lit in clause) + "]"

def formula_to_bend(clauses):
    """Convert the entire formula to Bend nested list syntax."""
    bend_clauses = [clause_to_bend(c) for c in clauses]
    return "[" + ", ".join(bend_clauses) + "]"

def generate_negate_function(num_vars):
    """Generate the negate() function for CDCL mode.

    Bend's runtime arithmetic (0 - x) produces u24 underflow values
    that don't work correctly as DIMACS literals with abs() and
    comparison operators. This function uses an if-else chain with
    parser-level negative literals (-1, -2, ...) to ensure proper
    behavior.
    """
    lines = []
    lines.append("# Generated negate function for %d variables." % num_vars)
    lines.append("# Maps each literal to its negation using parser-level")
    lines.append("# negative literals to avoid Bend's u24 arithmetic issues.")
    lines.append("def negate(lit):")
    lines.append("  v = abs(lit)")
    for i in range(1, num_vars + 1):
        prefix = "if" if i == 1 else "elif"
        lines.append(f"  {prefix} v == {i}:")
        lines.append(f"    if lit > 0:")
        lines.append(f"      return -{i}")
        lines.append(f"    else:")
        lines.append(f"      return {i}")
    lines.append("  else:")
    lines.append("    return 0")
    return "\n".join(lines)

def main():
    # Parse arguments
    args = sys.argv[1:]
    use_cdcl = False

    if '--cdcl' in args:
        use_cdcl = True
        args.remove('--cdcl')

    if len(args) != 1:
        print(f"Usage: {sys.argv[0]} [--cdcl] input.cnf", file=sys.stderr)
        sys.exit(1)

    cnf_file = args[0]
    num_vars, num_clauses, clauses = parse_dimacs(cnf_file)

    # Read solver library
    if use_cdcl:
        solver_filename = 'solver_cdcl.bend'
    else:
        solver_filename = 'solver.bend'

    solver_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), solver_filename)
    with open(solver_path, 'r') as f:
        solver_code = f.read()

    # Generate the Bend program
    print(solver_code)
    print()

    # For CDCL mode, generate the negate() function
    if use_cdcl:
        print(generate_negate_function(num_vars))
        print()

    print(f"# Generated from: {cnf_file}")
    print(f"# Variables: {num_vars}, Clauses: {num_clauses}")
    if use_cdcl:
        print(f"# Solver: CDCL-lite (solver_cdcl.bend)")
    else:
        print(f"# Solver: Parallel DPLL (solver.bend)")
    print()
    print("def main():")
    print(f"  formula = {formula_to_bend(clauses)}")

    if use_cdcl:
        # Budget: start with num_vars (each restart doubles it)
        # Max restarts: 10 (final attempt uses budget 9999)
        initial_budget = num_vars
        max_restarts = 10
        print(f"  return solve_cdcl(formula, {num_vars}, {initial_budget}, {max_restarts})")
    else:
        print(f"  asgn = init_map({num_vars})")
        print(f"  return dpll(formula, asgn, {num_vars})")

if __name__ == "__main__":
    main()
