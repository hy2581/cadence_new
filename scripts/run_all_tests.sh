#!/bin/bash
# Run all unit tests via VCS on AutoDL
set -e

ln -sf /usr/bin/gcc-4.8 /usr/bin/gcc
ln -sf /usr/bin/g++-4.8 /usr/bin/g++
cd /workspace

PASS=0
FAIL=0
VCS_FLAGS="-full64 -sverilog -LDFLAGS -Wl,--no-as-needed +incdir+rtl/include -timescale=1ns/1ps"

run_test() {
    local NAME=$1
    shift
    local FILES="$@"
    echo ""
    echo "============================================"
    echo "  TEST: $NAME"
    echo "============================================"
    rm -rf csrc /tmp/simv_${NAME}* ${NAME}.daidir
    vcs $VCS_FLAGS $FILES -o /tmp/simv_${NAME} -l /tmp/vcs_${NAME}.log 2>&1 | grep -E "Error|Warning|modules done|up to date|CPU"
    if [ -x /tmp/simv_${NAME} ]; then
        /tmp/simv_${NAME} -l /tmp/sim_${NAME}.log 2>&1
        if grep -q "ALL TESTS PASSED" /tmp/sim_${NAME}.log; then
            echo ">>> RESULT: PASS <<<"
            PASS=$((PASS + 1))
        else
            echo ">>> RESULT: FAIL <<<"
            FAIL=$((FAIL + 1))
        fi
    else
        echo ">>> RESULT: COMPILE FAILED <<<"
        cat /tmp/vcs_${NAME}.log | grep "Error" | head -5
        FAIL=$((FAIL + 1))
    fi
}

echo "============================================"
echo "  FlashAttention Accelerator — Test Suite"
echo "============================================"

# Unit test 1: Causal Mask
run_test "causal_mask" \
    rtl/causal_mask_unit.sv \
    tb/unit_tb/causal_mask_tb.sv

# Unit test 2: AXI4-Lite Registers
run_test "axi4_lite" \
    rtl/axi4_lite_slave.sv \
    tb/unit_tb/axi4_lite_slave_tb.sv

# Unit test 3: Exp Approximation
run_test "exp_approx" \
    rtl/exp_approx_unit.sv \
    tb/unit_tb/exp_approx_unit_tb.sv

# Unit test 4: Dot Product
run_test "dot_product" \
    rtl/exp_approx_unit.sv \
    rtl/dot_product_array.sv \
    tb/unit_tb/dot_product_tb.sv

echo ""
echo "============================================"
echo "  SUMMARY: $PASS passed, $FAIL failed"
echo "============================================"
