#!/bin/bash
# ============================================================
# Post-Synthesis Gate-Level Simulation
# ============================================================
set -e
cd "$(dirname "$0")/.."

SYNTH_DIR=/tmp/fa_synth
OUTDIR=/tmp/fa_postsim
mkdir -p $OUTDIR

NETLIST="$SYNTH_DIR/results/flash_attention_top_netlist.v"
SDF="$SYNTH_DIR/results/flash_attention_top.sdf"
TSMC_LIB="/home/hy258/lib_new/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn12ffcllbwp6t16p96cpd_120a"

# Check synthesis outputs exist
if [ ! -f "$NETLIST" ]; then
    echo "ERROR: Netlist not found at $NETLIST"
    echo "Run synthesis first: bash scripts/run_synthesis.sh"
    exit 1
fi

echo "============================================================"
echo "  Post-Synthesis Gate-Level Simulation"
echo "============================================================"

# Find Verilog simulation model for TSMC library
TSMC_VERILOG=$(find /home/hy258/lib_new/TSMCHOME -name "*.v" -path "*/Verilog/*" 2>/dev/null | head -1)
if [ -z "$TSMC_VERILOG" ]; then
    echo "WARNING: TSMC Verilog model not found, using +nospecify"
    TSMC_VERILOG_OPT=""
else
    TSMC_VERILOG_OPT="$TSMC_VERILOG"
fi

echo "[1/2] Compiling gate-level simulation..."
vcs -full64 -sverilog \
    +incdir+baseline/rtl/include \
    $TSMC_VERILOG_OPT \
    $NETLIST \
    baseline/tb/unit_tb/axi4_slave_mem.sv \
    baseline/tb/unit_tb/system_tb.sv \
    -timescale=1ns/1ps \
    +define+SIMULATION +define+GATE_SIM \
    +neg_tchk \
    -sdf typ:fa_tb_top.u_dut:$SDF \
    -o $OUTDIR/postsim_simv 2>&1 | tail -15

echo ""
echo "[2/2] Running gate-level simulation..."
$OUTDIR/postsim_simv +notimingcheck \
    -l $OUTDIR/postsim.log 2>&1 | tail -30

echo ""
echo "============================================================"
echo "  Post-simulation complete"
echo "  Log: $OUTDIR/postsim.log"
echo "============================================================"
