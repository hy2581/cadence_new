#!/usr/bin/env bash
# Generate VCS activity and run DC power with SAIF annotation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

if [ -f "${SCRIPT_DIR}/synopsys2025_env.sh" ]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/synopsys2025_env.sh"
fi

if [ -f "${SCRIPT_DIR}/sky130_env.sh" ]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/sky130_env.sh"
fi

DC_BIN="${DC_BIN:-$(command -v dc_shell || true)}"
VCD2SAIF_BIN="${VCD2SAIF_BIN:-$(command -v vcd2saif || true)}"
if [ -z "${DC_BIN}" ]; then
    echo "ERROR: dc_shell was not found. Source scripts/synopsys2025_env.sh or set DC_BIN." >&2
    exit 2
fi
if [ -z "${VCD2SAIF_BIN}" ]; then
    echo "ERROR: vcd2saif was not found. Source scripts/synopsys2025_env.sh or set VCD2SAIF_BIN." >&2
    exit 2
fi

TAG="${POWER_ACTIVITY_TAG:-$(date +%Y%m%d_%H%M%S)}"
export PROJECT_ROOT
export POWER_ACTIVITY_OUT_DIR="${POWER_ACTIVITY_OUT_DIR:-${PROJECT_ROOT}/build/dc_power_activity_${TAG}}"
POWER_ACTIVITY_VCS_BUILD_DIR="${POWER_ACTIVITY_VCS_BUILD_DIR:-${PROJECT_ROOT}/build/vcs_power_activity_${TAG}}"
POWER_ACTIVITY_DIR="${POWER_ACTIVITY_OUT_DIR}/activity"
POWER_ACTIVITY_VCD="${POWER_ACTIVITY_VCD:-${POWER_ACTIVITY_VCS_BUILD_DIR}/fa_system_tb.vcd}"
export POWER_ACTIVITY_SAIF="${POWER_ACTIVITY_SAIF:-${POWER_ACTIVITY_DIR}/fa_system_tb_dut.saif}"
export POWER_ACTIVITY_NETLIST="${POWER_ACTIVITY_NETLIST:-${PROJECT_ROOT}/build/dc_quality_lint_timing_20260518_1523/netlist/fa_top_netlist.v}"
export POWER_ACTIVITY_SDC="${POWER_ACTIVITY_SDC:-${PROJECT_ROOT}/build/dc_quality_lint_timing_20260518_1523/netlist/fa_top.sdc}"
export POWER_ACTIVITY_INSTANCE_NAME="${POWER_ACTIVITY_INSTANCE_NAME:-system_tb/dut}"
VCD_INSTANCE="${POWER_ACTIVITY_VCD_INSTANCE:-system_tb.dut}"

mkdir -p "${POWER_ACTIVITY_OUT_DIR}" "${POWER_ACTIVITY_DIR}" "${POWER_ACTIVITY_VCS_BUILD_DIR}"

echo "================================================"
echo " FlashAttention activity power - VCS + DC"
echo "================================================"
echo "Project : ${PROJECT_ROOT}"
echo "DC out  : ${POWER_ACTIVITY_OUT_DIR}"
echo "VCS out : ${POWER_ACTIVITY_VCS_BUILD_DIR}"
echo "VCD     : ${POWER_ACTIVITY_VCD}"
echo "SAIF    : ${POWER_ACTIVITY_SAIF}"
echo "Netlist : ${POWER_ACTIVITY_NETLIST}"
echo "SDC     : ${POWER_ACTIVITY_SDC}"
echo ""

if [ ! -f "${POWER_ACTIVITY_SAIF}" ]; then
    if [ ! -f "${POWER_ACTIVITY_VCD}" ]; then
        SIM_PLUSARGS="+FA_DUMP_VCD=${POWER_ACTIVITY_VCD}"
        if [ -n "${POWER_ACTIVITY_VCD_DEPTH:-}" ]; then
            SIM_PLUSARGS="${SIM_PLUSARGS} +FA_DUMP_VCD_DEPTH=${POWER_ACTIVITY_VCD_DEPTH}"
        fi

        echo "[1/3] Running RTL system TB with plusarg-controlled VCD dump..."
        VCS_BUILD_DIR="${POWER_ACTIVITY_VCS_BUILD_DIR}" \
        VCS_SIM_ARGS="${VCS_SIM_ARGS:-} ${SIM_PLUSARGS}" \
            bash "${SCRIPT_DIR}/run_system_tb.sh"
    fi

    echo ""
    echo "[2/3] Converting VCD to SAIF..."
    "${VCD2SAIF_BIN}" \
        -input "${POWER_ACTIVITY_VCD}" \
        -output "${POWER_ACTIVITY_SAIF}" \
        -instance "${VCD_INSTANCE}" \
        2>&1 | tee "${POWER_ACTIVITY_OUT_DIR}/vcd2saif.log"
else
    echo "[1/3] Reusing existing SAIF: ${POWER_ACTIVITY_SAIF}"
fi

if [ ! -f "${POWER_ACTIVITY_SAIF}" ]; then
    echo "ERROR: SAIF was not produced: ${POWER_ACTIVITY_SAIF}" >&2
    exit 1
fi

LOG_FILE="${POWER_ACTIVITY_LOG_FILE:-${POWER_ACTIVITY_OUT_DIR}/dc_power_activity.log}"

echo ""
echo "[3/3] Running DC activity-annotated power..."
"${DC_BIN}" -f "${SCRIPT_DIR}/run_power_activity.tcl" 2>&1 | tee "${LOG_FILE}"
