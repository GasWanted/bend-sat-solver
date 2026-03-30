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


# Generated from: benchmarks/sat_30v_s2.cnf
# Variables: 30, Clauses: 129

def main():
  formula = [[28, -2, -3], [22, 28, 10], [-22, -6, -14], [-17, -12, -18], [28, 1, 12], [-29, 17, 6], [-11, 6, -5], [18, 6, -29], [-30, 25, -12], [15, -6, -25], [-8, -16, -9], [12, -22, 29], [-24, 30, 18], [-11, -27, -23], [25, -30, -16], [-17, 18, -21], [-16, -17, 12], [27, -11, -24], [-4, 2, 19], [-29, 30, 4], [27, -7, -29], [2, 12, 6], [-3, 1, 2], [-27, -30, 6], [-19, 2, 26], [-12, 20, 21], [-1, -10, 15], [-9, -25, 13], [-8, -3, 22], [-26, -28, 5], [-11, 5, -28], [-14, -21, -1], [9, 2, -5], [-17, -30, 23], [15, 3, -9], [20, 23, -12], [1, 5, -2], [3, 8, 4], [-7, 1, -17], [-13, -7, -22], [-14, 17, 1], [-17, -19, 6], [1, 17, -30], [30, -12, 10], [-10, -7, -27], [2, 14, -21], [3, 1, -10], [8, -25, 16], [15, -5, 25], [-4, -3, -20], [-23, 4, 1], [23, 16, -10], [-9, -16, -17], [-14, 30, 16], [-16, -20, -9], [-3, 19, 24], [18, 5, 26], [-29, 22, 26], [-8, 23, 22], [-10, -4, -5], [4, -11, 17], [6, -15, 23], [25, 19, 24], [-20, 13, 29], [-9, 13, -23], [-12, -18, 11], [27, -28, 24], [-22, 13, 29], [23, 30, 29], [-13, 7, 24], [-4, -13, 27], [30, -19, 7], [22, -14, 16], [7, -25, -3], [-22, -3, -25], [-15, 9, 29], [-25, -12, -6], [-9, -22, 21], [-6, -16, 13], [-10, 18, -15], [13, -19, 15], [-5, -16, 23], [27, -11, 10], [-21, 13, -17], [-13, 20, -17], [3, 10, 2], [9, -2, 4], [12, 7, 11], [16, -15, -28], [-15, 21, 7], [-8, -16, 7], [5, -26, 8], [26, -27, -24], [-17, 19, 23], [-23, -28, -30], [-18, 20, 21], [6, 9, -29], [6, 11, 13], [-12, -3, -30], [1, -18, 11], [-10, 16, 21], [-16, 4, 5], [12, 9, 3], [-20, -2, -11], [-28, 5, -6], [-5, 11, -17], [23, 20, -13], [16, -20, -28], [-19, 17, 18], [23, -15, 6], [4, -15, -19], [30, 6, -3], [9, 4, 22], [-22, -3, 11], [29, 16, 8], [23, 17, -18], [-27, -17, 11], [-16, 1, 5], [26, 2, -20], [-28, -13, -29], [22, -6, -17], [7, 6, 13], [-5, -13, -11], [-16, 9, 10], [-14, -23, 5], [18, 25, 7], [-5, -21, 1], [-2, 24, 25], [11, 2, -23]]
  asgn = init_map(30)
  return dpll(formula, asgn, 30)
