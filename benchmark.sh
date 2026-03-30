#!/usr/bin/env bash
#
# Benchmark: Bend SAT Solver vs CaDiCaL
#
# Compares wall-clock time of:
#   1. bend run-c  (parallel, multi-core)
#   2. bend run-rs (single-thread baseline)
#   3. CaDiCaL    (state-of-the-art CDCL solver)
#
# Usage: ./benchmark.sh [cadical_path]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CADICAL="${1:-$HOME/.local/bin/cadical}"
BENCH_DIR="$SCRIPT_DIR/benchmarks"
RESULTS_FILE="$SCRIPT_DIR/results.csv"

mkdir -p "$BENCH_DIR"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "============================================"
echo "  Bend SAT Solver Benchmark"
echo "  $(date)"
echo "  Cores: $(nproc)"
echo "  Bend: $(bend --version 2>&1)"
echo "  CaDiCaL: $($CADICAL --version 2>&1 || echo 'not found')"
echo "============================================"
echo ""

# CSV header
echo "vars,clauses,ratio,seed,cadical_time,cadical_result,bend_c_time,bend_c_result,bend_rs_time,bend_rs_result" > "$RESULTS_FILE"

# Time a command, return wall-clock seconds and result
time_cmd() {
  local start end elapsed result
  start=$(date +%s%N)
  result=$(timeout 60 "$@" 2>/dev/null) || result="TIMEOUT"
  end=$(date +%s%N)
  elapsed=$(( (end - start) / 1000000 ))  # milliseconds
  echo "$elapsed $result"
}

run_benchmark() {
  local vars=$1 clauses=$2 seed=$3
  local ratio
  ratio=$(python3 -c "print(f'{$clauses/$vars:.2f}')")

  local cnf_file="$BENCH_DIR/sat_${vars}v_${clauses}c_s${seed}.cnf"
  local bend_file="$BENCH_DIR/sat_${vars}v_${clauses}c_s${seed}.bend"

  echo -e "${YELLOW}--- ${vars} vars, ${clauses} clauses (ratio ${ratio}), seed ${seed} ---${NC}"

  # Generate CNF
  python3 "$SCRIPT_DIR/gen_cnf.py" "$vars" "$clauses" 3 "$seed" > "$cnf_file"

  # Convert to Bend
  python3 "$SCRIPT_DIR/cnf_to_bend.py" "$cnf_file" > "$bend_file"

  # Run CaDiCaL
  local cad_start cad_end cad_ms cad_result
  cad_start=$(date +%s%N)
  cad_output=$(timeout 60 "$CADICAL" "$cnf_file" 2>/dev/null) || true
  cad_end=$(date +%s%N)
  cad_ms=$(( (cad_end - cad_start) / 1000000 ))
  if echo "$cad_output" | grep -q "^s SATISFIABLE"; then
    cad_result="SAT"
  elif echo "$cad_output" | grep -q "^s UNSATISFIABLE"; then
    cad_result="UNSAT"
  else
    cad_result="TIMEOUT"
  fi
  echo -e "  CaDiCaL:    ${cad_ms}ms  ${GREEN}${cad_result}${NC}"

  # Run Bend (C backend - parallel)
  local bend_c_start bend_c_end bend_c_ms bend_c_result bend_c_raw
  bend_c_start=$(date +%s%N)
  bend_c_raw=$(timeout 60 bend run-c "$bend_file" 2>/dev/null) || bend_c_raw="TIMEOUT"
  bend_c_end=$(date +%s%N)
  bend_c_ms=$(( (bend_c_end - bend_c_start) / 1000000 ))
  if echo "$bend_c_raw" | grep -q "Result: 1"; then
    bend_c_result="SAT"
  elif echo "$bend_c_raw" | grep -q "Result: 0"; then
    bend_c_result="UNSAT"
  else
    bend_c_result="TIMEOUT"
  fi
  echo -e "  Bend run-c: ${bend_c_ms}ms  ${GREEN}${bend_c_result}${NC}"

  # Run Bend (Rust backend - single thread)
  local bend_rs_start bend_rs_end bend_rs_ms bend_rs_result bend_rs_raw
  bend_rs_start=$(date +%s%N)
  bend_rs_raw=$(timeout 60 bend run-rs "$bend_file" 2>/dev/null) || bend_rs_raw="TIMEOUT"
  bend_rs_end=$(date +%s%N)
  bend_rs_ms=$(( (bend_rs_end - bend_rs_start) / 1000000 ))
  if echo "$bend_rs_raw" | grep -q "Result: 1"; then
    bend_rs_result="SAT"
  elif echo "$bend_rs_raw" | grep -q "Result: 0"; then
    bend_rs_result="UNSAT"
  else
    bend_rs_result="TIMEOUT"
  fi
  echo -e "  Bend run-rs: ${bend_rs_ms}ms ${GREEN}${bend_rs_result}${NC}"

  # Correctness check
  if [ "$cad_result" != "TIMEOUT" ] && [ "$bend_c_result" != "TIMEOUT" ]; then
    if [ "$cad_result" = "$bend_c_result" ]; then
      echo -e "  ${GREEN}CORRECT${NC} (matches CaDiCaL)"
    else
      echo -e "  ${RED}MISMATCH${NC}: CaDiCaL=${cad_result}, Bend=${bend_c_result}"
    fi
  fi

  # Speedup
  if [ "$bend_rs_ms" -gt 0 ] && [ "$bend_c_ms" -gt 0 ] && [ "$bend_rs_result" != "TIMEOUT" ] && [ "$bend_c_result" != "TIMEOUT" ]; then
    local speedup
    speedup=$(python3 -c "print(f'{$bend_rs_ms / $bend_c_ms:.2f}x')")
    echo -e "  Parallel speedup (run-rs/run-c): ${YELLOW}${speedup}${NC}"
  fi

  echo ""

  # Write CSV
  echo "${vars},${clauses},${ratio},${seed},${cad_ms},${cad_result},${bend_c_ms},${bend_c_result},${bend_rs_ms},${bend_rs_result}" >> "$RESULTS_FILE"
}

echo "Phase 1: Small instances (correctness + warmup)"
echo "================================================"
for seed in 1 2 3; do
  run_benchmark 10 43 "$seed"     # 10 vars, ratio ~4.3
done

echo ""
echo "Phase 2: Medium instances (parallel scaling test)"
echo "================================================="
for seed in 1 2 3; do
  run_benchmark 15 64 "$seed"     # 15 vars, ratio ~4.27
done

for seed in 1 2 3; do
  run_benchmark 20 85 "$seed"     # 20 vars, ratio ~4.25
done

echo ""
echo "Phase 3: Larger instances (stress test)"
echo "========================================"
for seed in 1 2; do
  run_benchmark 25 107 "$seed"    # 25 vars
done

for seed in 1 2; do
  run_benchmark 30 128 "$seed"    # 30 vars
done

echo ""
echo "Results saved to: $RESULTS_FILE"
echo ""
echo "============================================"
echo "  Summary"
echo "============================================"
python3 -c "
import csv
with open('$RESULTS_FILE') as f:
    reader = csv.DictReader(f)
    rows = list(reader)

correct = sum(1 for r in rows if r['cadical_result'] == r['bend_c_result'] and r['cadical_result'] != 'TIMEOUT')
total = sum(1 for r in rows if r['cadical_result'] != 'TIMEOUT' and r['bend_c_result'] != 'TIMEOUT')
print(f'Correctness: {correct}/{total}')

rs_times = [int(r['bend_rs_time']) for r in rows if r['bend_rs_result'] != 'TIMEOUT']
c_times = [int(r['bend_c_time']) for r in rows if r['bend_c_result'] != 'TIMEOUT']
if rs_times and c_times:
    avg_speedup = sum(rs/c for rs, c in zip(rs_times, c_times) if c > 0) / len(rs_times)
    print(f'Avg parallel speedup (run-rs/run-c): {avg_speedup:.2f}x')
"
