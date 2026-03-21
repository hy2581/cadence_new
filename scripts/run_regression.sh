#!/bin/bash
# ============================================================
# Regression Script — Run all UVM tests
# ============================================================

TESTS=(
    "fa_zero_test"
    "fa_random_nocausal_test"
    "fa_random_causal_test"
    "fa_reg_access_test"
)

PASS=0
FAIL=0
TOTAL=${#TESTS[@]}

echo "=========================================="
echo " FlashAttention Regression: $TOTAL tests"
echo "=========================================="

for TEST in "${TESTS[@]}"; do
    echo ""
    echo "--- Running: $TEST ---"
    ./scripts/run_vcs.sh "$TEST" UVM_LOW > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "  PASS: $TEST"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $TEST"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=========================================="
echo " Results: $PASS passed, $FAIL failed / $TOTAL total"
echo "=========================================="

exit $FAIL
