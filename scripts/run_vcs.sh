#!/bin/bash
# ============================================================
# VCS Compile & Simulate Script for FlashAttention Accelerator
# Usage:
#   ./scripts/run_vcs.sh [TESTNAME] [VERBOSITY]
# Example:
#   ./scripts/run_vcs.sh fa_random_causal_test UVM_MEDIUM
# ============================================================

set -e

TESTNAME=${1:-fa_reg_access_test}
VERBOSITY=${2:-UVM_MEDIUM}
WORKDIR=work_vcs

echo "================================================"
echo " FlashAttention VCS Simulation"
echo " Test: $TESTNAME"
echo " Verbosity: $VERBOSITY"
echo "================================================"

mkdir -p $WORKDIR reports/vcs_sim

# --- Compile ---
echo "[1/2] Compiling..."
vcs -full64 -sverilog \
    -ntb_opts uvm-1.2 \
    -timescale=1ns/1ps \
    -f filelist.f \
    -cm line+cond+fsm+tgl+branch \
    -debug_access+all \
    -o $WORKDIR/simv \
    -l reports/vcs_sim/compile_${TESTNAME}.log \
    +define+SIMULATION \
    2>&1 | tail -20

echo "[2/2] Running simulation..."
$WORKDIR/simv \
    +UVM_TESTNAME=$TESTNAME \
    +UVM_VERBOSITY=$VERBOSITY \
    -cm line+cond+fsm+tgl+branch \
    +DUMP_VCD \
    -l reports/vcs_sim/sim_${TESTNAME}.log \
    2>&1 | tail -30

echo ""
echo "================================================"
echo " Simulation complete: $TESTNAME"
echo " Log: reports/vcs_sim/sim_${TESTNAME}.log"
echo "================================================"
