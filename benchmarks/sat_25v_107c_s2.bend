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

# Generated from: /home/box/GW/bend-sat-solver/benchmarks/sat_25v_107c_s2.cnf
# Variables: 25, Clauses: 107

def main():
  formula = [[5, 7, 25], [20, 18, 41], [29, 43, 27], [25, 37, 31], [25, 30, 23], [12, 36, 16], [35, 25, 44], [29, 49, 35], [25, 30, 13], [42, 35, 17], [25, 44, 31], [36, 48, 30], [46, 13, 40], [47, 35, 37], [20, 48, 15], [6, 23, 49], [9, 4, 38], [8, 50, 35], [5, 28, 46], [16, 45, 2], [48, 3, 24], [12, 35, 47], [16, 11, 5], [48, 8, 20], [50, 40, 48], [40, 46, 11], [22, 9, 2], [38, 50, 27], [23, 19, 41], [10, 44, 4], [31, 43, 17], [16, 46, 30], [40, 46, 25], [2, 10, 5], [6, 16, 8], [15, 2, 35], [27, 15, 45], [29, 34, 2], [35, 39, 12], [3, 34, 9], [25, 20, 2], [15, 51, 44], [42, 33, 30], [20, 3, 24], [33, 14, 8], [51, 24, 26], [40, 22, 42], [41, 45, 32], [25, 30, 11], [33, 49, 28], [17, 13, 33], [47, 7, 38], [13, 37, 11], [44, 42, 4], [44, 22, 30], [50, 28, 9], [12, 31, 46], [50, 38, 48], [40, 27, 48], [27, 18, 47], [25, 37, 22], [49, 16, 37], [42, 3, 23], [42, 13, 9], [41, 26, 15], [51, 15, 18], [41, 10, 2], [39, 13, 31], [25, 3, 32], [39, 32, 45], [31, 2, 7], [27, 19, 45], [4, 12, 32], [2, 20, 36], [26, 39, 30], [11, 33, 46], [23, 20, 43], [34, 7, 43], [10, 34, 43], [36, 17, 34], [26, 24, 14], [13, 32, 30], [46, 30, 42], [17, 33, 14], [11, 17, 18], [49, 23, 19], [47, 49, 23], [42, 51, 47], [24, 20, 27], [31, 32, 7], [10, 2, 9], [48, 51, 42], [40, 27, 36], [22, 14, 32], [18, 10, 28], [47, 16, 48], [51, 40, 4], [30, 51, 19], [23, 43, 50], [4, 27, 50], [41, 7, 38], [26, 46, 30], [8, 31, 39], [12, 7, 26], [8, 44, 24], [6, 23, 42], [7, 32, 11]]
  asgn = zeros(26)
  return dpll(formula, asgn, 25)
