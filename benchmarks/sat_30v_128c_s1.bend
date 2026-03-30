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

# Generated from: /home/box/GW/bend-sat-solver/benchmarks/sat_30v_128c_s1.cnf
# Variables: 30, Clauses: 128

def main():
  formula = [[11, 38, 56], [51, 31, 32], [2, 59, 55], [47, 30, 19], [58, 23, 2], [58, 26, 44], [17, 51, 30], [44, 16, 50], [55, 60, 37], [48, 56, 21], [47, 35, 61], [15, 20, 39], [26, 38, 57], [28, 45, 13], [48, 25, 7], [34, 55, 26], [21, 47, 56], [13, 35, 17], [56, 36, 17], [24, 31, 61], [3, 27, 53], [35, 53, 10], [4, 33, 57], [28, 32, 55], [40, 52, 22], [12, 36, 39], [56, 55, 61], [6, 57, 2], [19, 8, 52], [13, 19, 35], [20, 30, 46], [27, 22, 28], [49, 34, 15], [16, 3, 26], [46, 35, 45], [43, 52, 47], [27, 45, 38], [49, 21, 10], [57, 6, 20], [38, 19, 10], [55, 14, 59], [51, 46, 40], [15, 39, 44], [45, 26, 21], [26, 58, 20], [38, 52, 11], [55, 27, 61], [37, 32, 51], [6, 11, 12], [23, 40, 34], [21, 17, 57], [33, 10, 38], [7, 26, 56], [9, 40, 39], [17, 38, 6], [36, 60, 9], [55, 20, 2], [54, 58, 53], [28, 13, 8], [57, 8, 29], [61, 55, 20], [14, 42, 23], [20, 48, 40], [7, 61, 22], [15, 53, 41], [32, 45, 24], [17, 24, 7], [7, 43, 38], [20, 5, 23], [60, 21, 17], [40, 7, 16], [18, 36, 57], [20, 50, 53], [9, 34, 51], [13, 51, 10], [9, 47, 34], [15, 10, 36], [59, 41, 53], [46, 15, 12], [56, 44, 17], [52, 28, 37], [2, 26, 54], [43, 60, 29], [39, 10, 19], [12, 40, 7], [35, 59, 43], [17, 23, 33], [23, 37, 40], [43, 17, 5], [25, 13, 34], [47, 20, 57], [31, 41, 7], [38, 26, 13], [48, 51, 53], [25, 27, 35], [34, 6, 53], [7, 11, 51], [7, 31, 56], [52, 59, 28], [41, 60, 33], [29, 60, 8], [37, 3, 14], [40, 16, 54], [15, 18, 21], [53, 56, 13], [51, 14, 39], [58, 53, 3], [45, 50, 49], [38, 53, 21], [22, 2, 8], [27, 23, 52], [61, 27, 15], [49, 58, 55], [40, 55, 35], [20, 47, 12], [34, 2, 44], [57, 41, 39], [6, 33, 48], [3, 29, 49], [52, 18, 57], [2, 25, 61], [36, 20, 10], [35, 5, 18], [24, 6, 45], [12, 47, 7], [15, 34, 16], [55, 60, 35], [5, 13, 21]]
  asgn = zeros(31)
  return dpll(formula, asgn, 30)
