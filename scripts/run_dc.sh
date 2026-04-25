#!/usr/bin/env bash
# Run Design Compiler 2025 with the project-local Tcl flow.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

if [ -f "${SCRIPT_DIR}/synopsys2025_env.sh" ]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/synopsys2025_env.sh"
fi

if [ -f "${SCRIPT_DIR}/tsmc12_env.sh" ]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/tsmc12_env.sh"
fi

DC_BIN="${DC_BIN:-$(command -v dc_shell || true)}"
if [ -z "${DC_BIN}" ]; then
    echo "ERROR: dc_shell was not found. Source scripts/synopsys2025_env.sh or set DC_BIN." >&2
    exit 2
fi

export PROJECT_ROOT
export DC_OUT_DIR="${DC_OUT_DIR:-${PROJECT_ROOT}/build/dc}"
mkdir -p "${DC_OUT_DIR}"

LOG_FILE="${DC_LOG_FILE:-${DC_OUT_DIR}/dc_shell.log}"

echo "================================================"
echo " FlashAttention synthesis - DC 2025"
echo "================================================"
echo "Project : ${PROJECT_ROOT}"
echo "Output  : ${DC_OUT_DIR}"
echo "DC      : ${DC_BIN}"
echo "Library : ${DC_TARGET_LIB:-<not set>}"
echo "Log     : ${LOG_FILE}"
echo ""

"${DC_BIN}" -f "${SCRIPT_DIR}/run_dc.tcl" 2>&1 | tee "${LOG_FILE}"
