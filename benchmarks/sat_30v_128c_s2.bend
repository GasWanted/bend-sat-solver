# Bend SAT Solver — Parallel DPLL via HVM
#
# A SAT solver that exploits HVM's automatic parallelism to explore
# both branches of every variable decision simultaneously.
#
# Data representation:
#   Assignment: List of values, index = var_id (1-based, index 0 unused)
#     0 = unset, 1 = true, 2 = false
#   Literal encoding: var v positive = v*2, var v negative = v*2+1
#   Clause: List of encoded literals
#   Formula: List of clauses
#
# This file is used as a template. The cnf_to_bend.py converter
# generates a complete .bend program by appending a main() function
# that embeds the specific CNF formula.

# --- List-based assignment (duplicable in HVM, unlike Map) ---

def list_get(xs, i):
  match xs:
    case List/Nil:
      return 0
    case List/Cons:
      if i == 0:
        return xs.head
      else:
        return list_get(xs.tail, i - 1)

def list_set(xs, i, v):
  match xs:
    case List/Nil:
      if i == 0:
        return List/Cons { head: v, tail: List/Nil }
      else:
        return List/Cons { head: 0, tail: list_set(List/Nil, i - 1, v) }
    case List/Cons:
      if i == 0:
        return List/Cons { head: v, tail: xs.tail }
      else:
        return List/Cons { head: xs.head, tail: list_set(xs.tail, i - 1, v) }

def zeros(n):
  if n == 0:
    return []
  else:
    return List/Cons { head: 0, tail: zeros(n - 1) }

# --- Literal evaluation ---

def eval_lit(asgn, lit):
  v = lit / 2
  neg = lit % 2
  val = list_get(asgn, v)
  if neg == 0:
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
# Find a clause with exactly one unset literal (all others false).
# Returns the literal to propagate, or 0 if none found.

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

# Apply unit propagation: set the literal's variable to satisfy it
def propagate_lit(asgn, lit):
  v = lit / 2
  neg = lit % 2
  if neg == 0:
    return list_set(asgn, v, 1)
  else:
    return list_set(asgn, v, 2)

# Iterative unit propagation (up to max_steps to prevent infinite loops)
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
    val = list_get(asgn, var)
    if val == 0:
      return var
    else:
      return pick_var(asgn, var + 1, num_vars)

# --- DPLL Solver ---
# The core parallel algorithm.
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
      asgn_t = list_set(asgn2, v, 1)
      asgn_f = list_set(asgn2, v, 2)
      left = dpll(formula, asgn_t, num_vars)
      right = dpll(formula, asgn_f, num_vars)
      if left == 1:
        return 1
      else:
        return right

# Generated from: /home/box/GW/bend-sat-solver/benchmarks/sat_30v_128c_s2.cnf
# Variables: 30, Clauses: 128

def main():
  formula = [[56, 5, 7], [44, 56, 20], [45, 13, 29], [35, 25, 37], [56, 2, 24], [59, 34, 12], [23, 12, 11], [36, 12, 59], [61, 50, 25], [30, 13, 51], [17, 33, 19], [24, 45, 58], [49, 60, 36], [23, 55, 47], [50, 61, 33], [35, 36, 43], [33, 35, 24], [54, 23, 49], [9, 4, 38], [59, 60, 8], [54, 15, 59], [4, 24, 12], [7, 2, 4], [55, 61, 12], [39, 4, 52], [25, 40, 42], [3, 21, 30], [19, 51, 26], [17, 7, 44], [53, 57, 10], [23, 10, 57], [29, 43, 3], [18, 4, 11], [35, 61, 46], [30, 6, 19], [40, 46, 25], [2, 10, 5], [6, 16, 8], [15, 2, 35], [27, 15, 45], [29, 34, 2], [35, 39, 12], [2, 34, 61], [60, 25, 20], [21, 15, 55], [4, 28, 43], [6, 2, 21], [16, 51, 32], [30, 11, 50], [9, 7, 41], [47, 8, 2], [46, 32, 21], [19, 33, 35], [29, 60, 32], [33, 41, 19], [7, 38, 48], [36, 10, 52], [59, 44, 52], [17, 46, 44], [21, 9, 11], [8, 23, 34], [12, 31, 46], [50, 38, 48], [41, 26, 58], [19, 26, 47], [25, 37, 22], [54, 57, 48], [45, 26, 58], [46, 60, 58], [27, 14, 48], [9, 27, 54], [60, 39, 14], [44, 29, 32], [14, 51, 7], [45, 7, 51], [31, 18, 58], [51, 25, 13], [19, 45, 42], [13, 33, 26], [21, 36, 31], [26, 39, 30], [11, 33, 46], [54, 23, 20], [43, 26, 35], [27, 40, 35], [6, 20, 4], [18, 5, 8], [24, 14, 22], [32, 31, 57], [31, 42, 14], [17, 33, 14], [10, 53, 16], [52, 55, 49], [35, 38, 46], [47, 57, 61], [37, 40, 42], [12, 18, 59], [12, 22, 26], [25, 7, 61], [2, 37, 22], [21, 32, 42], [33, 8, 10], [24, 18, 6], [41, 5, 23], [57, 10, 13], [11, 22, 35], [46, 40, 27], [32, 41, 57], [39, 34, 36], [46, 31, 12], [8, 31, 39], [60, 12, 7], [18, 8, 44], [45, 7, 22], [58, 32, 16], [46, 34, 37], [55, 35, 22], [33, 2, 10], [52, 4, 41], [57, 27, 59], [44, 13, 35], [14, 12, 26], [11, 27, 23], [33, 18, 20], [29, 47, 10], [36, 50, 14], [11, 43, 2], [5, 48, 50]]
  asgn = zeros(31)
  return dpll(formula, asgn, 30)
