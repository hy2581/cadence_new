#!/usr/bin/env bash
# Export DDC/SDF/SPEF-style artifacts from an existing synthesized netlist.
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
if [ -z "${DC_BIN}" ]; then
    echo "ERROR: dc_shell was not found. Source scripts/synopsys2025_env.sh or set DC_BIN." >&2
    exit 2
fi

TAG="${SDF_EXPORT_TAG:-$(date +%Y%m%d_%H%M%S)}"
export PROJECT_ROOT
export SDF_EXPORT_OUT_DIR="${SDF_EXPORT_OUT_DIR:-${PROJECT_ROOT}/build/dc_sdf_export_${TAG}}"
export SDF_EXPORT_NETLIST="${SDF_EXPORT_NETLIST:-${PROJECT_ROOT}/build/dc_quality_lint_timing_20260518_1523/netlist/fa_top_netlist.v}"
export SDF_EXPORT_SDC="${SDF_EXPORT_SDC:-${PROJECT_ROOT}/build/dc_quality_lint_timing_20260518_1523/netlist/fa_top.sdc}"

mkdir -p "${SDF_EXPORT_OUT_DIR}"
LOG_FILE="${SDF_EXPORT_LOG_FILE:-${SDF_EXPORT_OUT_DIR}/dc_sdf_export.log}"

echo "================================================"
echo " FlashAttention SDF export - DC 2025"
echo "================================================"
echo "Project : ${PROJECT_ROOT}"
echo "Output  : ${SDF_EXPORT_OUT_DIR}"
echo "Netlist : ${SDF_EXPORT_NETLIST}"
echo "SDC     : ${SDF_EXPORT_SDC}"
echo "DC      : ${DC_BIN}"
echo "Library : ${DC_TARGET_LIB:-<not set>}"
echo "Log     : ${LOG_FILE}"
echo ""

"${DC_BIN}" -f "${SCRIPT_DIR}/run_sdf_export.tcl" 2>&1 | tee "${LOG_FILE}"
