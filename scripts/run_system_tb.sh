#!/usr/bin/env bash
# VCS 2025 compile and run script for the FlashAttention system testbench.
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

BUILD_DIR="${VCS_BUILD_DIR:-${PROJECT_ROOT}/build/vcs_system_tb}"
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
    "${PROJECT_ROOT}/tb/unit_tb/system_tb.sv"
)

VCS_ARGS=(
    -full64
    -sverilog
    "+incdir+${PROJECT_ROOT}/rtl/include"
    +define+SIMULATION
    +define+SYNTHESIS
    -timescale=1ns/1ps
)

if [ -n "${VCS_DEBUG_ARGS:-}" ]; then
    # Intentionally split user-supplied extra VCS flags.
    # shellcheck disable=SC2206
    EXTRA_ARGS=(${VCS_DEBUG_ARGS})
    VCS_ARGS+=("${EXTRA_ARGS[@]}")
fi

if [ -n "${VCS_LDFLAGS:-}" ]; then
    VCS_ARGS+=(-LDFLAGS "${VCS_LDFLAGS}")
fi

SIM_ARGS=()
if [ -n "${VCS_SIM_ARGS:-}" ]; then
    # Intentionally split user-supplied runtime plusargs/options.
    # shellcheck disable=SC2206
    EXTRA_SIM_ARGS=(${VCS_SIM_ARGS})
    SIM_ARGS+=("${EXTRA_SIM_ARGS[@]}")
fi

echo "================================================"
echo " FlashAttention System TB - VCS 2025"
echo "================================================"
echo "Project : ${PROJECT_ROOT}"
echo "Build   : ${BUILD_DIR}"
echo "VCS     : ${VCS_BIN}"
echo ""

echo "[1/2] Compiling..."
"${VCS_BIN}" "${VCS_ARGS[@]}" "${RTL_FILES[@]}" "${TB_FILES[@]}" \
    -o simv_system \
    -l compile.log \
    2>&1 | tee compile.stdout

if [ ! -f simv_system ]; then
    echo "ERROR: VCS did not produce simv_system. See ${BUILD_DIR}/compile.log." >&2
    exit 1
fi

echo ""
echo "[2/2] Running simulation..."
./simv_system "${SIM_ARGS[@]}" -l sim.log 2>&1 | tee sim.stdout

echo ""
echo "================================================"
echo " Simulation complete"
echo " Compile log: ${BUILD_DIR}/compile.log"
echo " Sim log    : ${BUILD_DIR}/sim.log"
echo "================================================"
