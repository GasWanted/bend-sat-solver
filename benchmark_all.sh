#!/usr/bin/env bash
#
# Head-to-head benchmark: 4 solvers
#   1. CaDiCaL (CDCL, C++)
#   2. Rust CDCL (our implementation)
#   3. Bend CDCL-lite (DPLL + clause learning + restarts, parallel)
#   4. Bend DPLL (basic parallel DPLL)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CADICAL="${HOME}/.local/bin/cadical"
RUST_CDCL="${SCRIPT_DIR}/rust-cdcl/target/release/rust-cdcl"
BENCH_DIR="${SCRIPT_DIR}/benchmarks"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "============================================"
echo "  4-Way SAT Solver Benchmark"
echo "  $(date)"
echo "  Cores: $(nproc)"
echo "============================================"
echo ""

RESULTS="${SCRIPT_DIR}/results_all.csv"
echo "vars,clauses,seed,cadical_ms,cadical_result,rust_cdcl_ms,rust_cdcl_result,bend_cdcl_ms,bend_cdcl_result,bend_dpll_ms,bend_dpll_result" > "$RESULTS"

run_test() {
  local vars=$1 clauses=$2 seed=$3
  local cnf="${BENCH_DIR}/sat_${vars}v_s${seed}.cnf"
  local bend_dpll="${BENCH_DIR}/sat_${vars}v_s${seed}.bend"
  local bend_cdcl="/tmp/bench_cdcl_${vars}v_s${seed}.bend"

  # Generate if needed
  if [ ! -f "$cnf" ]; then
    python3 "${SCRIPT_DIR}/gen_cnf.py" "$vars" "$clauses" 3 "$seed" > "$cnf"
  fi
  if [ ! -f "$bend_dpll" ]; then
    python3 "${SCRIPT_DIR}/cnf_to_bend.py" "$cnf" > "$bend_dpll"
  fi
  python3 "${SCRIPT_DIR}/cnf_to_bend.py" --cdcl "$cnf" > "$bend_cdcl"

  echo -e "${YELLOW}--- ${vars} vars, ${clauses} clauses, seed ${seed} ---${NC}"

  # 1. CaDiCaL
  local s e ms r out
  s=$(date +%s%N)
  out=$(timeout 120 "$CADICAL" "$cnf" 2>/dev/null) || out=""
  e=$(date +%s%N); ms=$(( (e - s) / 1000000 ))
  if echo "$out" | grep -q "^s SATISFIABLE"; then r="SAT";
  elif echo "$out" | grep -q "^s UNSATISFIABLE"; then r="UNSAT";
  else r="TIMEOUT"; fi
  local cad_ms=$ms cad_r=$r
  echo -e "  CaDiCaL:       ${CYAN}${ms}ms${NC}  ${GREEN}${r}${NC}"

  # 2. Rust CDCL
  s=$(date +%s%N)
  out=$(timeout 120 "$RUST_CDCL" "$cnf" 2>/dev/null) || out=""
  e=$(date +%s%N); ms=$(( (e - s) / 1000000 ))
  if echo "$out" | grep -q "^s SATISFIABLE"; then r="SAT";
  elif echo "$out" | grep -q "^s UNSATISFIABLE"; then r="UNSAT";
  else r="TIMEOUT"; fi
  local rust_ms=$ms rust_r=$r
  echo -e "  Rust CDCL:     ${CYAN}${ms}ms${NC}  ${GREEN}${r}${NC}"

  # 3. Bend CDCL-lite
  s=$(date +%s%N)
  out=$(timeout 120 bend run-c "$bend_cdcl" 2>/dev/null) || out=""
  e=$(date +%s%N); ms=$(( (e - s) / 1000000 ))
  if echo "$out" | grep -q "Result: 1"; then r="SAT";
  elif echo "$out" | grep -q "Result: 0"; then r="UNSAT";
  else r="TIMEOUT"; fi
  local bcdcl_ms=$ms bcdcl_r=$r
  echo -e "  Bend CDCL:     ${CYAN}${ms}ms${NC}  ${GREEN}${r}${NC}"

  # 4. Bend DPLL
  s=$(date +%s%N)
  out=$(timeout 120 bend run-c "$bend_dpll" 2>/dev/null) || out=""
  e=$(date +%s%N); ms=$(( (e - s) / 1000000 ))
  if echo "$out" | grep -q "Result: 1"; then r="SAT";
  elif echo "$out" | grep -q "Result: 0"; then r="UNSAT";
  else r="TIMEOUT"; fi
  local bdpll_ms=$ms bdpll_r=$r
  echo -e "  Bend DPLL:     ${CYAN}${ms}ms${NC}  ${GREEN}${r}${NC}"

  # Correctness
  if [ "$cad_r" != "TIMEOUT" ]; then
    local all_match=true
    for solver_r in "$rust_r" "$bcdcl_r" "$bdpll_r"; do
      if [ "$solver_r" != "TIMEOUT" ] && [ "$solver_r" != "$cad_r" ]; then
        all_match=false
      fi
    done
    if $all_match; then
      echo -e "  ${GREEN}ALL CORRECT${NC}"
    else
      echo -e "  ${RED}MISMATCH: cad=$cad_r rust=$rust_r b-cdcl=$bcdcl_r b-dpll=$bdpll_r${NC}"
    fi
  fi
  echo ""

  echo "${vars},${clauses},${seed},${cad_ms},${cad_r},${rust_ms},${rust_r},${bcdcl_ms},${bcdcl_r},${bdpll_ms},${bdpll_r}" >> "$RESULTS"
}

echo "Phase 1: Small (10-20 vars)"
echo "==========================="
for seed in 1 2 3; do run_test 10 43 "$seed"; done
for seed in 1 2 3; do run_test 15 64 "$seed"; done
for seed in 1 2 3; do run_test 20 86 "$seed"; done

echo "Phase 2: Medium (25-35 vars)"
echo "============================="
for seed in 1 2 3; do run_test 25 107 "$seed"; done
for seed in 1 2; do run_test 30 128 "$seed"; done
for seed in 1 2; do run_test 35 150 "$seed"; done

echo "Phase 3: Larger (40+ vars) - CDCL solvers only"
echo "================================================"
for seed in 1 2; do
  vars=50; clauses=213
  cnf="${BENCH_DIR}/sat_${vars}v_s${seed}.cnf"
  if [ ! -f "$cnf" ]; then
    python3 "${SCRIPT_DIR}/gen_cnf.py" "$vars" "$clauses" 3 "$seed" > "$cnf"
  fi
  echo -e "${YELLOW}--- ${vars} vars, ${clauses} clauses, seed ${seed} ---${NC}"

  s=$(date +%s%N)
  out=$(timeout 120 "$CADICAL" "$cnf" 2>/dev/null) || out=""
  e=$(date +%s%N); ms=$(( (e - s) / 1000000 ))
  if echo "$out" | grep -q "^s SATISFIABLE"; then r="SAT";
  elif echo "$out" | grep -q "^s UNSATISFIABLE"; then r="UNSAT";
  else r="TIMEOUT"; fi
  echo -e "  CaDiCaL:       ${CYAN}${ms}ms${NC}  ${GREEN}${r}${NC}"
  cad_ms=$ms; cad_r=$r

  s=$(date +%s%N)
  out=$(timeout 120 "$RUST_CDCL" "$cnf" 2>/dev/null) || out=""
  e=$(date +%s%N); ms=$(( (e - s) / 1000000 ))
  if echo "$out" | grep -q "^s SATISFIABLE"; then r="SAT";
  elif echo "$out" | grep -q "^s UNSATISFIABLE"; then r="UNSAT";
  else r="TIMEOUT"; fi
  echo -e "  Rust CDCL:     ${CYAN}${ms}ms${NC}  ${GREEN}${r}${NC}"
  rust_ms=$ms; rust_r=$r

  echo -e "  Bend CDCL:     ${CYAN}skipped${NC} (too slow for 50 vars)"
  echo -e "  Bend DPLL:     ${CYAN}skipped${NC} (too slow for 50 vars)"
  echo ""

  echo "${vars},${clauses},${seed},${cad_ms},${cad_r},${rust_ms},${rust_r},-1,SKIP,-1,SKIP" >> "$RESULTS"
done

# 100 vars
for seed in 1 2; do
  vars=100; clauses=426
  cnf="${BENCH_DIR}/sat_${vars}v_s${seed}.cnf"
  if [ ! -f "$cnf" ]; then
    python3 "${SCRIPT_DIR}/gen_cnf.py" "$vars" "$clauses" 3 "$seed" > "$cnf"
  fi
  echo -e "${YELLOW}--- ${vars} vars, ${clauses} clauses, seed ${seed} ---${NC}"

  s=$(date +%s%N)
  out=$(timeout 120 "$CADICAL" "$cnf" 2>/dev/null) || out=""
  e=$(date +%s%N); ms=$(( (e - s) / 1000000 ))
  if echo "$out" | grep -q "^s SATISFIABLE"; then r="SAT";
  elif echo "$out" | grep -q "^s UNSATISFIABLE"; then r="UNSAT";
  else r="TIMEOUT"; fi
  echo -e "  CaDiCaL:       ${CYAN}${ms}ms${NC}  ${GREEN}${r}${NC}"
  cad_ms=$ms; cad_r=$r

  s=$(date +%s%N)
  out=$(timeout 120 "$RUST_CDCL" "$cnf" 2>/dev/null) || out=""
  e=$(date +%s%N); ms=$(( (e - s) / 1000000 ))
  if echo "$out" | grep -q "^s SATISFIABLE"; then r="SAT";
  elif echo "$out" | grep -q "^s UNSATISFIABLE"; then r="UNSAT";
  else r="TIMEOUT"; fi
  echo -e "  Rust CDCL:     ${CYAN}${ms}ms${NC}  ${GREEN}${r}${NC}"
  rust_ms=$ms; rust_r=$r

  echo ""
  echo "${vars},${clauses},${seed},${cad_ms},${cad_r},${rust_ms},${rust_r},-1,SKIP,-1,SKIP" >> "$RESULTS"
done

# 200 vars
for seed in 1; do
  vars=200; clauses=852
  cnf="${BENCH_DIR}/sat_${vars}v_s${seed}.cnf"
  if [ ! -f "$cnf" ]; then
    python3 "${SCRIPT_DIR}/gen_cnf.py" "$vars" "$clauses" 3 "$seed" > "$cnf"
  fi
  echo -e "${YELLOW}--- ${vars} vars, ${clauses} clauses, seed ${seed} ---${NC}"

  s=$(date +%s%N)
  out=$(timeout 120 "$CADICAL" "$cnf" 2>/dev/null) || out=""
  e=$(date +%s%N); ms=$(( (e - s) / 1000000 ))
  if echo "$out" | grep -q "^s SATISFIABLE"; then r="SAT";
  elif echo "$out" | grep -q "^s UNSATISFIABLE"; then r="UNSAT";
  else r="TIMEOUT"; fi
  echo -e "  CaDiCaL:       ${CYAN}${ms}ms${NC}  ${GREEN}${r}${NC}"
  cad_ms=$ms; cad_r=$r

  s=$(date +%s%N)
  out=$(timeout 120 "$RUST_CDCL" "$cnf" 2>/dev/null) || out=""
  e=$(date +%s%N); ms=$(( (e - s) / 1000000 ))
  if echo "$out" | grep -q "^s SATISFIABLE"; then r="SAT";
  elif echo "$out" | grep -q "^s UNSATISFIABLE"; then r="UNSAT";
  else r="TIMEOUT"; fi
  echo -e "  Rust CDCL:     ${CYAN}${ms}ms${NC}  ${GREEN}${r}${NC}"

  echo ""
  echo "${vars},${clauses},${seed},${cad_ms},${cad_r},${rust_ms},${rust_r},-1,SKIP,-1,SKIP" >> "$RESULTS"
done

echo ""
echo "Results saved to: $RESULTS"
echo ""
echo "============================================"
echo "  Summary"
echo "============================================"
python3 << 'PYEOF'
import csv
with open("$RESULTS") as f:
    rows = list(csv.DictReader(f))

print(f"{'Vars':>4} {'Clauses':>7} {'CaDiCaL':>10} {'Rust CDCL':>10} {'Bend CDCL':>10} {'Bend DPLL':>10} {'Rust/CaDiCaL':>12}")
print("-" * 75)
for r in rows:
    cad = r['cadical_ms'] + 'ms'
    rust = r['rust_cdcl_ms'] + 'ms' if r['rust_cdcl_result'] != 'SKIP' else 'skip'
    bcdcl = r['bend_cdcl_ms'] + 'ms' if r['bend_cdcl_result'] not in ('SKIP','TIMEOUT') else r['bend_cdcl_result'].lower()
    bdpll = r['bend_dpll_ms'] + 'ms' if r['bend_dpll_result'] not in ('SKIP','TIMEOUT') else r['bend_dpll_result'].lower()

    ratio = ''
    if r['rust_cdcl_result'] not in ('SKIP','TIMEOUT') and r['cadical_result'] != 'TIMEOUT':
        c = int(r['cadical_ms'])
        ru = int(r['rust_cdcl_ms'])
        if c > 0:
            ratio = f'{ru/c:.1f}x'
        else:
            ratio = 'n/a'

    print(f"{r['vars']:>4} {r['clauses']:>7} {cad:>10} {rust:>10} {bcdcl:>10} {bdpll:>10} {ratio:>12}")
PYEOF
