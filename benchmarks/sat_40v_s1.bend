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


# Generated from: benchmarks/sat_40v_s1.cnf
# Variables: 40, Clauses: 172

def main():
  formula = [[9, 37, 5], [25, -14, 7], [39, -1, -29], [7, -21, 2], [-25, -14, -28], [32, -36, -15], [-19, -2, -27], [-12, -19, -8], [33, -28, -13], [-33, 26, -38], [26, -27, -12], [-24, 6, 29], [-26, 24, 32], [-40, 38, 26], [-1, -13, 35], [-23, -37, -30], [-1, -25, -33], [-28, -4, 31], [-33, 27, 32], [35, 40, 22], [12, 36, -38], [17, 3, 5], [-18, 16, 8], [-11, -17, -34], [19, 30, 21], [22, 27, -13], [-14, 39, 28], [10, -3, 11], [15, -34, 29], [37, 21, -28], [-4, 20, -5], [11, 27, -37], [-3, -38, 14], [40, 33, 3], [28, -38, 13], [33, -32, -2], [-2, -11, -13], [9, -22, -28], [36, -23, 35], [3, -6, 9], [-22, 39, 33], [-19, -16, 39], [38, 36, 7], [10, -9, -22], [5, 37, 36], [-19, 37, 35], [-3, 19, 1], [-3, -13, 16], [29, -11, 16], [-25, -35, 19], [14, -21, -3], [39, 21, 29], [21, 39, -30], [35, -31, 23], [-16, 24, -6], [-6, 37, 22], [-21, 12, 38], [-35, 40, 38], [16, -26, -5], [-2, 1, 19], [-10, 7, -33], [12, -10, -21], [-39, 19, -9], [-3, -21, -40], [14, 12, -20], [-16, 17, 5], [-17, 35, 29], [22, -11, -17], [-37, -2, -4], [9, 17, -18], [15, 32, -1], [29, -15, -16], [-27, -22, -36], [-15, -4, 5], [33, 14, -20], [11, 30, -39], [33, 37, 25], [-37, -4, 32], [-33, 11, -35], [-17, 7, -18], [-40, 6, -29], [-28, 26, -11], [32, -14, -8], [19, -18, -16], [34, -29, -38], [17, -14, 12], [-38, -17, -29], [35, 23, 32], [-25, -14, 19], [37, -1, -35], [9, -5, 33], [23, 34, 21], [20, -35, -26], [-8, -25, -14], [-33, -13, -30], [-20, -11, 29], [1, 25, -38], [-38, 5, -32], [-19, 2, -27], [-26, -18, -12], [-23, -17, 27], [17, 32, -11], [38, -28, 5], [33, -11, -6], [-14, 34, 16], [-34, -24, 30], [-36, 18, -23], [-12, 31, 17], [-40, -16, 2], [28, -16, 18], [-38, 29, -10], [9, 29, 24], [14, 20, 5], [7, -12, -3], [-14, -3, -32], [-40, 29, -22], [12, 7, 15], [-11, 15, -16], [14, -29, -17], [-6, -3, 1], [-25, 38, -19], [10, -2, -1], [37, 25, -17], [1, -3, 35], [18, 8, -28], [18, -13, -29], [-16, -4, 38], [-39, -36, -34], [-35, 13, 28], [40, 5, 17], [14, 28, -3], [31, 33, 24], [-3, -29, -9], [29, 2, 34], [20, 3, -25], [-17, 25, 8], [16, -33, -36], [26, -38, 31], [-36, -38, -34], [19, -11, 13], [23, 9, -37], [35, 21, 27], [-34, 33, -1], [21, 37, 5], [-24, -25, 6], [-34, 32, 37], [-37, -22, 24], [-20, -30, 39], [-10, -17, 15], [-27, -40, -4], [7, -14, -17], [-5, 14, -12], [-32, -19, -15], [-16, -28, -29], [31, 5, -17], [25, -33, -32], [38, -28, 3], [20, 1, -35], [-21, 35, 37], [-34, 27, 39], [33, -29, -38], [-17, -1, 28], [-26, -19, -2], [25, -18, -30], [31, 22, 25], [-27, -10, 2], [-9, 38, -19], [19, -27, 18], [32, 26, -28], [15, 2, -7], [26, -12, -1], [36, 14, -35]]
  asgn = init_map(40)
  return dpll(formula, asgn, 40)
