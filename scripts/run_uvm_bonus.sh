#!/usr/bin/env bash
# Run selected UVM bonus tests with isolated VCS build directories.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

TESTS="${UVM_BONUS_TESTS:-fa_uvm_padding_mask_test fa_uvm_multi_head_test fa_uvm_task_queue_test fa_uvm_bf16_fp16_test fa_uvm_fixed_format_test fa_uvm_int8_fp8_test fa_uvm_dropout_test fa_uvm_axis_smoke_test}"
BASE_BUILD_DIR="${VCS_BONUS_BUILD_ROOT:-${PROJECT_ROOT}/build/vcs_uvm_bonus}"

mkdir -p "${BASE_BUILD_DIR}"

echo "================================================"
echo " FlashAttention UVM Bonus Regression"
echo "================================================"
echo "Project : ${PROJECT_ROOT}"
echo "Builds  : ${BASE_BUILD_DIR}"
echo "Tests   : ${TESTS}"
echo ""

for test_name in ${TESTS}; do
    test_build_dir="${BASE_BUILD_DIR}/${test_name}"
    echo "------------------------------------------------"
    echo "Running ${test_name}"
    echo "Build ${test_build_dir}"
    echo "------------------------------------------------"
    VCS_BUILD_DIR="${test_build_dir}" \
    UVM_TESTNAME="${test_name}" \
    VCS_ENABLE_COVERAGE="${VCS_ENABLE_COVERAGE:-0}" \
    bash "${SCRIPT_DIR}/run_uvm_verification.sh"
done

echo ""
echo "================================================"
echo " UVM bonus regression complete"
echo "================================================"
