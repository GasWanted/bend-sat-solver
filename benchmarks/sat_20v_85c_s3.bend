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

# Generated from: /home/box/GW/bend-sat-solver/benchmarks/sat_20v_85c_s3.cnf
# Variables: 20, Clauses: 85

def main():
  formula = [[16, 39, 36], [39, 6, 3], [15, 32, 37], [11, 17, 41], [6, 12, 5], [32, 27, 28], [10, 24, 8], [29, 20, 40], [39, 29, 17], [19, 13, 23], [14, 38, 19], [33, 6, 24], [21, 28, 39], [5, 27, 22], [16, 4, 21], [15, 28, 20], [23, 41, 24], [31, 35, 27], [40, 35, 18], [21, 29, 18], [28, 39, 23], [4, 23, 31], [19, 33, 2], [24, 19, 30], [13, 22, 25], [8, 2, 11], [17, 23, 12], [41, 22, 39], [13, 6, 23], [18, 17, 8], [38, 13, 18], [40, 25, 11], [30, 25, 28], [28, 11, 15], [35, 29, 36], [31, 35, 21], [39, 20, 9], [35, 14, 29], [12, 34, 21], [4, 9, 23], [4, 25, 17], [13, 17, 19], [2, 32, 26], [34, 40, 29], [4, 10, 41], [6, 34, 38], [26, 40, 20], [8, 11, 37], [38, 13, 5], [26, 5, 29], [22, 28, 39], [38, 6, 28], [23, 24, 36], [9, 35, 27], [8, 38, 2], [35, 6, 9], [23, 9, 3], [21, 38, 41], [34, 41, 17], [5, 36, 22], [13, 17, 30], [25, 27, 40], [16, 29, 13], [35, 33, 10], [9, 33, 38], [13, 10, 19], [17, 37, 21], [39, 40, 18], [27, 14, 12], [11, 28, 33], [37, 2, 33], [5, 31, 17], [6, 14, 18], [12, 4, 18], [6, 41, 8], [24, 30, 22], [33, 7, 14], [10, 36, 23], [9, 30, 35], [24, 41, 31], [19, 9, 22], [32, 34, 25], [12, 11, 40], [9, 37, 11], [29, 36, 20]]
  asgn = zeros(21)
  return dpll(formula, asgn, 20)
