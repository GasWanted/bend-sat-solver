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


# Generated from: benchmarks/sat_25v_s2.cnf
# Variables: 25, Clauses: 107

def main():
  formula = [[-2, -3, -12], [10, 9, -20], [-14, -21, -13], [-12, -18, -15], [-12, 15, -11], [6, 18, 8], [-17, -12, 22], [-14, -24, -17], [-12, 15, -6], [21, -17, -8], [-12, 22, -15], [18, 24, 15], [23, -6, 20], [-23, -17, -18], [10, 24, -7], [3, -11, -24], [-4, 2, 19], [4, 25, -17], [-2, 14, 23], [8, -22, 1], [24, -1, 12], [6, -17, -23], [8, -5, -2], [24, 4, 10], [25, 20, 24], [20, 23, -5], [11, -4, 1], [19, 25, -13], [-11, -9, -20], [5, 22, 2], [-15, -21, -8], [8, 23, 15], [20, 23, -12], [1, 5, -2], [3, 8, 4], [-7, 1, -17], [-13, -7, -22], [-14, 17, 1], [-17, -19, 6], [-1, 17, -4], [-12, 10, 1], [-7, -25, 22], [21, -16, 15], [10, -1, 12], [-16, 7, 4], [-25, 12, 13], [20, 11, 21], [-20, -22, 16], [-12, 15, -5], [-16, -24, 14], [-8, -6, -16], [-23, -3, 19], [-6, -18, -5], [22, 21, 2], [22, 11, 15], [25, 14, -4], [6, -15, 23], [25, 19, 24], [20, -13, 24], [-13, 9, -23], [-12, -18, 11], [-24, 8, -18], [21, -1, -11], [21, -6, -4], [-20, 13, -7], [-25, -7, 9], [-20, 5, 1], [-19, -6, -15], [-12, -1, 16], [-19, 16, -22], [-15, 1, -3], [-13, -9, -22], [2, 6, 16], [1, 10, 18], [13, -19, 15], [-5, -16, 23], [-11, 10, -21], [17, -3, -21], [5, 17, -21], [18, -8, 17], [13, 12, 7], [-6, 16, 15], [23, 15, 21], [-8, -16, 7], [-5, -8, 9], [-24, -11, -9], [-23, -24, -11], [21, -25, -23], [12, 10, -13], [-15, 16, -3], [5, 1, -4], [24, -25, 21], [20, -13, 18], [11, 7, 16], [9, 5, 14], [-23, 8, 24], [-25, 20, 2], [15, -25, -9], [-11, -21, 25], [2, -13, 25], [-20, -3, 19], [13, 23, 15], [4, -15, -19], [6, -3, 13], [4, 22, 12], [3, -11, 21], [-3, 16, -5]]
  asgn = init_map(25)
  return dpll(formula, asgn, 25)
