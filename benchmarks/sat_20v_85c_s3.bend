# Bend SAT Solver — Parallel DPLL via HVM
#
# A SAT solver that exploits HVM's automatic parallelism to explore
# both branches of every variable decision simultaneously.
#
# Data representation:
#   Assignment: Map from var_id → value (0=unset, 1=true, 2=false)
#     IMPORTANT: All variable keys must be pre-initialized to 0.
#     Map/get on missing keys returns 'unreachable' (ERA), which
#     poisons arithmetic. Pre-initialization avoids this.
#   Literal: DIMACS encoding (positive = var true, negative = var false)
#   Clause: List of literals
#   Formula: List of clauses
#
# This file is used as a template. The cnf_to_bend.py converter
# generates a complete .bend program by appending a main() function
# that embeds the specific CNF formula.

# --- Helpers ---

def abs(x):
  if x < 0:
    return (0 - x)
  else:
    return x

# Initialize map with keys 0..n all set to 0
def init_map(n):
  if n == 0:
    return {0: 0}
  else:
    m = init_map(n - 1)
    m[n] = 0
    return m

# --- Literal evaluation ---
# Uses DIMACS encoding: positive literal = var true, negative = var false

def eval_lit(asgn, lit):
  v = abs(lit)
  val = asgn[v]
  if lit > 0:
    return val
  else:
    if val == 0:
      return 0
    elif val == 1:
      return 2
    else:
      return 1

# --- Clause evaluation ---
# Returns: 1 = satisfied, 2 = unsatisfied (conflict), 0 = undetermined

def eval_clause(asgn, clause):
  match clause:
    case List/Nil:
      return 2
    case List/Cons:
      lv = eval_lit(asgn, clause.head)
      if lv == 1:
        return 1
      elif lv == 0:
        rest = eval_clause(asgn, clause.tail)
        if rest == 1:
          return 1
        else:
          return 0
      else:
        return eval_clause(asgn, clause.tail)

# --- Formula evaluation ---
# Returns: 1 = all clauses SAT, 2 = any clause UNSAT, 0 = undetermined

def eval_formula(asgn, formula):
  match formula:
    case List/Nil:
      return 1
    case List/Cons:
      cv = eval_clause(asgn, formula.head)
      if cv == 2:
        return 2
      elif cv == 0:
        rest = eval_formula(asgn, formula.tail)
        if rest == 2:
          return 2
        else:
          return 0
      else:
        return eval_formula(asgn, formula.tail)

# --- Unit propagation ---

def find_unit_in_clause(asgn, clause, unset_count, unset_lit):
  match clause:
    case List/Nil:
      if unset_count == 1:
        return unset_lit
      else:
        return 0
    case List/Cons:
      lv = eval_lit(asgn, clause.head)
      if lv == 1:
        return 0
      elif lv == 0:
        new_count = unset_count + 1
        if new_count > 1:
          return 0
        else:
          return find_unit_in_clause(asgn, clause.tail, new_count, clause.head)
      else:
        return find_unit_in_clause(asgn, clause.tail, unset_count, unset_lit)

def find_unit(asgn, formula):
  match formula:
    case List/Nil:
      return 0
    case List/Cons:
      u = find_unit_in_clause(asgn, formula.head, 0, 0)
      if u != 0:
        return u
      else:
        return find_unit(asgn, formula.tail)

def propagate_lit(asgn, lit):
  v = abs(lit)
  if lit > 0:
    asgn[v] = 1
    return asgn
  else:
    asgn[v] = 2
    return asgn

def unit_propagate(asgn, formula, steps):
  if steps == 0:
    return asgn
  else:
    u = find_unit(asgn, formula)
    if u == 0:
      return asgn
    else:
      new_asgn = propagate_lit(asgn, u)
      return unit_propagate(new_asgn, formula, steps - 1)

# --- Variable selection ---

def pick_var(asgn, var, num_vars):
  if var > num_vars:
    return 0
  else:
    val = asgn[var]
    if val == 0:
      return var
    else:
      return pick_var(asgn, var + 1, num_vars)

# --- DPLL Solver ---
# At each decision point, HVM automatically evaluates both branches
# (var=TRUE and var=FALSE) across available CPU cores.

def dpll(formula, asgn, num_vars):
  # Unit propagation
  asgn2 = unit_propagate(asgn, formula, num_vars)
  # Check formula status
  status = eval_formula(asgn2, formula)
  if status == 1:
    return 1
  elif status == 2:
    return 0
  else:
    v = pick_var(asgn2, 1, num_vars)
    if v == 0:
      return 0
    else:
      # PARALLEL BRANCH: HVM runs both simultaneously
      asgn_t = asgn2
      asgn_t[v] = 1
      asgn_f = asgn2
      asgn_f[v] = 2
      left = dpll(formula, asgn_t, num_vars)
      right = dpll(formula, asgn_f, num_vars)
      if left == 1:
        return 1
      else:
        return right


# Generated from: /home/box/GW/bend-sat-solver/benchmarks/sat_20v_85c_s3.cnf
# Variables: 20, Clauses: 85

def main():
  formula = [[8, -19, 18], [-19, 3, -1], [-7, 16, -18], [-5, -8, -20], [3, 6, -2], [16, -13, 14], [5, 12, 4], [-14, 10, 20], [-19, -14, -8], [-9, -6, -11], [7, 19, -9], [-16, 3, 12], [-10, 14, -19], [-2, -13, 11], [8, 2, -10], [-7, 14, 10], [-11, -20, 12], [-15, -17, -13], [20, -17, 9], [-10, -14, 9], [14, -19, -11], [2, -11, -15], [-9, -16, 1], [12, -9, 15], [-6, 11, -12], [4, 1, -5], [-8, -11, 6], [-20, 11, -19], [-6, 3, -11], [9, -8, 4], [19, -6, 9], [20, -12, -5], [15, -12, 14], [14, -5, -7], [-17, -14, 18], [-15, -17, -10], [-19, 10, -4], [-17, 7, -14], [6, 17, -10], [2, -4, -11], [2, -12, -8], [-6, -8, -9], [1, 16, 13], [17, 20, -14], [2, 5, -20], [3, 17, 19], [13, 20, 10], [4, -5, -18], [19, -6, -2], [13, -2, -14], [11, 14, -19], [19, 3, 14], [-11, 12, 18], [-4, -17, -13], [4, 19, 1], [-17, 3, -4], [-11, -4, -1], [-10, 19, -20], [17, -20, -8], [-2, 18, 11], [-6, -8, 15], [-12, -13, 20], [8, -14, -6], [-17, -16, 5], [-4, -16, 19], [-6, 5, -9], [-8, -18, -10], [-19, 20, 9], [-13, 7, 6], [-5, 14, -16], [-18, 1, -16], [-2, -15, -8], [3, 7, 9], [6, 2, 9], [3, -20, 4], [12, 15, 11], [-16, -3, 7], [5, 18, -11], [-4, 15, -17], [12, -20, -15], [-9, -4, 11], [16, 17, -12], [6, -5, 20], [-4, -18, -5], [-14, 18, 10]]
  asgn = init_map(20)
  return dpll(formula, asgn, 20)
