# Bend SAT Solver — CDCL-lite via HVM
#
# An enhanced SAT solver that adds conflict-driven clause learning
# and restarts on top of the parallel DPLL framework.
#
# Key additions over solver.bend:
#   1. Decision trail tracking: each branch records its decisions
#   2. Conflict clause extraction: when both branches fail, the
#      negation of the decision trail becomes a learned clause
#   3. Restart loop: runs DPLL with a budget, collects learned
#      clauses, augments the formula, and restarts
#
# NOTE: Bend's number type (i24/u24) does not support runtime
# negation via (0 - x) for use as DIMACS literals. The negate()
# function is generated per-problem by cnf_to_bend.py using an
# if-else chain with parser-level negative literals.
#
# Data representation (same as solver.bend):
#   Assignment: Map from var_id -> value (0=unset, 1=true, 2=false)
#   Literal: DIMACS encoding (positive = var true, negative = var false)
#   Clause: List of literals
#   Formula: List of clauses
#
# Result type:
#   SolveResult/Sat     { val }     — formula is satisfiable
#   SolveResult/Unsat   { learned } — UNSAT with list of learned clauses
#   SolveResult/Unknown {}          — budget exhausted, restart needed
#
# This file is used as a template. The cnf_to_bend.py converter
# (with --cdcl flag) generates a complete .bend program by appending
# the negate() function and a main() function.

type SolveResult:
  Sat { val }
  Unsat { learned }
  Unknown {}

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

# --- List utilities ---

def concat(a, b):
  match a:
    case List/Nil:
      return b
    case List/Cons:
      return List/Cons(a.head, concat(a.tail, b))

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

# --- Negate decision trail to form a learned clause ---
# Uses the generated negate() function to produce proper
# parser-level negative literals.
# If decisions = [3, -5, 7] (set x3=T, x5=F, x7=T),
# learned clause = [-3, 5, -7] (at least one must differ).

def negate_trail(trail):
  match trail:
    case List/Nil:
      return List/Nil
    case List/Cons:
      neg_lit = negate(trail.head)
      return List/Cons(neg_lit, negate_trail(trail.tail))

# --- Merge learned clauses from two DPLL branches ---

def merge_results(r1, r2, decisions):
  match r1:
    case SolveResult/Sat:
      return r1
    case SolveResult/Unknown:
      match r2:
        case SolveResult/Sat:
          return r2
        case SolveResult/Unknown:
          return SolveResult/Unknown
        case SolveResult/Unsat:
          return SolveResult/Unknown
    case SolveResult/Unsat:
      match r2:
        case SolveResult/Sat:
          return r2
        case SolveResult/Unknown:
          return SolveResult/Unknown
        case SolveResult/Unsat:
          # Both UNSAT: create a conflict clause from decision trail
          conflict_clause = negate_trail(decisions)
          all_learned = concat(r1.learned, r2.learned)
          final_learned = List/Cons(conflict_clause, all_learned)
          return SolveResult/Unsat { learned: final_learned }

# --- DPLL with clause learning and budget ---
#
# decisions: list of decision literals made so far (trail)
# budget: max number of decisions remaining (0 = give up, restart)
#
# Returns SolveResult:
#   Sat { val: 1 }           — satisfiable
#   Unsat { learned: [...] } — unsatisfiable with learned clauses
#   Unknown {}               — budget exhausted

def dpll_cdcl(formula, asgn, num_vars, decisions, budget):
  # Unit propagation
  asgn2 = unit_propagate(asgn, formula, num_vars)
  # Check formula status
  status = eval_formula(asgn2, formula)
  if status == 1:
    return SolveResult/Sat { val: 1 }
  elif status == 2:
    # Conflict: return UNSAT with empty learned list
    return SolveResult/Unsat { learned: [] }
  else:
    if budget == 0:
      return SolveResult/Unknown
    else:
      v = pick_var(asgn2, 1, num_vars)
      if v == 0:
        # All variables assigned but formula not SAT => UNSAT
        return SolveResult/Unsat { learned: [] }
      else:
        # PARALLEL BRANCH: HVM runs both simultaneously
        new_budget = budget - 1
        neg_v = negate(v)
        decisions_t = List/Cons(v, decisions)
        decisions_f = List/Cons(neg_v, decisions)
        asgn_t = asgn2
        asgn_t[v] = 1
        asgn_f = asgn2
        asgn_f[v] = 2
        left = dpll_cdcl(formula, asgn_t, num_vars, decisions_t, new_budget)
        right = dpll_cdcl(formula, asgn_f, num_vars, decisions_f, new_budget)
        return merge_results(left, right, decisions)

# --- Add learned clauses to the formula ---

def add_clauses(formula, clauses):
  match clauses:
    case List/Nil:
      return formula
    case List/Cons:
      new_formula = List/Cons(clauses.head, formula)
      return add_clauses(new_formula, clauses.tail)

# --- Restart loop ---
#
# Runs dpll_cdcl with increasing budgets.
# When budget is exhausted or UNSAT with learned clauses,
# adds learned clauses to formula and restarts.
#
# Budget schedule: starts at initial_budget, doubles each restart.
# max_restarts: safety limit to prevent infinite loops.

def solve_restart(formula, num_vars, budget, restarts_left):
  if restarts_left == 0:
    # Final attempt: run with very large budget (no restart)
    asgn = init_map(num_vars)
    result = dpll_cdcl(formula, asgn, num_vars, [], 9999)
    match result:
      case SolveResult/Sat:
        return 1
      case SolveResult/Unsat:
        return 0
      case SolveResult/Unknown:
        return 0
  else:
    asgn = init_map(num_vars)
    result = dpll_cdcl(formula, asgn, num_vars, [], budget)
    match result:
      case SolveResult/Sat:
        return 1
      case SolveResult/Unsat:
        # Definitive UNSAT within budget. Add learned clauses
        # and try again (learned clauses may help prune on restart).
        new_formula = add_clauses(formula, result.learned)
        return solve_restart(new_formula, num_vars, budget * 2, restarts_left - 1)
      case SolveResult/Unknown:
        # Budget exhausted — restart with doubled budget.
        return solve_restart(formula, num_vars, budget * 2, restarts_left - 1)

# --- Top-level solver ---

def solve_cdcl(formula, num_vars, initial_budget, max_restarts):
  return solve_restart(formula, num_vars, initial_budget, max_restarts)
