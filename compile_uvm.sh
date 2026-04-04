#!/bin/bash
export SNPSLMD_LICENSE_FILE=27000@localhost
cd /work/cadence/submission

VCSHOME=/usr/synopsys/vcs-L-2016.06
VCS1=$VCSHOME/linux64/bin/vcs1
UVMHOME=$VCSHOME/etc/uvm-1.2
OUTDIR=/tmp/fa_uvm
mkdir -p $OUTDIR

RTL_FILES=(
    baseline/rtl/exp_lut_rom.sv
    baseline/rtl/exp_approx_unit.sv
    baseline/rtl/reciprocal_unit.sv
    baseline/rtl/causal_mask_unit.sv
    baseline/rtl/dot_product_array.sv
    baseline/rtl/online_softmax_unit.sv
    baseline/rtl/output_accumulator.sv
    baseline/rtl/compute_core.sv
    baseline/rtl/buffer_system.sv
    baseline/rtl/tile_controller.sv
    baseline/rtl/axi4_lite_slave.sv
    baseline/rtl/axi4_master_if.sv
    baseline/rtl/dma_engine.sv
    baseline/rtl/flash_attention_top.sv
)

TB_FILES=(
    baseline/tb/agents/axi4_lite_agent/axi4_lite_if.sv
    baseline/tb/agents/axi4_mem_agent/axi4_mem_if.sv
    baseline/tb/uvm_env/fa_env_pkg.sv
    baseline/tb/tb_top/fa_tb_top.sv
)

echo "============================================================"
echo "  Compiling UVM testbench (direct vcs1)"
echo "============================================================"

$VCS1 \
    -Mcc=gcc -Mcplusplus=g++ \
    "-Mcfl= -pipe -DVCSMX -fPIC -O -I${VCSHOME}/include " \
    "-Mxcflags= -pipe -DVCSMX -fPIC -I${VCSHOME}/include" \
    "-Mldflags= -rdynamic " \
    -Mout=$OUTDIR/uvm_simv \
    "-Mobjects=${VCSHOME}/linux64/lib/vpdlogstub.o ${VCSHOME}/linux64/lib/libvirsim.so ${VCSHOME}/linux64/lib/liberrorinf.so ${VCSHOME}/linux64/lib/libsnpsmalloc.so " \
    -Msaverestoreobj=${VCSHOME}/linux64/lib/vcs_save_restore_new.o \
    "-Mcsrc=${UVMHOME}/dpi/uvm_dpi.cc " \
    "-Msyslibs=-ldl " \
    +incdir+${UVMHOME} \
    ${UVMHOME}/uvm_pkg.sv \
    -full64 -ntb_opts uvm-1.2 \
    +incdir+${UVMHOME}/ \
    -timescale=1ns/1ps +define+SIMULATION \
    -o $OUTDIR/uvm_simv \
    -picarchive -sverilog -gen_obj \
    +incdir+baseline/rtl/include \
    +incdir+baseline/tb \
    +incdir+baseline/tb/agents \
    +incdir+baseline/tb/agents/axi4_lite_agent \
    +incdir+baseline/tb/agents/axi4_mem_agent \
    +incdir+baseline/tb/uvm_env \
    +incdir+baseline/tb/sequences \
    +incdir+baseline/tb/tests \
    ${RTL_FILES[@]} \
    ${TB_FILES[@]} \
    -P ${VCSHOME}/linux64/lib/vcsdstub.tab

RC=$?
echo "VCS1 exit code: $RC"

if [ $RC -eq 0 ]; then
    echo "Compile OK"
else
    echo "Compile FAILED"
fi
