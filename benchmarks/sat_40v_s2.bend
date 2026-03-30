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


# Generated from: benchmarks/sat_40v_s2.cnf
# Variables: 40, Clauses: 172

def main():
  formula = [[-4, -6, -24], [20, 17, -39], [-28, -26, 33], [18, -3, -2], [-28, 34, 11], [-21, 12, -9], [-36, -12, -29], [24, -38, 23], [26, 30, 34], [-33, 23, -30], [-36, -30, -32], [-11, 40, 18], [-33, -36, 34], [14, -32, -33], [-22, 1, -13], [4, -18, 38], [34, 9, -18], [28, 3, -4], [6, -8, 5], [-17, -9, 11], [38, 3, 16], [40, 8, 19], [-39, -3, -17], [-31, 15, 6], [-29, 9, -34], [10, -22, -17], [36, 9, 4], [-30, -15, 33], [16, 15, 29], [-40, 24, -17], [10, 3, -25], [16, 7, 2], [-34, 30, -20], [14, -28, -33], [-34, -38, 12], [-2, 34, -8], [-24, 20, 2], [13, -2, 29], [38, 40, 5], [5, -15, 32], [30, 9, 23], [-6, -40, -22], [-2, -40, 31], [-23, 30, -10], [-31, 27, 32], [-32, -39, -17], [6, 38, -37], [-10, -27, -5], [3, -9, -19], [-22, 29, -12], [-28, -7, 22], [11, -30, -16], [37, 10, -30], [12, 26, 33], [-27, 31, -24], [-6, 15, -35], [-1, -21, 30], [12, 7, -2], [25, -14, -7], [18, -38, 13], [-28, 31, -17], [-5, -23, -1], [-5, -38, 32], [-33, -30, 2], [26, 17, -9], [19, 10, 1], [-3, 35, -25], [-32, -9, 31], [17, -21, 20], [-26, 34, -6], [10, 33, 6], [15, 34, -18], [25, 24, 14], [-11, 32, 29], [29, 14, 18], [13, -24, 12], [-36, -25, 26], [-39, -33, -38], [-19, 35, 40], [-31, 12, 17], [12, 21, 25], [23, 5, -28], [39, -25, 35], [21, 13, 32], [17, 10, 27], [16, 40, -3], [-4, 10, -12], [-9, 21, -34], [-40, 26, 15], [-40, -21, -35], [-35, 32, 26], [-34, 29, -3], [8, 33, -12], [-1, 17, 7], [-28, -6, 22], [31, -16, 5], [33, -35, 4], [34, 22, 16], [8, -16, -7], [-25, 22, -40], [-34, -33, 11], [14, 12, 25], [-9, -26, -21], [-31, 18, 19], [-27, 9, -36], [-13, -14, -26], [17, -31, -35], [10, 39, 21], [-35, -12, 6], [-19, -14, 11], [34, 37, -5], [-30, -20, -8], [2, -14, 27], [-34, -13, -28], [29, -30, -23], [38, 31, -29], [20, -5, 11], [-40, 37, 9], [-20, 7, -1], [4, -21, 35], [29, -5, 27], [37, -9, 14], [-5, -38, 29], [16, -10, -37], [-13, -40, -22], [16, -14, 36], [40, 26, 28], [25, 19, -14], [-6, 39, -35], [26, 15, 33], [-32, -38, 5], [2, 31, 3], [35, 4, -40], [-36, 35, -6], [-3, 20, -33], [-23, 22, -7], [-24, -18, -31], [2, -3, 22], [-35, -4, -5], [-28, 27, 16], [38, -23, 12], [16, -37, 15], [39, 5, 16], [-26, -6, 33], [-34, 26, 28], [-30, -24, -4], [-29, -28, -39], [-11, -32, 39], [-17, -12, 10], [29, 31, -30], [-23, 3, 26], [-2, -36, 31], [-30, 24, -34], [36, -35, -11], [-27, 8, -33], [-25, -8, 28], [-25, -29, -40], [36, -23, -11], [-27, -29, 32], [-17, 21, -37], [17, 21, 1], [8, 1, 24], [-21, 6, -34], [29, 7, 39], [4, -1, -22], [1, -31, 37], [-22, -20, 26], [18, 6, 33], [-24, -12, -16], [14, -38, -30], [33, 11, 1], [-12, -13, -39]]
  asgn = init_map(40)
  return dpll(formula, asgn, 40)
