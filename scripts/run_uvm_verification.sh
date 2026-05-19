#!/usr/bin/env bash
# VCS 2025 compile and run script for the FlashAttention UVM environment.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

if [ -f "${SCRIPT_DIR}/synopsys2025_env.sh" ]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/synopsys2025_env.sh"
fi

VCS_BIN="${VCS_BIN:-$(command -v vcs || true)}"
if [ -z "${VCS_BIN}" ]; then
    echo "ERROR: vcs was not found. Source scripts/synopsys2025_env.sh or set VCS_BIN." >&2
    exit 2
fi

BUILD_DIR="${VCS_BUILD_DIR:-${PROJECT_ROOT}/build/vcs_uvm_verification}"
UVM_TESTNAME="${UVM_TESTNAME:-fa_uvm_causal_e2e_test}"
VCS_UVM_OPT="${VCS_UVM_OPT:-uvm}"
COVERAGE_ENABLE="${VCS_ENABLE_COVERAGE:-1}"
COVERAGE_METRICS="${VCS_COVERAGE_METRICS:-line+cond+fsm+tgl+branch}"
COVERAGE_DIR="${VCS_COVERAGE_DIR:-${BUILD_DIR}/simv.vdb}"
COVERAGE_REPORT_DIR="${VCS_COVERAGE_REPORT_DIR:-${BUILD_DIR}/coverage_report}"

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

RTL_FILES=(
    "${PROJECT_ROOT}/rtl/exp_lut_rom.sv"
    "${PROJECT_ROOT}/rtl/exp_approx_unit.sv"
    "${PROJECT_ROOT}/rtl/reciprocal_unit.sv"
    "${PROJECT_ROOT}/rtl/causal_mask_unit.sv"
    "${PROJECT_ROOT}/rtl/dot_product_array.sv"
    "${PROJECT_ROOT}/rtl/online_softmax_unit.sv"
    "${PROJECT_ROOT}/rtl/output_accumulator.sv"
    "${PROJECT_ROOT}/rtl/compute_core.sv"
    "${PROJECT_ROOT}/rtl/buffer_system.sv"
    "${PROJECT_ROOT}/rtl/tile_controller.sv"
    "${PROJECT_ROOT}/rtl/axi4_lite_slave.sv"
    "${PROJECT_ROOT}/rtl/axi4_master_if.sv"
    "${PROJECT_ROOT}/rtl/dma_engine.sv"
    "${PROJECT_ROOT}/rtl/flash_attention_top.sv"
)

TB_FILES=(
    "${PROJECT_ROOT}/tb/unit_tb/axi4_slave_mem.sv"
    "${PROJECT_ROOT}/tb/uvm/fa_uvm_if.sv"
    "${PROJECT_ROOT}/tb/uvm/fa_uvm_pkg.sv"
    "${PROJECT_ROOT}/tb/uvm/fa_uvm_tb.sv"
)

VCS_ARGS=(
    -full64
    -sverilog
    -ntb_opts "${VCS_UVM_OPT}"
    "+incdir+${PROJECT_ROOT}/rtl/include"
    "+incdir+${PROJECT_ROOT}/tb/uvm"
    +define+SIMULATION
    +define+SYNTHESIS
    -timescale=1ns/1ps
    -top fa_uvm_tb
)

SIM_ARGS=(
    "+UVM_TESTNAME=${UVM_TESTNAME}"
    +UVM_NO_RELNOTES
)

if [ "${COVERAGE_ENABLE}" = "1" ]; then
    VCS_ARGS+=(-cm "${COVERAGE_METRICS}" -cm_dir "${COVERAGE_DIR}")
    SIM_ARGS+=(-cm "${COVERAGE_METRICS}" -cm_dir "${COVERAGE_DIR}")
fi

if [ -n "${VCS_DEBUG_ARGS:-}" ]; then
    # Intentionally split user-supplied extra VCS flags.
    # shellcheck disable=SC2206
    EXTRA_ARGS=(${VCS_DEBUG_ARGS})
    VCS_ARGS+=("${EXTRA_ARGS[@]}")
fi

if [ -n "${VCS_LDFLAGS:-}" ]; then
    VCS_ARGS+=(-LDFLAGS "${VCS_LDFLAGS}")
fi

if [ -n "${VCS_SIM_ARGS:-}" ]; then
    # Intentionally split user-supplied runtime plusargs/options.
    # shellcheck disable=SC2206
    EXTRA_SIM_ARGS=(${VCS_SIM_ARGS})
    SIM_ARGS+=("${EXTRA_SIM_ARGS[@]}")
fi

echo "================================================"
echo " FlashAttention UVM Verification - VCS 2025"
echo "================================================"
echo "Project  : ${PROJECT_ROOT}"
echo "Build    : ${BUILD_DIR}"
echo "VCS      : ${VCS_BIN}"
echo "UVM opt  : ${VCS_UVM_OPT}"
echo "Test     : ${UVM_TESTNAME}"
echo "Coverage : ${COVERAGE_ENABLE}"
echo ""

echo "[1/3] Compiling UVM verification TB..."
"${VCS_BIN}" "${VCS_ARGS[@]}" "${RTL_FILES[@]}" "${TB_FILES[@]}" \
    -o simv_uvm \
    -l compile.log \
    2>&1 | tee compile.stdout

if [ ! -f simv_uvm ]; then
    echo "ERROR: VCS did not produce simv_uvm. See ${BUILD_DIR}/compile.log." >&2
    exit 1
fi

echo ""
echo "[2/3] Running UVM verification TB..."
./simv_uvm "${SIM_ARGS[@]}" -l sim.log 2>&1 | tee sim.stdout

if [ "${COVERAGE_ENABLE}" = "1" ]; then
    URG_BIN="${URG_BIN:-$(command -v urg || true)}"
    if [ -n "${URG_BIN}" ] && [ -d "${COVERAGE_DIR}" ]; then
        echo ""
        echo "[3/3] Generating coverage report..."
        "${URG_BIN}" -dir "${COVERAGE_DIR}" -report "${COVERAGE_REPORT_DIR}" \
            -format both \
            2>&1 | tee urg.stdout
    else
        echo ""
        echo "[3/3] Coverage database exists but urg was not found; skipping report generation."
    fi
else
    echo ""
    echo "[3/3] Coverage disabled by VCS_ENABLE_COVERAGE=0."
fi

echo ""
echo "================================================"
echo " UVM verification complete"
echo " Compile log     : ${BUILD_DIR}/compile.log"
echo " Simulation log  : ${BUILD_DIR}/sim.log"
if [ "${COVERAGE_ENABLE}" = "1" ]; then
    echo " Coverage DB     : ${COVERAGE_DIR}"
    echo " Coverage report : ${COVERAGE_REPORT_DIR}"
fi
echo "================================================"
