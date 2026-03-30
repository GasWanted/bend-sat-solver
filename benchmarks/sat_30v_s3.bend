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


# Generated from: benchmarks/sat_30v_s3.cnf
# Variables: 30, Clauses: 129

def main():
  formula = [[8, -19, 18], [19, -3, 20], [8, -7, 23], [21, 28, -5], [-13, 24, -1], [-19, -2, 10], [-20, -24, -30], [-13, -24, 26], [12, 4, -2], [-14, 25, -21], [-19, -12, -18], [-22, -30, -1], [6, -23, -28], [4, -23, -21], [10, -4, 3], [12, 26, 3], [25, -14, -28], [13, -23, -19], [17, 8, -2], [2, 7, -14], [-28, -11, 12], [15, -28, -17], [-4, 20, -26], [8, 30, 10], [11, -1, 26], [20, -19, 21], [12, -22, -30], [-1, 19, 2], [-21, 15, 10], [-11, 25, -12], [4, -25, -27], [-10, 17, 8], [-22, 14, 21], [11, -22, -27], [-3, -11, 24], [8, -26, 4], [-27, 19, -6], [3, 26, 20], [26, -28, 9], [-19, 14, 2], [-27, 29, -20], [30, 23, -8], [-24, -17, -10], [28, 19, 10], [-26, -23, -17], [19, 2, -1], [-8, 22, -1], [20, -4, -11], [26, 2, -12], [-4, -6, -8], [27, -30, 1], [25, -9, 8], [-16, -11, -25], [2, 4, -3], [17, 16, 11], [13, 19, 10], [4, -5, -18], [19, -6, -2], [13, -21, 26], [-21, 16, -25], [15, 1, -8], [26, -14, -8], [-12, 29, 18], [-4, -27, -24], [22, -4, -24], [23, -1, 16], [-3, 19, -4], [11, -27, -28], [-27, -23, 10], [-25, 19, -17], [4, 30, -18], [-27, -3, 8], [23, -25, -13], [18, 14, -3], [27, -24, -6], [30, -17, -22], [5, 6, -4], [-15, 19, -24], [5, 19, -17], [-25, 10, -22], [19, 9, 29], [-13, 7, 6], [-28, 5, -14], [-15, -19, 27], [-24, -3, -28], [2, 15, -30], [-22, 3, 7], [-9, -5, 6], [-30, 9, 6], [24, 26, -3], [-2, -12, 15], [11, 14, -13], [-16, 13, 5], [22, -14, 4], [-17, 23, 12], [-22, 21, -26], [-11, 22, 19], [12, -2, -23], [21, -24, -5], [4, 30, -18], [20, 14, 18], [26, -6, -23], [18, 19, 24], [2, -28, 5], [-25, -17, 12], [26, -25, 3], [-9, -19, -4], [4, 6, -23], [-27, 24, 5], [7, 18, -17], [12, -26, -10], [-27, -13, -11], [17, -22, 23], [-20, 7, -24], [-8, 16, 6], [-17, -7, -2], [-4, -19, 10], [-26, 3, -20], [-17, -3, 16], [-28, 12, -23], [-25, -30, 2], [26, 7, -30], [8, 16, 11], [7, 23, 6], [-28, 14, 7], [25, 23, 13], [9, -12, -28], [8, -1, 26], [15, 18, -7]]
  asgn = init_map(30)
  return dpll(formula, asgn, 30)
