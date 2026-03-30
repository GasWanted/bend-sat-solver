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

# Generated from: /home/box/GW/bend-sat-solver/benchmarks/sat_20v_85c_s1.cnf
# Variables: 20, Clauses: 85

def main():
  formula = [[10, 38, 6], [26, 15, 8], [40, 3, 31], [8, 23, 2], [27, 15, 29], [32, 37, 17], [21, 3, 29], [13, 21, 9], [35, 29, 40], [38, 33, 34], [26, 29, 13], [25, 6, 30], [27, 24, 32], [41, 38, 26], [3, 15, 36], [24, 38, 41], [3, 27, 35], [29, 5, 32], [35, 28, 32], [37, 23, 31], [37, 39, 13], [18, 4, 6], [18, 17, 40], [6, 13, 39], [20, 30, 22], [22, 28, 15], [14, 28, 2], [13, 31, 34], [35, 30, 17], [23, 28, 4], [5, 20, 7], [12, 29, 19], [38, 15, 31], [40, 34, 4], [28, 39, 14], [34, 33, 3], [3, 13, 15], [10, 23, 29], [36, 25, 40], [4, 7, 10], [22, 34, 18], [41, 33, 10], [29, 7, 27], [22, 9, 27], [19, 25, 20], [19, 8, 5], [7, 29, 8], [38, 28, 12], [9, 29, 27], [36, 18, 32], [3, 40, 20], [27, 7, 39], [9, 19, 15], [32, 24, 18], [24, 7, 18], [38, 22, 16], [22, 38, 21], [40, 7, 16], [19, 36, 6], [25, 32, 39], [23, 6, 35], [10, 23, 21], [20, 11, 14], [22, 36, 14], [17, 18, 6], [19, 36, 30], [22, 13, 19], [39, 3, 5], [10, 18, 39], [16, 32, 3], [30, 17, 39], [29, 23, 37], [17, 5, 6], [34, 14, 21], [13, 31, 7], [38, 26, 13], [5, 32, 27], [13, 36, 4], [9, 18, 7], [7, 30, 17], [29, 26, 13], [32, 15, 9], [20, 19, 17], [34, 31, 2], [18, 15, 12]]
  asgn = zeros(21)
  return dpll(formula, asgn, 20)
