#!/bin/bash
export SNPSLMD_LICENSE_FILE=27000@localhost
cd /work/cadence/submission

VCSHOME=/usr/synopsys/vcs-L-2016.06
VCS1=$VCSHOME/linux64/bin/vcs1
OUTDIR=/tmp/fa_sys
mkdir -p $OUTDIR

echo "============================================================"
echo "  Compiling system_tb (direct vcs1, no UVM)"
echo "============================================================"

$VCS1 \
    -Mcc=gcc -Mcplusplus=g++ \
    "-Mcfl= -pipe -fPIC -O -I${VCSHOME}/include " \
    "-Mxcflags= -pipe -fPIC -I${VCSHOME}/include" \
    "-Mldflags= -rdynamic " \
    -Mout=$OUTDIR/system_simv \
    "-Mobjects= ${VCSHOME}/linux64/lib/libvirsim.so ${VCSHOME}/linux64/lib/liberrorinf.so ${VCSHOME}/linux64/lib/libsnpsmalloc.so " \
    -Msaverestoreobj=${VCSHOME}/linux64/lib/vcs_save_restore_new.o \
    "-Msyslibs=-ldl " \
    -full64 -timescale=1ns/1ps +define+SIMULATION \
    -o $OUTDIR/system_simv \
    -picarchive -sverilog -gen_obj \
    +incdir+baseline/rtl/include \
    baseline/rtl/exp_lut_rom.sv \
    baseline/rtl/exp_approx_unit.sv \
    baseline/rtl/reciprocal_unit.sv \
    baseline/rtl/causal_mask_unit.sv \
    baseline/rtl/dot_product_array.sv \
    baseline/rtl/online_softmax_unit.sv \
    baseline/rtl/output_accumulator.sv \
    baseline/rtl/compute_core.sv \
    baseline/rtl/buffer_system.sv \
    baseline/rtl/tile_controller.sv \
    baseline/rtl/axi4_lite_slave.sv \
    baseline/rtl/axi4_master_if.sv \
    baseline/rtl/dma_engine.sv \
    baseline/rtl/flash_attention_top.sv \
    baseline/tb/unit_tb/axi4_slave_mem.sv \
    baseline/tb/unit_tb/system_tb.sv

RC=$?
echo "VCS1 exit code: $RC"
if [ $RC -eq 0 ]; then
    echo "Compile OK - now linking..."
    cd $OUTDIR
    ls -la *.o 2>/dev/null
    gcc -o system_simv *.o -L${VCSHOME}/linux64/lib -lvirsim -lerrorinf -lsnpsmalloc -ldl -rdynamic 2>&1 | tail -10
    echo "Link exit: $?"
fi
