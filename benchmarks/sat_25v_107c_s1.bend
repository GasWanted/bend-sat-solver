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

# Generated from: /home/box/GW/bend-sat-solver/benchmarks/sat_25v_107c_s1.cnf
# Variables: 25, Clauses: 107

def main():
  formula = [[10, 38, 51], [33, 42, 26], [27, 28, 40], [49, 17, 38], [2, 43, 37], [29, 49, 3], [36, 16, 24], [21, 3, 29], [13, 42, 48], [49, 46, 35], [44, 15, 20], [35, 26, 39], [26, 29, 45], [44, 49, 24], [12, 35, 26], [21, 46, 40], [35, 17, 3], [16, 27, 34], [19, 45, 36], [49, 35, 10], [5, 32, 25], [32, 25, 29], [41, 23, 31], [37, 39, 13], [18, 5, 44], [50, 19, 16], [20, 7, 12], [18, 43, 46], [8, 2, 20], [9, 18, 49], [2, 17, 26], [46, 35, 45], [42, 47, 34], [45, 38, 23], [10, 15, 4], [20, 48, 12], [5, 39, 14], [51, 46, 40], [15, 39, 44], [45, 26, 21], [26, 21, 3], [38, 10, 22], [27, 37, 25], [50, 36, 16], [12, 36, 15], [18, 24, 23], [41, 50, 47], [8, 22, 5], [11, 23, 8], [39, 37, 16], [21, 38, 36], [5, 20, 2], [5, 15, 16], [30, 13, 44], [27, 37, 20], [14, 42, 23], [20, 48, 40], [7, 22, 40], [41, 50, 36], [12, 36, 14], [18, 7, 51], [16, 26, 21], [38, 21, 17], [40, 7, 16], [19, 36, 6], [50, 25, 32], [51, 23, 6], [10, 23, 21], [20, 11, 14], [23, 41, 45], [46, 15, 12], [45, 17, 18], [29, 37, 18], [26, 22, 13], [28, 38, 2], [11, 18, 26], [33, 3, 13], [31, 44, 42], [32, 17, 47], [42, 18, 17], [25, 13, 34], [46, 21, 37], [41, 7, 9], [12, 11, 19], [4, 33, 44], [13, 37, 48], [18, 43, 9], [11, 51, 41], [31, 17, 26], [23, 30, 10], [28, 40, 36], [17, 27, 49], [39, 2, 42], [13, 20, 11], [19, 45, 31], [36, 24, 32], [27, 15, 20], [39, 49, 3], [43, 11, 6], [35, 44, 24], [46, 30, 25], [44, 39, 32], [37, 3, 19], [49, 34, 15], [29, 48, 46], [40, 45, 35], [38, 29, 27]]
  asgn = zeros(26)
  return dpll(formula, asgn, 25)
