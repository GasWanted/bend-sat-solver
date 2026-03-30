// CDCL SAT Solver with:
// - Two-watched-literal unit propagation
// - 1-UIP conflict analysis
// - Non-chronological backtracking
// - VSIDS variable selection
// - Luby sequence restarts
// - Clause deletion with LBD

use std::env;
use std::fs;
use std::process;
use std::time::Instant;

// ---------------------------------------------------------------------------
// Literal / Variable helpers
// ---------------------------------------------------------------------------

/// A literal is stored as a `u32`.  Variable `v` (1-based) is encoded as:
///   positive literal  v  -> 2*(v-1)
///   negative literal -v  -> 2*(v-1) + 1
type Lit = u32;
type Var = u32;

const LIT_UNDEF: Lit = u32::MAX;

#[inline(always)]
fn lit_from_dimacs(d: i32) -> Lit {
    debug_assert!(d != 0);
    if d > 0 {
        2 * (d as u32 - 1)
    } else {
        2 * ((-d) as u32 - 1) + 1
    }
}

#[inline(always)]
fn lit_neg(l: Lit) -> Lit {
    l ^ 1
}

#[inline(always)]
fn lit_var(l: Lit) -> Var {
    l >> 1
}

#[inline(always)]
fn lit_sign(l: Lit) -> bool {
    (l & 1) == 0
}

#[allow(dead_code)]
fn lit_to_dimacs(l: Lit) -> i32 {
    let v = (lit_var(l) + 1) as i32;
    if lit_sign(l) { v } else { -v }
}

// ---------------------------------------------------------------------------
// Value helpers - inlined to avoid borrow issues
// ---------------------------------------------------------------------------

const LBOOL_UNDEF: u8 = 2;
const LBOOL_TRUE: u8 = 1;
const LBOOL_FALSE: u8 = 0;

#[inline(always)]
fn eval_lit(assigns: &[u8], l: Lit) -> u8 {
    let v = assigns[lit_var(l) as usize];
    if v == LBOOL_UNDEF {
        LBOOL_UNDEF
    } else if lit_sign(l) {
        v
    } else {
        v ^ 1
    }
}

// ---------------------------------------------------------------------------
// Clause
// ---------------------------------------------------------------------------

struct Clause {
    lits: Vec<Lit>,
    learnt: bool,
    lbd: u32,
    activity: f64,
}

// ---------------------------------------------------------------------------
// Solver
// ---------------------------------------------------------------------------

struct Solver {
    num_vars: u32,
    num_original_clauses: usize,

    clauses: Vec<Clause>,

    // Watch lists: for each literal, a list of (clause_ref, blocker_lit)
    watches: Vec<Vec<(usize, Lit)>>,

    // Assignment
    assigns: Vec<u8>,       // indexed by Var
    level: Vec<u32>,        // decision level for each var
    reason: Vec<u32>,       // clause index that implied this var (u32::MAX = decision/unassigned)

    // Trail
    trail: Vec<Lit>,
    trail_lim: Vec<usize>,

    // Propagation pointer
    qhead: usize,

    // VSIDS
    activity: Vec<f64>,
    var_inc: f64,
    var_decay: f64,
    heap: Vec<Var>,
    heap_pos: Vec<u32>, // u32::MAX = not in heap

    // Clause activity
    cla_inc: f64,
    cla_decay: f64,

    // Restart
    luby_restart_base: f64,
    restart_count: u64,

    // Learned clause limits
    max_learnt: usize,
    learnt_adj_start: f64,
    learnt_adj_inc: f64,
    learnt_adj_cnt: f64,

    // Stats
    conflicts: u64,
    decisions: u64,
    propagations: u64,

    // Temporary
    seen: Vec<bool>,
    analyze_toclear: Vec<Var>,
}

const REASON_UNDEF: u32 = u32::MAX;

impl Solver {
    fn new(num_vars: u32) -> Self {
        let nv = num_vars as usize;
        let nl = 2 * nv;
        Solver {
            num_vars,
            num_original_clauses: 0,
            clauses: Vec::new(),
            watches: vec![Vec::new(); nl],
            assigns: vec![LBOOL_UNDEF; nv],
            level: vec![0; nv],
            reason: vec![REASON_UNDEF; nv],
            trail: Vec::with_capacity(nv),
            trail_lim: Vec::new(),
            qhead: 0,
            activity: vec![0.0; nv],
            var_inc: 1.0,
            var_decay: 0.95,
            heap: Vec::new(),
            heap_pos: vec![u32::MAX; nv],
            cla_inc: 1.0,
            cla_decay: 0.999,
            luby_restart_base: 100.0,
            restart_count: 0,
            max_learnt: 0,
            learnt_adj_start: 100.0,
            learnt_adj_inc: 1.5,
            learnt_adj_cnt: 0.0,
            conflicts: 0,
            decisions: 0,
            propagations: 0,
            seen: vec![false; nv],
            analyze_toclear: Vec::new(),
        }
    }

    // -----------------------------------------------------------------------
    // Heap (max-heap on activity)
    // -----------------------------------------------------------------------

    fn heap_sift_up(&mut self, mut i: usize) {
        let x = self.heap[i];
        while i > 0 {
            let p = (i - 1) / 2;
            if self.activity[x as usize] <= self.activity[self.heap[p] as usize] {
                break;
            }
            self.heap[i] = self.heap[p];
            self.heap_pos[self.heap[p] as usize] = i as u32;
            i = p;
        }
        self.heap[i] = x;
        self.heap_pos[x as usize] = i as u32;
    }

    fn heap_sift_down(&mut self, mut i: usize) {
        let x = self.heap[i];
        let n = self.heap.len();
        loop {
            let l = 2 * i + 1;
            if l >= n { break; }
            let r = l + 1;
            let child = if r < n && self.activity[self.heap[r] as usize] > self.activity[self.heap[l] as usize] { r } else { l };
            if self.activity[self.heap[child] as usize] <= self.activity[x as usize] {
                break;
            }
            self.heap[i] = self.heap[child];
            self.heap_pos[self.heap[child] as usize] = i as u32;
            i = child;
        }
        self.heap[i] = x;
        self.heap_pos[x as usize] = i as u32;
    }

    fn heap_insert(&mut self, v: Var) {
        if self.heap_pos[v as usize] != u32::MAX { return; }
        let i = self.heap.len();
        self.heap.push(v);
        self.heap_pos[v as usize] = i as u32;
        self.heap_sift_up(i);
    }

    fn heap_remove_top(&mut self) -> Option<Var> {
        if self.heap.is_empty() { return None; }
        let x = self.heap[0];
        self.heap_pos[x as usize] = u32::MAX;
        let last = self.heap.len() - 1;
        if last > 0 {
            self.heap[0] = self.heap[last];
            self.heap_pos[self.heap[0] as usize] = 0;
            self.heap.pop();
            self.heap_sift_down(0);
        } else {
            self.heap.pop();
        }
        Some(x)
    }

    fn heap_update(&mut self, v: Var) {
        let pos = self.heap_pos[v as usize];
        if pos != u32::MAX {
            self.heap_sift_up(pos as usize);
        }
    }

    // -----------------------------------------------------------------------
    // Inline helpers
    // -----------------------------------------------------------------------

    #[inline(always)]
    fn decision_level(&self) -> u32 {
        self.trail_lim.len() as u32
    }

    fn enqueue(&mut self, lit: Lit, reason: u32) {
        let var = lit_var(lit);
        debug_assert!(self.assigns[var as usize] == LBOOL_UNDEF);
        self.assigns[var as usize] = if lit_sign(lit) { LBOOL_TRUE } else { LBOOL_FALSE };
        self.level[var as usize] = self.decision_level();
        self.reason[var as usize] = reason;
        self.trail.push(lit);
    }

    // -----------------------------------------------------------------------
    // Add clause
    // -----------------------------------------------------------------------

    fn add_clause(&mut self, mut lits: Vec<Lit>, learnt: bool) -> Option<usize> {
        if !learnt {
            lits.sort();
            lits.dedup();
            // Check tautology
            for i in 0..lits.len().saturating_sub(1) {
                if lits[i] == lit_neg(lits[i + 1]) {
                    return None;
                }
            }
            // Remove false lits at level 0, check satisfied
            lits.retain(|&l| eval_lit(&self.assigns, l) != LBOOL_FALSE);
            for &l in &lits {
                if eval_lit(&self.assigns, l) == LBOOL_TRUE {
                    return None;
                }
            }
        }

        if lits.is_empty() { return None; }

        if lits.len() == 1 {
            if eval_lit(&self.assigns, lits[0]) == LBOOL_UNDEF {
                self.enqueue(lits[0], REASON_UNDEF);
            }
            return None;
        }

        let lbd = if learnt { self.compute_lbd(&lits) } else { lits.len() as u32 };

        let cr = self.clauses.len();
        let l0 = lits[0];
        let l1 = lits[1];
        self.clauses.push(Clause { lits, learnt, lbd, activity: 0.0 });
        // watches[~l] = clauses to check when l becomes false (i.e., ~l becomes true)
        self.watches[lit_neg(l0) as usize].push((cr, l1));
        self.watches[lit_neg(l1) as usize].push((cr, l0));

        Some(cr)
    }

    fn compute_lbd(&self, lits: &[Lit]) -> u32 {
        let mut levels: Vec<u32> = lits.iter().map(|&l| self.level[lit_var(l) as usize]).collect();
        levels.sort_unstable();
        levels.dedup();
        levels.len() as u32
    }

    // -----------------------------------------------------------------------
    // Two-watched-literal propagation
    // -----------------------------------------------------------------------

    fn propagate(&mut self) -> Option<usize> {
        let mut conflict: Option<usize> = None;

        while self.qhead < self.trail.len() {
            let p = self.trail[self.qhead];
            self.qhead += 1;
            self.propagations += 1;

            // p just became true; ~p just became false.
            // watches[p] = clauses that have ~p as a watched literal (need checking).
            let false_lit = lit_neg(p); // the literal that just became false

            let mut wl = std::mem::take(&mut self.watches[p as usize]);

            let mut i = 0;
            let mut j = 0;
            let len = wl.len();

            while i < len {
                let (cr, blocker) = wl[i];

                // Quick check: blocker still true?
                if eval_lit(&self.assigns, blocker) == LBOOL_TRUE {
                    wl[j] = wl[i]; j += 1; i += 1;
                    continue;
                }

                // Ensure lits[0] is NOT the false literal
                {
                    let cl = &mut self.clauses[cr].lits;
                    if cl[0] == false_lit {
                        cl.swap(0, 1);
                    }
                }

                let first = self.clauses[cr].lits[0];

                // If the other watched lit is true, satisfied
                if eval_lit(&self.assigns, first) == LBOOL_TRUE {
                    wl[j] = (cr, first); j += 1; i += 1;
                    continue;
                }

                // Search for a replacement watch
                let clen = self.clauses[cr].lits.len();
                let mut found = false;
                for k in 2..clen {
                    let lk = self.clauses[cr].lits[k];
                    if eval_lit(&self.assigns, lk) != LBOOL_FALSE {
                        // Found replacement
                        self.clauses[cr].lits.swap(1, k);
                        let new_watch = self.clauses[cr].lits[1];
                        let first_lit = self.clauses[cr].lits[0];
                        self.watches[lit_neg(new_watch) as usize].push((cr, first_lit));
                        found = true;
                        break;
                    }
                }

                if found {
                    i += 1;
                    continue;
                }

                // No replacement: clause is unit or conflicting
                let first = self.clauses[cr].lits[0];
                wl[j] = (cr, first); j += 1;

                let val = eval_lit(&self.assigns, first);
                if val == LBOOL_FALSE {
                    // Conflict
                    conflict = Some(cr);
                    // Copy remaining watches
                    while i + 1 < len {
                        i += 1;
                        wl[j] = wl[i]; j += 1;
                    }
                    i += 1;
                } else if val == LBOOL_UNDEF {
                    self.enqueue(first, cr as u32);
                    i += 1;
                } else {
                    i += 1;
                }
            }

            wl.truncate(j);
            self.watches[p as usize] = wl;

            if conflict.is_some() {
                return conflict;
            }
        }

        None
    }

    // -----------------------------------------------------------------------
    // Conflict analysis (1-UIP)
    // -----------------------------------------------------------------------

    fn analyze(&mut self, conflict_clause: usize) -> (Vec<Lit>, u32) {
        let mut learnt: Vec<Lit> = Vec::new();
        let cur_level = self.decision_level();
        let mut counter: i32 = 0;
        let mut p: Lit = LIT_UNDEF;
        let mut reason_cr = conflict_clause;
        let mut trail_idx = self.trail.len();

        learnt.push(0); // placeholder for UIP
        self.analyze_toclear.clear();

        loop {
            // Bump clause activity
            if self.clauses[reason_cr].learnt {
                self.clauses[reason_cr].activity += self.cla_inc;
                if self.clauses[reason_cr].activity > 1e20 {
                    for c in self.clauses.iter_mut() {
                        if c.learnt { c.activity *= 1e-20; }
                    }
                    self.cla_inc *= 1e-20;
                }
            }

            let start = if p == LIT_UNDEF { 0 } else { 1 };
            // Copy lits to avoid borrow issues
            let lits: Vec<Lit> = self.clauses[reason_cr].lits[start..].to_vec();

            for &lit in &lits {
                let var = lit_var(lit) as usize;
                if !self.seen[var] && self.level[var] > 0 {
                    self.seen[var] = true;
                    // Bump variable activity
                    self.activity[var] += self.var_inc;
                    if self.activity[var] > 1e100 {
                        for a in self.activity.iter_mut() { *a *= 1e-100; }
                        self.var_inc *= 1e-100;
                    }
                    self.heap_update(var as Var);

                    if self.level[var] >= cur_level {
                        counter += 1;
                    } else {
                        learnt.push(lit);
                    }
                    self.analyze_toclear.push(var as Var);
                }
            }

            // Walk back on trail to find next seen literal at current level
            loop {
                trail_idx -= 1;
                let tl = self.trail[trail_idx];
                if self.seen[lit_var(tl) as usize] {
                    p = tl;
                    break;
                }
            }

            counter -= 1;
            if counter == 0 { break; }

            reason_cr = self.reason[lit_var(p) as usize] as usize;
        }

        learnt[0] = lit_neg(p);

        // Clause minimization
        self.minimize_clause(&mut learnt);

        // Find backtrack level
        let btlevel = if learnt.len() == 1 {
            0
        } else {
            let mut max_i = 1;
            for i in 2..learnt.len() {
                if self.level[lit_var(learnt[i]) as usize] > self.level[lit_var(learnt[max_i]) as usize] {
                    max_i = i;
                }
            }
            learnt.swap(1, max_i);
            self.level[lit_var(learnt[1]) as usize]
        };

        // Clear seen
        for &v in &self.analyze_toclear {
            self.seen[v as usize] = false;
        }

        (learnt, btlevel)
    }

    fn minimize_clause(&mut self, learnt: &mut Vec<Lit>) {
        let mut j = 1;
        for i in 1..learnt.len() {
            let var = lit_var(learnt[i]) as usize;
            if self.reason[var] == REASON_UNDEF {
                learnt[j] = learnt[i]; j += 1;
            } else {
                let cr = self.reason[var] as usize;
                let reason_lits: Vec<Lit> = self.clauses[cr].lits.clone();
                let mut dominated = true;
                for k in 1..reason_lits.len() {
                    let rv = lit_var(reason_lits[k]) as usize;
                    if !self.seen[rv] && self.level[rv] > 0 {
                        dominated = false;
                        break;
                    }
                }
                if !dominated {
                    learnt[j] = learnt[i]; j += 1;
                }
            }
        }
        learnt.truncate(j);
    }

    // -----------------------------------------------------------------------
    // VSIDS decay
    // -----------------------------------------------------------------------

    fn decay_var_activity(&mut self) {
        self.var_inc /= self.var_decay;
    }

    fn decay_clause_activity(&mut self) {
        self.cla_inc /= self.cla_decay;
    }

    // -----------------------------------------------------------------------
    // Pick branching variable
    // -----------------------------------------------------------------------

    fn pick_branch_var(&mut self) -> Option<Var> {
        loop {
            match self.heap_remove_top() {
                None => return None,
                Some(v) => {
                    if self.assigns[v as usize] == LBOOL_UNDEF {
                        return Some(v);
                    }
                }
            }
        }
    }

    // -----------------------------------------------------------------------
    // Backtrack
    // -----------------------------------------------------------------------

    fn cancel_until(&mut self, level: u32) {
        if self.decision_level() <= level { return; }
        let limit = self.trail_lim[level as usize];
        for i in (limit..self.trail.len()).rev() {
            let var = lit_var(self.trail[i]);
            self.assigns[var as usize] = LBOOL_UNDEF;
            self.reason[var as usize] = REASON_UNDEF;
            self.heap_insert(var);
        }
        self.trail.truncate(limit);
        self.trail_lim.truncate(level as usize);
        self.qhead = self.trail.len();
    }

    // -----------------------------------------------------------------------
    // Luby sequence
    // -----------------------------------------------------------------------

    fn luby(y: f64, mut x: u64) -> f64 {
        let mut size: u64 = 1;
        let mut seq: u64 = 0;
        while size < x + 1 {
            seq += 1;
            size = 2 * size + 1;
        }
        while size - 1 != x {
            size = (size - 1) >> 1;
            seq -= 1;
            if x >= size { x -= size; }
        }
        y.powi(seq as i32)
    }

    // -----------------------------------------------------------------------
    // Clause deletion
    // -----------------------------------------------------------------------

    fn reduce_db(&mut self) {
        let mut learnt_indices: Vec<usize> = (self.num_original_clauses..self.clauses.len())
            .filter(|&i| self.clauses[i].learnt && !self.clauses[i].lits.is_empty())
            .collect();

        learnt_indices.sort_by(|&a, &b| {
            self.clauses[a].activity.partial_cmp(&self.clauses[b].activity)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        let limit = learnt_indices.len() / 2;
        let mut to_remove = Vec::new();

        for (idx, &cr) in learnt_indices.iter().enumerate() {
            if idx < limit && self.clauses[cr].lbd > 2 && !self.is_clause_reason(cr) {
                to_remove.push(cr);
            }
        }

        for &cr in &to_remove {
            self.remove_clause(cr);
        }
    }

    fn is_clause_reason(&self, cr: usize) -> bool {
        for &lit in &self.clauses[cr].lits {
            let var = lit_var(lit) as usize;
            if self.assigns[var] != LBOOL_UNDEF && self.reason[var] == cr as u32 {
                return true;
            }
        }
        false
    }

    fn remove_clause(&mut self, cr: usize) {
        let l0 = self.clauses[cr].lits[0];
        let l1 = self.clauses[cr].lits[1];

        Self::remove_watch_static(&mut self.watches[lit_neg(l0) as usize], cr);
        Self::remove_watch_static(&mut self.watches[lit_neg(l1) as usize], cr);

        self.clauses[cr].lits.clear();
        self.clauses[cr].learnt = false;
    }

    fn remove_watch_static(wl: &mut Vec<(usize, Lit)>, cr: usize) {
        if let Some(pos) = wl.iter().position(|&(c, _)| c == cr) {
            wl.swap_remove(pos);
        }
    }

    // -----------------------------------------------------------------------
    // Main solve loop
    // -----------------------------------------------------------------------

    fn solve(&mut self) -> bool {
        for v in 0..self.num_vars {
            self.heap_insert(v);
        }

        self.learnt_adj_cnt = self.learnt_adj_start;
        self.max_learnt = (self.num_original_clauses as f64 / 3.0) as usize + 10;

        loop {
            let conflict = self.propagate();

            if let Some(conflict_cr) = conflict {
                self.conflicts += 1;

                if self.decision_level() == 0 {
                    return false;
                }

                let (learnt_lits, btlevel) = self.analyze(conflict_cr);

                self.cancel_until(btlevel);

                if learnt_lits.len() == 1 {
                    self.enqueue(learnt_lits[0], REASON_UNDEF);
                } else {
                    let asserting_lit = learnt_lits[0];
                    let cr = self.add_clause(learnt_lits, true);
                    if let Some(cr) = cr {
                        self.enqueue(asserting_lit, cr as u32);
                    }
                }

                self.decay_var_activity();
                self.decay_clause_activity();

                // Restart check
                let restart_limit = (Self::luby(2.0, self.restart_count) * self.luby_restart_base) as u64;
                if restart_limit > 0 && self.conflicts % restart_limit == 0 {
                    self.restart_count += 1;
                    self.cancel_until(0);
                }

                // Clause deletion check
                let num_learnt = self.clauses.len() - self.num_original_clauses;
                if num_learnt > self.max_learnt + self.trail.len() {
                    self.reduce_db();
                }

                // Adjust learnt limit
                self.learnt_adj_cnt -= 1.0;
                if self.learnt_adj_cnt <= 0.0 {
                    self.learnt_adj_start *= self.learnt_adj_inc;
                    self.learnt_adj_cnt = self.learnt_adj_start;
                    self.max_learnt = (self.max_learnt as f64 * 1.1) as usize;
                }
            } else {
                // No conflict: decide
                match self.pick_branch_var() {
                    None => return true, // SAT: all vars assigned
                    Some(var) => {
                        self.decisions += 1;
                        self.trail_lim.push(self.trail.len());
                        // Pick negative phase by default
                        let lit = 2 * var + 1; // negative literal
                        self.enqueue(lit, REASON_UNDEF);
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// DIMACS parser
// ---------------------------------------------------------------------------

fn parse_dimacs(content: &str) -> (u32, Vec<Vec<Lit>>) {
    let mut num_vars = 0u32;
    let mut clauses = Vec::new();
    let mut current_clause = Vec::new();

    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('c') || line.starts_with('%') {
            continue;
        }
        if line.starts_with('p') {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 4 && parts[1] == "cnf" {
                num_vars = parts[2].parse().unwrap_or(0);
            }
            continue;
        }
        for token in line.split_whitespace() {
            if let Ok(val) = token.parse::<i32>() {
                if val == 0 {
                    if !current_clause.is_empty() {
                        clauses.push(std::mem::take(&mut current_clause));
                    }
                } else {
                    current_clause.push(lit_from_dimacs(val));
                }
            }
        }
    }
    if !current_clause.is_empty() {
        clauses.push(current_clause);
    }

    (num_vars, clauses)
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <cnf-file>", args[0]);
        process::exit(1);
    }

    let filename = &args[1];
    let content = match fs::read_to_string(filename) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Error reading {}: {}", filename, e);
            process::exit(1);
        }
    };

    let start = Instant::now();

    let (num_vars, clauses) = parse_dimacs(&content);
    eprintln!("c Parsed {} variables, {} clauses", num_vars, clauses.len());

    let mut solver = Solver::new(num_vars);

    let mut unsat_at_root = false;
    for clause_lits in clauses {
        if clause_lits.is_empty() {
            unsat_at_root = true;
            break;
        }
        solver.add_clause(clause_lits, false);
        if solver.propagate().is_some() {
            unsat_at_root = true;
            break;
        }
    }

    solver.num_original_clauses = solver.clauses.len();

    let result = if unsat_at_root { false } else { solver.solve() };

    let elapsed = start.elapsed();

    if result {
        // Verify the assignment satisfies all original clauses
        #[cfg(debug_assertions)]
        {
            for (ci, clause) in solver.clauses.iter().enumerate().take(solver.num_original_clauses) {
                let satisfied = clause.lits.iter().any(|&l| eval_lit(&solver.assigns, l) == LBOOL_TRUE);
                if !satisfied {
                    eprintln!("c BUG: clause {} not satisfied", ci);
                }
            }
        }
        println!("s SATISFIABLE");
    } else {
        println!("s UNSATISFIABLE");
    }

    eprintln!(
        "c Time: {:.3}s  Conflicts: {}  Decisions: {}  Propagations: {}",
        elapsed.as_secs_f64(), solver.conflicts, solver.decisions, solver.propagations
    );
}
