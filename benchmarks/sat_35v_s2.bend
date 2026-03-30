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


# Generated from: benchmarks/sat_35v_s2.cnf
# Variables: 35, Clauses: 150

def main():
  formula = [[-4, -6, -24], [-20, -17, 14], [-28, -26, 33], [18, -3, -2], [-28, 34, 11], [-21, 12, -9], [-12, -29, -27], [23, -24, -29], [30, -34, -16], [-23, -30, -32], [11, -18, -31], [33, 34, -27], [-5, 22, -1], [-4, -18, -15], [-9, -18, 16], [3, 4, 24], [8, -5, 2], [-9, 11, -12], [16, -10, -3], [8, 19, -22], [-3, -17, 26], [-15, 6, -21], [9, 34, -26], [-22, -17, -27], [4, 17, 3], [-15, 33, 3], [-17, -6, -15], [-17, 28, 18], [-27, 11, 8], [2, 12, -15], [-30, 20, -35], [14, -28, -33], [-34, 12, 7], [-8, -24, 19], [27, -7, -20], [-29, 4, -27], [5, 1, -19], [15, 32, -13], [-9, 23, 26], [-22, 26, -14], [3, 32, -19], [-18, -31, -34], [27, 32, -19], [28, 6, -7], [-27, -5, -6], [3, -9, -19], [-22, 29, -12], [-28, -7, 22], [11, -30, -16], [-10, -30, 29], [12, 26, 33], [-27, 31, -24], [-6, 15, -35], [-1, -21, 30], [12, 7, -2], [25, -14, -7], [-18, 13, -32], [-28, 31, -17], [-5, -23, -1], [5, -32, 22], [-6, -23, -12], [17, 9, 4], [19, 10, 1], [-3, 35, -25], [-32, -9, 31], [17, -21, 20], [-26, 34, -6], [10, 33, 6], [15, 34, -18], [25, 24, 14], [-11, 32, 29], [29, 14, 18], [13, -24, 12], [25, -26, -22], [-21, -26, 19], [20, -26, 31], [31, 6, -12], [7, -23, -11], [28, -1, -35], [-35, 19, 31], [-32, 7, 10], [24, 17, 6], [-3, -22, -24], [12, 5, 28], [8, 22, -26], [-32, -21, -35], [-35, 32, 26], [-34, 29, -3], [8, 33, -12], [-1, 17, 7], [-28, -6, 22], [31, -16, 5], [33, -35, 4], [34, 22, 16], [8, -16, -7], [-25, -22, -26], [-11, 33, -7], [12, 25, 13], [-26, -21, 20], [-19, 34, -32], [7, 2, 13], [-9, 2, 17], [15, 10, 21], [-35, -12, 6], [-19, -14, 11], [-34, -5, 27], [-20, 8, 18], [-17, -35, -26], [-28, 9, 11], [-23, -25, -31], [-29, 13, 31], [-24, -31, -15], [-9, -20, 14], [2, -13, -21], [22, -29, 5], [9, -14, -10], [29, -18, -6], [10, -20, -15], [26, 34, 27], [-16, 9, 26], [26, 31, 25], [-34, 6, -35], [26, 15, 33], [-32, 5, 30], [-31, 3, 9], [-4, 10, -19], [-6, 9, -28], [-18, 31, 4], [7, -24, -23], [-31, 19, 33], [-28, -1, -23], [-5, 35, 33], [12, -11, -3], [23, -12, -19], [-15, 26, -5], [-5, 16, -15], [-6, 33, -18], [-34, 26, 28], [-30, -24, -4], [29, -28, -11], [-10, -2, -17], [17, 29, 31], [-15, -23, 3], [-20, -2, 31], [-30, 24, -34], [35, -11, 30], [-8, -33, -16], [-8, 28, -30], [-25, -29, 24], [15, -12, -27]]
  asgn = init_map(35)
  return dpll(formula, asgn, 35)
