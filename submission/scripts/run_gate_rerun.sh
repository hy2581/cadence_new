#!/bin/bash
set +e

if [ -z "$1" ]; then
  echo "Usage: $0 <result_dir>"
  exit 2
fi

RES="$1"
cd /work/cadence/submission || exit 2

STUB="$RES/syn/gate_stub_auto.v"
mkdir -p "$(dirname "$STUB")"

{
  cat <<'EOF'
module \**SEQGEN** (clear, preset, next_state, clocked_on, data_in, enable, Q,
                    synch_clear, synch_preset, synch_toggle, synch_enable);
  input clear, preset, next_state, clocked_on, data_in, enable;
  input synch_clear, synch_preset, synch_toggle, synch_enable;
  output reg Q;
  always @(posedge clocked_on or posedge clear or posedge preset) begin
    if (clear) Q <= 1'b0;
    else if (preset) Q <= 1'b1;
    else begin
      if (synch_clear) Q <= 1'b0;
      else if (synch_preset) Q <= 1'b1;
      else if (synch_toggle) Q <= ~Q;
      else if (synch_enable) Q <= next_state;
      else if (enable) Q <= data_in;
    end
  end
endmodule

module SELECT_OP(
EOF

  for i in $(seq 1 63); do
    echo "  DATA${i},"
  done
  for i in $(seq 1 63); do
    echo "  CONTROL${i},"
  done

  cat <<'EOF'
  Z
);
EOF

  for i in $(seq 1 63); do
    echo "  input [1023:0] DATA${i};"
  done
  for i in $(seq 1 63); do
    echo "  input CONTROL${i};"
  done

  cat <<'EOF'
  output [1023:0] Z;
  assign Z =
EOF

  for i in $(seq 1 63); do
    if [ "$i" -lt 63 ]; then
      echo "    CONTROL${i} ? DATA${i} :"
    else
      echo "    CONTROL${i} ? DATA${i} : 1024'b0;"
    fi
  done

  echo "endmodule"

  cat <<'EOF'

module ADD_UNS_OP(input [1023:0] A, input [1023:0] B, output [1023:0] Z);
  assign Z = A + B;
endmodule

module ADD_TC_OP(input [1023:0] A, input [1023:0] B, output [1023:0] Z);
  assign Z = A + B;
endmodule

module SUB_UNS_OP(input [1023:0] A, input [1023:0] B, output [1023:0] Z);
  assign Z = A - B;
endmodule

module SUB_TC_OP(input [1023:0] A, input [1023:0] B, output [1023:0] Z);
  assign Z = A - B;
endmodule

module MULT_UNS_OP(input [1023:0] A, input [1023:0] B, output [1023:0] Z);
  assign Z = A * B;
endmodule

module MULT_TC_OP(input [1023:0] A, input [1023:0] B, output [1023:0] Z);
  assign Z = A * B;
endmodule

module DIV_TC_OP(input [1023:0] A, input [1023:0] B, output [1023:0] QUOTIENT);
  assign QUOTIENT = (B != 0) ? (A / B) : 1024'b0;
endmodule

module GT_UNS_OP(input [1023:0] A, input [1023:0] B, output Z);
  assign Z = (A > B);
endmodule

module GT_TC_OP(input [1023:0] A, input [1023:0] B, output Z);
  assign Z = ($signed(A) > $signed(B));
endmodule

module LT_UNS_OP(input [1023:0] A, input [1023:0] B, output Z);
  assign Z = (A < B);
endmodule

module LEQ_TC_OP(input [1023:0] A, input [1023:0] B, output Z);
  assign Z = ($signed(A) <= $signed(B));
endmodule

module GEQ_TC_OP(input [1023:0] A, input [1023:0] B, output Z);
  assign Z = ($signed(A) >= $signed(B));
endmodule

module EQ_UNS_OP(input [1023:0] A, input [1023:0] B, output Z);
  assign Z = (A == B);
endmodule

module MUX_OP(
  input [1023:0] D0, input [1023:0] D1, input [1023:0] D2, input [1023:0] D3,
  input [1023:0] D4, input [1023:0] D5, input [1023:0] D6, input [1023:0] D7,
  input [1023:0] S, input [1023:0] S0, input [1023:0] S1, input [1023:0] S2,
  input [1023:0] S3, output [1023:0] Z
);
  assign Z = D0;
endmodule
EOF
} > "$STUB"

/usr/synopsys/11.9/amd64/bin/lmgrd -c /usr/local/flexlm/licenses/license.dat -l "$RES/logs/lmgrd_gate_rerun_script.log" &
sleep 5
export LM_LICENSE_FILE=27000@127.0.0.1
export SNPSLMD_LICENSE_FILE=27000@127.0.0.1

vcs +error+200 -full64 -sverilog \
  +incdir+baseline/rtl/include \
  /usr/synopsys/dc-L-2016.03-SP1/packages/gtech/src_ver/gtech_lib.v \
  "$STUB" \
  "$RES/syn/flash_attention_top_syn.v" \
  baseline/tb/unit_tb/axi4_slave_mem.sv \
  baseline/tb/unit_tb/system_tb.sv \
  -timescale=1ns/1ps +define+GATE_SIM \
  -o "$RES/syn/baseline_gate_simv" > "$RES/logs/04_gate_compile_rerun_script.log" 2>&1
GATE_COMPILE_RC=$?

if [ "$GATE_COMPILE_RC" -eq 0 ]; then
  "$RES/syn/baseline_gate_simv" -sdf max:system_tb.dut:"$RES/syn/flash_attention_top_syn.sdf" +sdfverbose > "$RES/logs/05_gate_run_rerun_script.log" 2>&1
  GATE_RUN_RC=$?
else
  GATE_RUN_RC=97
fi

{
  echo "GATE_COMPILE_RC=$GATE_COMPILE_RC"
  echo "GATE_RUN_RC=$GATE_RUN_RC"
} | tee "$RES/logs/05_gate_rerun_script.summary"
