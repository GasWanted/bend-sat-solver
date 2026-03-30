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


# Generated from: benchmarks/sat_35v_s3.cnf
# Variables: 35, Clauses: 150

def main():
  formula = [[16, -35, -9], [5, 1, -31], [-31, 35, -26], [-34, 25, -1], [-3, 20, -2], [-25, -28, -26], [9, 24, 7], [-28, 20, 27], [-27, -15, -22], [-11, -21, -35], [14, 18, -19], [-31, 6, 23], [-19, 28, -27], [-3, -25, 22], [16, 3, -20], [-13, 27, 19], [-22, -21, 24], [-30, -34, -25], [-33, -18, -28], [28, 17, -34], [-21, -2, 25], [-22, 30, -23], [-32, 2, 4], [30, 20, -21], [17, -20, -25], [9, -20, 33], [12, 28, 7], [15, -29, 11], [-29, 18, -15], [21, -12, 18], [23, -9, 27], [23, 27, -19], [10, -13, -1], [33, 28, -15], [34, 19, 35], [19, -8, -16], [13, -28, 4], [-20, 16, -2], [8, -22, 9], [4, -23, -15], [-11, -16, -18], [1, 32, 26], [34, -28, 4], [4, 9, -3], [6, 33, 32], [25, -20, 24], [-9, -1, 25], [-30, 35, -25], [-4, 24, -32], [27, -30, -2], [5, -28, -15], [24, 17, -8], [-34, -25, 7], [1, 31, -10], [-7, 25, -12], [-2, -8, -31], [-6, 3, -33], [-7, 4, 21], [-12, -16, 30], [-24, -26, 23], [16, -27, -11], [-34, -31, 10], [-7, -32, 31], [-12, 9, -18], [-15, -35, -19], [18, 14, 20], [12, -24, 16], [-31, -14, -30], [-2, 31, -5], [-3, -30, -15], [5, 14, 17], [12, 3, 17], [-6, 8, 17], [22, 1, 2], [14, 32, -26], [5, -28, 8], [34, -24, -29], [-17, -7, 22], [32, 33, -23], [-12, -10, 24], [-10, -22, 27], [20, 12, -5], [26, 23, -7], [3, -31, -33], [-22, -26, 29], [-8, -10, -18], [-8, -12, 13], [-9, -10, 26], [12, 13, -17], [29, -27, 25], [-32, -34, 20], [-13, -1, 7], [34, -30, 13], [-33, -29, -8], [-9, 30, 6], [15, 33, 5], [22, -23, -9], [-3, 6, 22], [13, 28, 15], [5, 13, 11], [28, 14, -32], [26, 29, 12], [24, 29, -34], [14, 17, 24], [-14, -2, -11], [9, 8, -11], [26, -29, 21], [26, -3, 32], [7, 25, 31], [8, -4, 19], [-20, 32, 16], [23, 21, 6], [-1, 7, -2], [-31, -4, 13], [-31, 22, 23], [26, 6, -19], [22, -35, -26], [-23, 12, 24], [-31, -23, -18], [25, -32, 3], [30, -6, -7], [-4, -29, 30], [24, -1, -5], [22, -20, 8], [4, 10, 1], [-33, -27, 21], [-12, 6, 3], [7, 13, 17], [7, -32, -23], [19, -29, 25], [5, -22, -23], [-24, 28, 5], [4, 22, 16], [-11, -14, 30], [-13, -27, 31], [3, 19, -2], [19, 33, 34], [14, 18, -32], [19, -10, 7], [-14, -10, -32], [24, 11, -28], [-35, 15, 24], [-24, -23, -20], [1, 9, -34], [1, -14, 30], [3, 32, -12], [4, 35, -7], [32, 27, 17], [-11, -16, 9], [22, 9, 18]]
  asgn = init_map(35)
  return dpll(formula, asgn, 35)
