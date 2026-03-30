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

# Generated from: /home/box/GW/bend-sat-solver/benchmarks/sat_15v_64c_s2.cnf
# Variables: 15, Clauses: 64

def main():
  formula = [[28, 30, 2], [26, 22, 10], [23, 7, 15], [19, 13, 31], [28, 2, 12], [31, 18, 6], [13, 6, 29], [19, 7, 17], [27, 12, 31], [16, 7, 27], [9, 17, 11], [13, 22, 17], [30, 19, 25], [29, 25, 7], [17, 11, 29], [19, 30, 23], [17, 19, 12], [28, 13, 25], [5, 2, 20], [31, 5, 26], [9, 3, 14], [13, 6, 9], [3, 30, 24], [30, 7, 24], [2, 26, 8], [21, 22, 24], [11, 17, 19], [27, 14, 20], [23, 30, 13], [7, 18, 20], [28, 13, 11], [25, 18, 6], [7, 5, 17], [30, 2, 8], [21, 9, 30], [23, 14, 10], [15, 6, 4], [2, 6, 27], [17, 30, 11], [27, 8, 24], [21, 3, 15], [22, 27, 17], [21, 13, 10], [28, 22, 15], [23, 28, 3], [17, 8, 20], [10, 24, 4], [12, 15, 24], [4, 11, 30], [14, 9, 24], [2, 24, 28], [26, 13, 11], [25, 27, 14], [9, 7, 17], [25, 5, 20], [7, 19, 31], [31, 22, 26], [9, 24, 22], [11, 5, 7], [4, 13, 18], [6, 17, 24], [26, 20, 24], [20, 15, 24], [15, 10, 25]]
  asgn = zeros(16)
  return dpll(formula, asgn, 15)
