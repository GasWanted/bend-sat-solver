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


# Generated from: benchmarks/sat_25v_s1.cnf
# Variables: 25, Clauses: 107

def main():
  formula = [[5, 19, -25], [-16, 21, 13], [-13, 14, 20], [-24, -8, 19], [1, -21, -18], [-14, -24, -1], [18, 8, 12], [-10, -1, -14], [-6, 21, 24], [-24, 23, -17], [22, -7, 10], [-17, 13, -19], [13, -14, -22], [22, -24, 12], [6, -17, 13], [-10, 23, 20], [-17, -8, -1], [8, -13, 17], [-9, -22, 18], [-24, -17, 5], [-2, 16, -12], [16, -12, -14], [-20, -11, -15], [-18, -19, -6], [9, -2, 22], [25, -9, 8], [10, -3, 6], [9, -21, 23], [4, 1, 10], [-4, 9, -24], [1, -8, 13], [23, -17, -22], [21, -23, 17], [-22, 19, -11], [5, -7, 2], [10, 24, 6], [-2, -19, 7], [-25, 23, 20], [-7, -19, 22], [-22, 13, -10], [13, -10, -1], [19, 5, 11], [-13, -18, -12], [25, 18, 8], [6, 18, -7], [9, 12, -11], [-20, 25, -23], [4, 11, -2], [-5, -11, 4], [-19, -18, 8], [-10, 19, 18], [-2, 10, 1], [-2, -7, 8], [15, -6, 22], [-13, -18, 10], [7, 21, -11], [10, 24, 20], [-3, 11, 20], [-20, 25, 18], [6, 18, 7], [9, -3, -25], [8, 13, -10], [19, -10, -8], [20, -3, 8], [-9, 18, 3], [25, -12, 16], [-25, -11, 3], [5, -11, -10], [10, -5, 7], [-11, -20, -22], [23, -7, 6], [-22, -8, 9], [-14, -18, 9], [13, 11, -6], [14, 19, 1], [-5, 9, 13], [-16, -1, -6], [-15, 22, 21], [16, -8, -23], [21, 9, -8], [-12, -6, 17], [23, -10, -18], [-20, -3, -4], [6, -5, -9], [2, -16, 22], [-6, -18, 24], [9, -21, -4], [-5, -25, -20], [-15, -8, 13], [-11, 15, 5], [14, 20, 18], [-8, -13, -24], [-19, 1, 21], [-6, 10, -5], [-9, -22, -15], [18, 12, 16], [-13, -7, 10], [-19, -24, -1], [-21, -5, 3], [-17, 22, 12], [23, 15, -12], [22, -19, 16], [-18, -1, -9], [-24, 17, -7], [-14, 24, 23], [20, -22, -17], [19, -14, -13]]
  asgn = init_map(25)
  return dpll(formula, asgn, 25)
