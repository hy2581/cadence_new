#!/usr/bin/env bash
# Run the contest-facing UVM signoff flow for baseline and bonus behavior.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

RUN_ROOT="${UVM_SIGNOFF_ROOT:-${PROJECT_ROOT}/build/vcs_uvm_signoff}"
BASELINE_COVERAGE="${UVM_SIGNOFF_BASELINE_COVERAGE:-1}"
BONUS_COVERAGE="${UVM_SIGNOFF_BONUS_COVERAGE:-0}"

mkdir -p "${RUN_ROOT}"

SUMMARY="${RUN_ROOT}/uvm_signoff_summary.md"
: > "${SUMMARY}"

log_summary() {
    printf '%s\n' "$*" >> "${SUMMARY}"
}

check_log_clean() {
    local log_file="$1"
    local label="$2"

    if [ ! -f "${log_file}" ]; then
        echo "ERROR: missing ${label} log: ${log_file}" >&2
        return 1
    fi

    if grep -Eq 'UVM_FATAL[[:space:]]*:[[:space:]]*[1-9]|UVM_ERROR[[:space:]]*:[[:space:]]*[1-9]' "${log_file}"; then
        echo "ERROR: ${label} has UVM errors/fatals. See ${log_file}" >&2
        return 1
    fi

    if grep -Eq 'Fatal:|Error:' "${log_file}"; then
        echo "ERROR: ${label} has simulator fatal/error lines. See ${log_file}" >&2
        return 1
    fi
}

collect_result() {
    local log_file="$1"
    local label="$2"

    log_summary "## ${label}"
    log_summary ""
    log_summary "- Log: \`${log_file}\`"
    if grep -E 'FA_UVM_SUMMARY|UVM task queue PASS|AXI4-Stream bridge PASS|UVM causal E2E PASS|UVM_ERROR|UVM_FATAL' "${log_file}" >> "${SUMMARY}"; then
        :
    else
        log_summary "- No standard summary lines found."
    fi
    log_summary ""
}

echo "================================================"
echo " FlashAttention UVM Signoff Flow"
echo "================================================"
echo "Project          : ${PROJECT_ROOT}"
echo "Run root         : ${RUN_ROOT}"
echo "Baseline coverage: ${BASELINE_COVERAGE}"
echo "Bonus coverage   : ${BONUS_COVERAGE}"
echo ""

log_summary "# FlashAttention UVM Signoff Summary"
log_summary ""
log_summary "- Project: \`${PROJECT_ROOT}\`"
log_summary "- Run root: \`${RUN_ROOT}\`"
log_summary "- Baseline coverage: \`${BASELINE_COVERAGE}\`"
log_summary "- Bonus coverage: \`${BONUS_COVERAGE}\`"
log_summary ""

echo "[0/3] Script syntax preflight"
bash -n \
    "${SCRIPT_DIR}/run_uvm_verification.sh" \
    "${SCRIPT_DIR}/run_uvm_bonus.sh" \
    "${SCRIPT_DIR}/run_uvm_bonus_full.sh" \
    "${SCRIPT_DIR}/run_uvm_signoff.sh"
log_summary "## Preflight"
log_summary ""
log_summary "- Script syntax: PASS"
log_summary ""

echo ""
echo "[1/3] Baseline UVM causal E2E with scoreboard and coverage"
VCS_BUILD_DIR="${RUN_ROOT}/01_baseline_causal" \
UVM_TESTNAME="fa_uvm_causal_e2e_test" \
VCS_ENABLE_COVERAGE="${BASELINE_COVERAGE}" \
bash "${SCRIPT_DIR}/run_uvm_verification.sh"
check_log_clean "${RUN_ROOT}/01_baseline_causal/sim.log" "baseline UVM"
collect_result "${RUN_ROOT}/01_baseline_causal/sim.log" "Baseline UVM causal E2E"

echo ""
echo "[2/3] Full bonus UVM regression"
VCS_BONUS_FULL_BUILD_ROOT="${RUN_ROOT}/02_bonus_full" \
VCS_ENABLE_COVERAGE="${BONUS_COVERAGE}" \
bash "${SCRIPT_DIR}/run_uvm_bonus_full.sh"

for log_file in "${RUN_ROOT}"/02_bonus_full/*/sim.log; do
    test_name="$(basename "$(dirname "${log_file}")")"
    check_log_clean "${log_file}" "${test_name}"
    collect_result "${log_file}" "${test_name}"
done

echo ""
echo "[3/3] Signoff summary"
log_summary "## Final Result"
log_summary ""
log_summary "PASS: baseline UVM and full bonus UVM regression completed with no UVM errors or fatals."

echo "================================================"
echo " UVM signoff complete"
echo " Summary: ${SUMMARY}"
echo "================================================"
