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


# Generated from: benchmarks/sat_40v_s3.cnf
# Variables: 40, Clauses: 172

def main():
  formula = [[16, -38, 35], [38, -5, 39], [-15, -13, 31], [10, 15, -34], [11, 38, -3], [-31, -39, 25], [-37, 29, 9], [-14, -17, 28], [-25, 37, 23], [-22, -2, 18], [-21, -35, 37], [37, 18, -19], [-31, 6, 23], [-19, 28, -27], [3, -25, -38], [33, 16, -3], [3, 13, -27], [-22, -21, 24], [-30, -34, -25], [40, -33, 18], [-20, -28, 17], [27, -38, -21], [4, -22, -30], [-18, -32, 2], [24, -17, 30], [-12, 21, -24], [-7, 2, -37], [18, 16, -21], [-7, -39, 21], [-11, 6, -22], [18, -15, 8], [37, -12, 18], [40, 23, -38], [-18, 30, -23], [3, 27, -10], [-40, -33, -28], [-3, -30, -34], [5, 38, 19], [-33, 13, -28], [11, 33, -20], [4, 40, -8], [31, 4, -23], [-8, -11, -16], [-1, 32, 37], [-18, 40, 34], [1, 4, 9], [-3, 6, 33], [23, 25, -38], [-28, -8, 9], [6, 37, -12], [-35, 25, 3], [-32, 21, 27], [-14, 35, 18], [-28, 9, -2], [-17, -8, -30], [-34, -25, 7], [38, -1, 31], [-6, 37, -7], [-22, -8, -2], [-19, 38, -20], [33, -34, -16], [-4, 36, 21], [-12, -16, 30], [-24, -39, -26], [-25, 33, -16], [-11, -27, -37], [-31, 10, 26], [-31, -34, 29], [-13, -10, -38], [-35, -19, -27], [14, -20, 2], [37, -24, 16], [31, -39, -14], [-36, 2, -31], [-3, -30, -15], [5, 14, 17], [-12, 40, -3], [21, -12, 28], [17, -19, -3], [1, 2, 22], [38, 32, -26], [5, -28, 8], [34, -24, -29], [-17, -7, 22], [32, 33, -23], [-12, -10, 24], [-36, -10, 22], [20, -12, -30], [-7, -12, 36], [-18, 25, -4], [-16, -33, 23], [-5, 23, 32], [-7, -8, 37], [-13, 37, -27], [9, 38, 39], [34, -11, 37], [-19, -2, 29], [-36, -38, -20], [-20, -31, 2], [-15, 32, 12], [-34, -14, -3], [-8, -37, 19], [6, -40, -4], [-32, 35, -2], [-9, 6, 39], [-22, 14, -5], [-32, 21, -7], [11, 26, -32], [14, 32, -20], [-29, -12, 30], [24, 29, -34], [14, 17, 24], [-14, -2, -11], [9, 8, 39], [2, 26, -29], [16, 26, -3], [15, 16, 7], [8, -23, 39], [30, 20, -32], [23, 21, 6], [40, 1, 7], [3, -31, 4], [-31, 22, 23], [-39, 26, 6], [33, -25, -36], [12, 25, -36], [29, -15, -31], [39, 25, -32], [30, -6, -7], [4, -40, -29], [24, -1, -5], [22, 37, -20], [-16, 4, -10], [-8, 15, -19], [27, -33, -39], [30, -12, 40], [-2, 7, 13], [26, 15, -40], [-23, -26, 39], [39, -29, 25], [5, -22, -23], [-24, 28, 5], [4, 22, 16], [11, -14, -40], [-24, 13, -40], [-27, 31, -38], [-12, 7, -2], [-31, 3, 13], [-23, 30, 13], [20, 27, -29], [-19, 25, -24], [31, -34, 35], [-2, -30, 24], [16, -34, 1], [2, -11, -4], [23, 24, 36], [-28, -22, 4], [17, 16, 32], [-28, -3, 11], [-9, 27, 33], [2, -11, -3], [-30, 34, -39], [-19, -12, -5], [27, -23, 29], [34, -10, 37], [-15, 30, -38], [36, -8, -32], [-18, 7, -28], [-29, 13, 20], [26, -21, -4], [-21, 40, 26], [27, 6, 32]]
  asgn = init_map(40)
  return dpll(formula, asgn, 40)
