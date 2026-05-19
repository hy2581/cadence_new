#!/usr/bin/env bash
# Run the full Contest-2 bonus UVM regression, including the SEQ_LEN=512 variant.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

BASE_BUILD_DIR="${VCS_BONUS_FULL_BUILD_ROOT:-${PROJECT_ROOT}/build/vcs_uvm_bonus_full}"
mkdir -p "${BASE_BUILD_DIR}"

echo "================================================"
echo " FlashAttention Full Bonus UVM Regression"
echo "================================================"
echo "Project : ${PROJECT_ROOT}"
echo "Builds  : ${BASE_BUILD_DIR}"
echo ""

echo "------------------------------------------------"
echo "Running baseline UVM causal E2E"
echo "------------------------------------------------"
VCS_BUILD_DIR="${BASE_BUILD_DIR}/fa_uvm_causal_e2e_test" \
UVM_TESTNAME="fa_uvm_causal_e2e_test" \
VCS_ENABLE_COVERAGE="${VCS_ENABLE_COVERAGE:-0}" \
bash "${SCRIPT_DIR}/run_uvm_verification.sh"

echo "------------------------------------------------"
echo "Running 256-row bonus UVM tests"
echo "------------------------------------------------"
VCS_BONUS_BUILD_ROOT="${BASE_BUILD_DIR}" \
VCS_ENABLE_COVERAGE="${VCS_ENABLE_COVERAGE:-0}" \
bash "${SCRIPT_DIR}/run_uvm_bonus.sh"

echo "------------------------------------------------"
echo "Running SEQ_LEN=512 compiled bonus UVM test"
echo "------------------------------------------------"
VCS_BUILD_DIR="${BASE_BUILD_DIR}/fa_uvm_seq512_test" \
UVM_TESTNAME="fa_uvm_seq512_test" \
VCS_ENABLE_COVERAGE="${VCS_ENABLE_COVERAGE:-0}" \
VCS_EXTRA_DEFINES="FA_SEQ_LEN_OVERRIDE=512" \
bash "${SCRIPT_DIR}/run_uvm_verification.sh"

echo ""
echo "================================================"
echo " Full bonus UVM regression complete"
echo "================================================"
