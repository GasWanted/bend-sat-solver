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


# Generated from: benchmarks/sat_35v_s1.cnf
# Variables: 35, Clauses: 150

def main():
  formula = [[9, -5, 17], [25, -14, 7], [-1, 29, -18], [21, -2, -35], [28, 2, 34], [-15, -23, 30], [7, 12, -19], [33, -28, -13], [33, -26, 3], [12, -24, -6], [34, 26, 24], [26, 11, 33], [15, -26, 33], [-18, -1, -25], [-33, 9, -34], [-31, 24, -13], [-27, -23, -1], [-30, -2, 15], [-6, -17, 3], [-2, 29, 1], [12, 23, -19], [11, 18, 19], [2, -20, 25], [-17, 33, -14], [15, -2, 26], [-33, -28, -35], [-34, 29, -15], [-21, 28, 4], [-4, 20, -5], [11, -27, -17], [-14, -30, -11], [33, 3, -25], [28, -13, 32], [-32, 2, 21], [-11, -13, 21], [-28, -14, -18], [-23, -35, 32], [3, -6, 9], [22, 33, 17], [32, 9, 7], [10, -9, -22], [-5, 15, 6], [-35, 8, 30], [19, -1, -6], [13, 16, -27], [-11, 7, -28], [19, 17, 31], [-2, 1, 19], [-26, -5, 21], [-14, 35, -31], [20, -13, 16], [-29, 6, 22], [21, 12, -20], [6, 16, 15], [5, -2, 1], [-10, 7, -33], [12, -10, -21], [19, -9, 14], [21, -14, 12], [-16, 17, 5], [-17, 35, 29], [22, -11, -17], [-2, -4, 23], [-18, 26, 12], [-34, -21, -33], [15, 16, 21], [-27, 22, -18], [-33, -24, 11], [-20, -24, -11], [8, 33, 25], [-4, 32, -26], [-11, 35, 3], [-7, 18, -6], [-6, 29, -16], [-28, 26, -11], [32, -14, -8], [19, -18, -16], [34, -29, 2], [17, -14, 12], [-17, 29, -11], [-14, -25, 19], [-1, -35, -19], [9, -5, 33], [23, 34, 21], [20, -35, -26], [-8, -25, -14], [-33, -13, -30], [-20, -11, 29], [-1, 25, -28], [-5, -32, -16], [-27, -10, -26], [-1, 23, -17], [-20, 10, 30], [3, -18, 33], [5, -29, 2], [-6, 26, 18], [22, -18, -5], [-24, 30, 33], [18, 23, 15], [17, -22, 15], [-2, -26, 21], [-18, 13, -5], [29, 10, -17], [-29, 24, -20], [20, 5, -7], [-12, 3, -4], [-3, -32, -34], [-22, 18, 8], [15, 32, 29], [19, -30, 25], [8, -14, -6], [-21, 25, -19], [10, -2, -1], [25, -17, 9], [1, -3, 35], [18, 8, -28], [18, -13, -29], [16, -4, -12], [-34, -4, -23], [-35, -28, -5], [-5, 17, -12], [-28, -3, -4], [-33, 24, -7], [-29, -9, 26], [34, 18, 6], [25, 4, -17], [8, 20, -7], [-22, -33, 26], [29, -34, -35], [11, 13, 24], [9, -5, -3], [27, 20, -21], [33, 1, -34], [-21, 5, -29], [25, -6, -4], [17, -16, -22], [-26, 20, -30], [-2, -10, -17], [-12, -27, -4], [7, -14, -17], [-5, 14, -12], [-32, -19, -15], [-16, -28, -29], [31, 5, -17], [25, -33, -32], [-28, 3, 23], [20, 1, -35], [-21, -35, -19], [34, 27, 20], [-9, -11, -17]]
  asgn = init_map(35)
  return dpll(formula, asgn, 35)
