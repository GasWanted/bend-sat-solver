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


# Generated from: benchmarks/sat_30v_s1.cnf
# Variables: 30, Clauses: 129

def main():
  formula = [[-5, 19, 28], [-25, -15, 16], [1, -29, -27], [-23, 15, -9], [29, -11, 1], [29, 13, 22], [-8, -25, 15], [22, 8, 25], [-27, 30, -18], [24, 28, -10], [-23, -17, -30], [-7, 10, -19], [13, 19, -28], [14, -22, -6], [24, -12, -3], [17, -27, 13], [-10, -23, 28], [-6, -17, -8], [28, 18, -8], [12, -15, -30], [-1, -13, -26], [-17, -26, 5], [2, -16, -28], [14, 16, -27], [20, 26, 11], [6, 18, -19], [28, -27, -30], [3, -28, 1], [-9, 4, 26], [-6, -9, -17], [10, 15, 23], [-13, 11, 14], [-24, 17, -7], [8, -1, 13], [23, -17, -22], [-21, 26, -23], [-13, -22, 19], [-24, -10, 5], [-28, 3, 10], [19, -9, 5], [-27, 7, -29], [-25, 23, 20], [-7, -19, 22], [-22, 13, -10], [13, 29, 10], [19, 26, -5], [-27, -13, -30], [-18, 16, -25], [3, -5, 6], [-11, 20, 17], [-10, -8, -28], [-16, 5, 19], [-3, 13, 28], [-4, 20, -19], [-8, 19, 3], [18, 30, -4], [-27, 10, 1], [27, 29, -26], [14, -6, 4], [-28, 4, -14], [-30, -27, 10], [7, 21, -11], [10, 24, 20], [-3, -30, 11], [-7, -26, -20], [16, -22, 12], [-8, 12, -3], [-3, -21, 19], [10, -2, -11], [30, -10, -8], [20, -3, 8], [9, 18, -28], [10, 25, -26], [-4, 17, -25], [-6, -25, 5], [-4, -23, 17], [-7, 5, 18], [-29, -20, -26], [23, -7, 6], [28, 22, -8], [26, 14, -18], [1, 13, 27], [-21, 30, -14], [-19, 5, -9], [6, 20, -3], [-17, -29, -21], [-8, -11, -16], [-11, -18, 20], [-21, -8, -2], [-12, -6, 17], [-23, 10, -28], [-15, -20, -3], [19, 13, -6], [24, -25, -26], [-12, -13, -17], [17, 3, -26], [-3, -5, -25], [-3, -15, 28], [26, -29, 14], [-20, 30, -16], [-14, 30, 4], [-18, -1, 7], [20, 8, 27], [-7, 9, -10], [-26, 28, -6], [-25, 7, -19], [29, -26, -1], [-22, 25, -24], [19, -26, -10], [11, 1, 4], [-13, -11, 26], [-30, -13, -7], [-24, 29, -27], [20, -27, -17], [10, -23, 6], [17, 1, 22], [-28, -20, -19], [3, -16, 24], [-1, -14, -24], [26, 9, -28], [1, -12, -30], [18, 10, 5], [-17, -2, 9], [12, 3, -22], [6, -23, -3], [-7, 17, 8], [-27, 30, -17], [-2, -6, -10], [-9, 12, 20]]
  asgn = init_map(30)
  return dpll(formula, asgn, 30)
