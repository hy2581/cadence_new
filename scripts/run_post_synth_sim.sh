#!/usr/bin/env bash
# Run no-SDF post-synthesis gate-level simulation with the latest DC netlist.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

if [ -f "${SCRIPT_DIR}/synopsys2025_env.sh" ]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/synopsys2025_env.sh"
fi

VCS_BIN="${VCS_BIN:-$(command -v vcs || true)}"
if [ -z "${VCS_BIN}" ]; then
    echo "ERROR: vcs was not found. Source scripts/synopsys2025_env.sh or set VCS_BIN." >&2
    exit 2
fi

BUILD_DIR="${POST_SYNTH_BUILD_DIR:-${PROJECT_ROOT}/build/vcs_post_synth_sim}"
NETLIST="${POST_SYNTH_NETLIST:-${PROJECT_ROOT}/build/dc_quality_lint_timing_20260518_1523/netlist/fa_top_netlist.v}"
TB_KIND="${POST_SYNTH_TB:-system}"
SKY130_CELL_ROOT="${SKY130_CELL_ROOT:-/home/hy258/cadence_codex_run_20260430_2114/pdk/src/skywater-pdk-libs-sky130_fd_sc_hs/cells}"
POST_SYNTH_SDF="${POST_SYNTH_SDF:-0}"
POST_SYNTH_USE_SPECIFY="${POST_SYNTH_USE_SPECIFY:-0}"
POST_SYNTH_NORMALIZE_SKY130_SDF="${POST_SYNTH_NORMALIZE_SKY130_SDF:-0}"
POST_SYNTH_NORMALIZE_SKY130_SDF_ASYNC="${POST_SYNTH_NORMALIZE_SKY130_SDF_ASYNC:-0}"
POST_SYNTH_NORMALIZED_SDF_FILE="${POST_SYNTH_NORMALIZED_SDF_FILE:-}"
POST_SYNTH_CELL_MODEL="${POST_SYNTH_CELL_MODEL:-functional}"
SDF_FILE="${SDF_FILE:-${POST_SYNTH_SDF_FILE:-}}"
SDF_MODE="${POST_SYNTH_SDF_MODE:-max}"
SDF_SCOPE="${POST_SYNTH_SDF_SCOPE:-}"
SDF_CLK_HALF_NS="${POST_SYNTH_SDF_CLK_HALF_NS:-5.0}"
SDF_ORIGINAL_FILE=""
SDF_NORMALIZATION_REPORT=""

if [ "${POST_SYNTH_USE_SPECIFY}" = "1" ]; then
    POST_SYNTH_CELL_MODEL="timing"
fi
case "${POST_SYNTH_CELL_MODEL}" in
    functional)
        ;;
    timing|specify)
        POST_SYNTH_CELL_MODEL="timing"
        POST_SYNTH_USE_SPECIFY="1"
        ;;
    *)
        echo "ERROR: unsupported POST_SYNTH_CELL_MODEL=${POST_SYNTH_CELL_MODEL}; use functional or timing." >&2
        exit 1
        ;;
esac
case "${POST_SYNTH_NORMALIZE_SKY130_SDF}" in
    0|1)
        ;;
    *)
        echo "ERROR: unsupported POST_SYNTH_NORMALIZE_SKY130_SDF=${POST_SYNTH_NORMALIZE_SKY130_SDF}; use 0 or 1." >&2
        exit 1
        ;;
esac
case "${POST_SYNTH_NORMALIZE_SKY130_SDF_ASYNC}" in
    0|1)
        ;;
    *)
        echo "ERROR: unsupported POST_SYNTH_NORMALIZE_SKY130_SDF_ASYNC=${POST_SYNTH_NORMALIZE_SKY130_SDF_ASYNC}; use 0 or 1." >&2
        exit 1
        ;;
esac
if [ "${POST_SYNTH_NORMALIZE_SKY130_SDF}" = "1" ] && [ "${POST_SYNTH_SDF}" != "1" ]; then
    echo "ERROR: POST_SYNTH_NORMALIZE_SKY130_SDF=1 requires POST_SYNTH_SDF=1." >&2
    exit 1
fi
if [ "${POST_SYNTH_NORMALIZE_SKY130_SDF_ASYNC}" = "1" ] && [ "${POST_SYNTH_NORMALIZE_SKY130_SDF}" != "1" ]; then
    echo "ERROR: POST_SYNTH_NORMALIZE_SKY130_SDF_ASYNC=1 requires POST_SYNTH_NORMALIZE_SKY130_SDF=1." >&2
    exit 1
fi

if [ ! -f "${NETLIST}" ]; then
    echo "ERROR: post-synthesis netlist not found: ${NETLIST}" >&2
    exit 1
fi
if [ ! -d "${SKY130_CELL_ROOT}" ]; then
    echo "ERROR: Sky130 HS cell Verilog root not found: ${SKY130_CELL_ROOT}" >&2
    exit 1
fi
if [ "${POST_SYNTH_SDF}" = "1" ]; then
    if [ -z "${SDF_FILE}" ]; then
        echo "ERROR: POST_SYNTH_SDF=1 requires SDF_FILE=/path/to/fa_top.sdf." >&2
        exit 1
    fi
    if [ ! -f "${SDF_FILE}" ]; then
        echo "ERROR: SDF file not found: ${SDF_FILE}" >&2
        exit 1
    fi
    SDF_FILE="$(cd "$(dirname "${SDF_FILE}")" && pwd)/$(basename "${SDF_FILE}")"
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

if [ "${POST_SYNTH_SDF}" = "1" ]; then
    SDF_ORIGINAL_FILE="${SDF_FILE}"
    if [ "${POST_SYNTH_NORMALIZE_SKY130_SDF}" = "1" ]; then
        if [ -z "${POST_SYNTH_NORMALIZED_SDF_FILE}" ]; then
            sdf_base="$(basename "${SDF_FILE}")"
            sdf_base="${sdf_base%.sdf}"
            if [ "${POST_SYNTH_NORMALIZE_SKY130_SDF_ASYNC}" = "1" ]; then
                POST_SYNTH_NORMALIZED_SDF_FILE="${BUILD_DIR}/${sdf_base}.sky130_pathnames_async.sdf"
            else
                POST_SYNTH_NORMALIZED_SDF_FILE="${BUILD_DIR}/${sdf_base}.sky130_pathnames.sdf"
            fi
        fi
        SDF_NORMALIZATION_REPORT="${BUILD_DIR}/sky130_sdf_normalization_report.txt"
        echo "[setup] Normalizing Sky130 SDF condition tokens..."
        NORMALIZE_ARGS=(
            --input "${SDF_ORIGINAL_FILE}"
            --output "${POST_SYNTH_NORMALIZED_SDF_FILE}"
            --report "${SDF_NORMALIZATION_REPORT}"
        )
        if [ "${POST_SYNTH_NORMALIZE_SKY130_SDF_ASYNC}" = "1" ]; then
            NORMALIZE_ARGS+=(--normalize-async-recrem)
        fi
        python3 "${SCRIPT_DIR}/normalize_sky130_sdf.py" \
            "${NORMALIZE_ARGS[@]}"
        SDF_FILE="${POST_SYNTH_NORMALIZED_SDF_FILE}"
    fi
fi

if [ "${POST_SYNTH_CELL_MODEL}" = "timing" ]; then
    OVERLAY_ROOT="${BUILD_DIR}/sky130_timing_model_overlay/cells"
else
    OVERLAY_ROOT="${BUILD_DIR}/sky130_model_overlay/cells"
fi
mkdir -p \
    "${OVERLAY_ROOT}/anchor" \
    "${OVERLAY_ROOT}/u_vpwr_vgnd" \
    "${OVERLAY_ROOT}/u_df_p_pg" \
    "${OVERLAY_ROOT}/u_df_p_no_pg" \
    "${OVERLAY_ROOT}/u_df_p_r_pg" \
    "${OVERLAY_ROOT}/u_df_p_r_no_pg" \
    "${OVERLAY_ROOT}/u_df_p_s_pg" \
    "${OVERLAY_ROOT}/u_df_p_s_no_pg" \
    "${OVERLAY_ROOT}/u_dfb_setdom_pg" \
    "${OVERLAY_ROOT}/u_dfb_setdom_notify_pg" \
    "${OVERLAY_ROOT}/u_dl_p_pg" \
    "${OVERLAY_ROOT}/u_dl_p_no_pg" \
    "${OVERLAY_ROOT}/u_dl_p_r_pg" \
    "${OVERLAY_ROOT}/u_dl_p_r_no_pg" \
    "${OVERLAY_ROOT}/u_edf_p_pg" \
    "${OVERLAY_ROOT}/u_edf_p_no_pg" \
    "${OVERLAY_ROOT}/u_mux_2" \
    "${OVERLAY_ROOT}/u_mux_2_1_inv" \
    "${OVERLAY_ROOT}/u_mux_4"

cat > "${OVERLAY_ROOT}/u_vpwr_vgnd/sky130_fd_sc_hs__u_vpwr_vgnd.v" <<'SKY130_STUB'
`ifndef SKY130_FD_SC_HS__U_VPWR_VGND_STUB_V
`define SKY130_FD_SC_HS__U_VPWR_VGND_STUB_V
module sky130_fd_sc_hs__u_vpwr_vgnd (X, A, VPWR, VGND);
    output X; input A, VPWR, VGND;
    assign X = A;
endmodule
`endif
SKY130_STUB

cat > "${OVERLAY_ROOT}/u_df_p_pg/sky130_fd_sc_hs__u_df_p_pg.v" <<'SKY130_STUB'
`ifndef SKY130_FD_SC_HS__U_DF_P_PG_STUB_V
`define SKY130_FD_SC_HS__U_DF_P_PG_STUB_V
module sky130_fd_sc_hs__u_df_p_pg (Q, D, CLK, VPWR, VGND);
    output reg Q; input D, CLK, VPWR, VGND;
    initial Q = 1'b0;
    always @(posedge CLK) Q <= D;
endmodule
`endif
SKY130_STUB

cat > "${OVERLAY_ROOT}/u_df_p_no_pg/sky130_fd_sc_hs__u_df_p_no_pg.v" <<'SKY130_STUB'
`ifndef SKY130_FD_SC_HS__U_DF_P_NO_PG_STUB_V
`define SKY130_FD_SC_HS__U_DF_P_NO_PG_STUB_V
module sky130_fd_sc_hs__u_df_p_no_pg (Q, D, CLK, notifier, VPWR, VGND);
    output reg Q; input D, CLK, notifier, VPWR, VGND;
    initial Q = 1'b0;
    always @(posedge CLK) Q <= D;
endmodule
`endif
SKY130_STUB

cat > "${OVERLAY_ROOT}/u_df_p_r_pg/sky130_fd_sc_hs__u_df_p_r_pg.v" <<'SKY130_STUB'
`ifndef SKY130_FD_SC_HS__U_DF_P_R_PG_STUB_V
`define SKY130_FD_SC_HS__U_DF_P_R_PG_STUB_V
module sky130_fd_sc_hs__u_df_p_r_pg (Q, D, CLK, RESET, VPWR, VGND);
    output reg Q; input D, CLK, RESET, VPWR, VGND;
    initial Q = 1'b0;
    always @(posedge CLK or posedge RESET) begin
        if (RESET) Q <= 1'b0; else Q <= D;
    end
endmodule
`endif
SKY130_STUB

cat > "${OVERLAY_ROOT}/u_df_p_r_no_pg/sky130_fd_sc_hs__u_df_p_r_no_pg.v" <<'SKY130_STUB'
`ifndef SKY130_FD_SC_HS__U_DF_P_R_NO_PG_STUB_V
`define SKY130_FD_SC_HS__U_DF_P_R_NO_PG_STUB_V
module sky130_fd_sc_hs__u_df_p_r_no_pg (Q, D, CLK, RESET, notifier, VPWR, VGND);
    output reg Q; input D, CLK, RESET, notifier, VPWR, VGND;
    initial Q = 1'b0;
    always @(posedge CLK or posedge RESET) begin
        if (RESET) Q <= 1'b0; else Q <= D;
    end
endmodule
`endif
SKY130_STUB

cat > "${OVERLAY_ROOT}/u_df_p_s_pg/sky130_fd_sc_hs__u_df_p_s_pg.v" <<'SKY130_STUB'
`ifndef SKY130_FD_SC_HS__U_DF_P_S_PG_STUB_V
`define SKY130_FD_SC_HS__U_DF_P_S_PG_STUB_V
module sky130_fd_sc_hs__u_df_p_s_pg (Q, D, CLK, SET, VPWR, VGND);
    output reg Q; input D, CLK, SET, VPWR, VGND;
    initial Q = 1'b0;
    always @(posedge CLK or posedge SET) begin
        if (SET) Q <= 1'b1; else Q <= D;
    end
endmodule
`endif
SKY130_STUB

cat > "${OVERLAY_ROOT}/u_df_p_s_no_pg/sky130_fd_sc_hs__u_df_p_s_no_pg.v" <<'SKY130_STUB'
`ifndef SKY130_FD_SC_HS__U_DF_P_S_NO_PG_STUB_V
`define SKY130_FD_SC_HS__U_DF_P_S_NO_PG_STUB_V
module sky130_fd_sc_hs__u_df_p_s_no_pg (Q, D, CLK, SET, notifier, VPWR, VGND);
    output reg Q; input D, CLK, SET, notifier, VPWR, VGND;
    initial Q = 1'b0;
    always @(posedge CLK or posedge SET) begin
        if (SET) Q <= 1'b1; else Q <= D;
    end
endmodule
`endif
SKY130_STUB

cat > "${OVERLAY_ROOT}/u_dfb_setdom_pg/sky130_fd_sc_hs__u_dfb_setdom_pg.v" <<'SKY130_STUB'
`ifndef SKY130_FD_SC_HS__U_DFB_SETDOM_PG_STUB_V
`define SKY130_FD_SC_HS__U_DFB_SETDOM_PG_STUB_V
module sky130_fd_sc_hs__u_dfb_setdom_pg (Q, SET, RESET, CLK, D, VPWR, VGND);
    output reg Q; input SET, RESET, CLK, D, VPWR, VGND;
    initial Q = 1'b0;
    always @(posedge CLK or posedge SET or posedge RESET) begin
        if (SET) Q <= 1'b1; else if (RESET) Q <= 1'b0; else Q <= D;
    end
endmodule
`endif
SKY130_STUB

cat > "${OVERLAY_ROOT}/u_dfb_setdom_notify_pg/sky130_fd_sc_hs__u_dfb_setdom_notify_pg.v" <<'SKY130_STUB'
`ifndef SKY130_FD_SC_HS__U_DFB_SETDOM_NOTIFY_PG_STUB_V
`define SKY130_FD_SC_HS__U_DFB_SETDOM_NOTIFY_PG_STUB_V
module sky130_fd_sc_hs__u_dfb_setdom_notify_pg (Q, SET, RESET, CLK, D, notifier, VPWR, VGND);
    output reg Q; input SET, RESET, CLK, D, notifier, VPWR, VGND;
    initial Q = 1'b0;
    always @(posedge CLK or posedge SET or posedge RESET) begin
        if (SET) Q <= 1'b1; else if (RESET) Q <= 1'b0; else Q <= D;
    end
endmodule
`endif
SKY130_STUB

cat > "${OVERLAY_ROOT}/u_dl_p_pg/sky130_fd_sc_hs__u_dl_p_pg.v" <<'SKY130_STUB'
`ifndef SKY130_FD_SC_HS__U_DL_P_PG_STUB_V
`define SKY130_FD_SC_HS__U_DL_P_PG_STUB_V
module sky130_fd_sc_hs__u_dl_p_pg (Q, D, GATE, VPWR, VGND);
    output reg Q; input D, GATE, VPWR, VGND;
    initial Q = 1'b0;
    always @* if (GATE) Q = D;
endmodule
`endif
SKY130_STUB

cat > "${OVERLAY_ROOT}/u_dl_p_no_pg/sky130_fd_sc_hs__u_dl_p_no_pg.v" <<'SKY130_STUB'
`ifndef SKY130_FD_SC_HS__U_DL_P_NO_PG_STUB_V
`define SKY130_FD_SC_HS__U_DL_P_NO_PG_STUB_V
module sky130_fd_sc_hs__u_dl_p_no_pg (Q, D, GATE, notifier, VPWR, VGND);
    output reg Q; input D, GATE, notifier, VPWR, VGND;
    initial Q = 1'b0;
    always @* if (GATE) Q = D;
endmodule
`endif
SKY130_STUB

cat > "${OVERLAY_ROOT}/u_dl_p_r_pg/sky130_fd_sc_hs__u_dl_p_r_pg.v" <<'SKY130_STUB'
`ifndef SKY130_FD_SC_HS__U_DL_P_R_PG_STUB_V
`define SKY130_FD_SC_HS__U_DL_P_R_PG_STUB_V
module sky130_fd_sc_hs__u_dl_p_r_pg (Q, D, GATE, RESET, VPWR, VGND);
    output reg Q; input D, GATE, RESET, VPWR, VGND;
    initial Q = 1'b0;
    always @* begin
        if (RESET) Q = 1'b0; else if (GATE) Q = D;
    end
endmodule
`endif
SKY130_STUB

cat > "${OVERLAY_ROOT}/u_dl_p_r_no_pg/sky130_fd_sc_hs__u_dl_p_r_no_pg.v" <<'SKY130_STUB'
`ifndef SKY130_FD_SC_HS__U_DL_P_R_NO_PG_STUB_V
`define SKY130_FD_SC_HS__U_DL_P_R_NO_PG_STUB_V
module sky130_fd_sc_hs__u_dl_p_r_no_pg (Q, D, GATE, RESET, notifier, VPWR, VGND);
    output reg Q; input D, GATE, RESET, notifier, VPWR, VGND;
    initial Q = 1'b0;
    always @* begin
        if (RESET) Q = 1'b0; else if (GATE) Q = D;
    end
endmodule
`endif
SKY130_STUB

cat > "${OVERLAY_ROOT}/u_edf_p_pg/sky130_fd_sc_hs__u_edf_p_pg.v" <<'SKY130_STUB'
`ifndef SKY130_FD_SC_HS__U_EDF_P_PG_STUB_V
`define SKY130_FD_SC_HS__U_EDF_P_PG_STUB_V
module sky130_fd_sc_hs__u_edf_p_pg (Q, D, CLK, DE, VPWR, VGND);
    output reg Q; input D, CLK, DE, VPWR, VGND;
    initial Q = 1'b0;
    always @(posedge CLK) if (DE) Q <= D;
endmodule
`endif
SKY130_STUB

cat > "${OVERLAY_ROOT}/u_edf_p_no_pg/sky130_fd_sc_hs__u_edf_p_no_pg.v" <<'SKY130_STUB'
`ifndef SKY130_FD_SC_HS__U_EDF_P_NO_PG_STUB_V
`define SKY130_FD_SC_HS__U_EDF_P_NO_PG_STUB_V
module sky130_fd_sc_hs__u_edf_p_no_pg (Q, D, CLK, DE, notifier, VPWR, VGND);
    output reg Q; input D, CLK, DE, notifier, VPWR, VGND;
    initial Q = 1'b0;
    always @(posedge CLK) if (DE) Q <= D;
endmodule
`endif
SKY130_STUB

cat > "${OVERLAY_ROOT}/u_mux_2/sky130_fd_sc_hs__u_mux_2.v" <<'SKY130_STUB'
`ifndef SKY130_FD_SC_HS__U_MUX_2_STUB_V
`define SKY130_FD_SC_HS__U_MUX_2_STUB_V
module sky130_fd_sc_hs__u_mux_2_1 (X, A0, A1, S);
    output X; input A0, A1, S;
    assign X = S ? A1 : A0;
endmodule
module sky130_fd_sc_hs__u_mux_2_2 (X, A0, A1, S);
    output X; input A0, A1, S;
    assign X = S ? A1 : A0;
endmodule
module sky130_fd_sc_hs__u_mux_2_4 (X, A0, A1, S);
    output X; input A0, A1, S;
    assign X = S ? A1 : A0;
endmodule
`endif
SKY130_STUB

cat > "${OVERLAY_ROOT}/u_mux_2_1_inv/sky130_fd_sc_hs__u_mux_2_1_inv.v" <<'SKY130_STUB'
`ifndef SKY130_FD_SC_HS__U_MUX_2_1_INV_STUB_V
`define SKY130_FD_SC_HS__U_MUX_2_1_INV_STUB_V
module sky130_fd_sc_hs__u_mux_2_1_inv (Y, A0, A1, S);
    output Y; input A0, A1, S;
    assign Y = ~(S ? A1 : A0);
endmodule
`endif
SKY130_STUB

cat > "${OVERLAY_ROOT}/u_mux_4/sky130_fd_sc_hs__u_mux_4.v" <<'SKY130_STUB'
`ifndef SKY130_FD_SC_HS__U_MUX_4_STUB_V
`define SKY130_FD_SC_HS__U_MUX_4_STUB_V
module sky130_fd_sc_hs__u_mux_4_1 (X, A0, A1, A2, A3, S0, S1);
    output X; input A0, A1, A2, A3, S0, S1;
    assign X = S1 ? (S0 ? A3 : A2) : (S0 ? A1 : A0);
endmodule
module sky130_fd_sc_hs__u_mux_4_2 (X, A0, A1, A2, A3, S0, S1);
    output X; input A0, A1, A2, A3, S0, S1;
    assign X = S1 ? (S0 ? A3 : A2) : (S0 ? A1 : A0);
endmodule
module sky130_fd_sc_hs__u_mux_4_4 (X, A0, A1, A2, A3, S0, S1);
    output X; input A0, A1, A2, A3, S0, S1;
    assign X = S1 ? (S0 ? A3 : A2) : (S0 ? A1 : A0);
endmodule
`endif
SKY130_STUB

generate_timing_strength_model() {
    local mod="$1"
    local cell="$2"
    local behavioral_file="$3"
    local specify_file="$4"
    local out_file="$5"
    local base_mod="sky130_fd_sc_hs__${cell}"
    local guard
    local need_awake=0
    local need_cond0=0
    local need_cond1=0
    local need_resetb=0
    local need_setb=0

    guard="$(printf '%s_TIMING_V' "${mod}" | tr '[:lower:]' '[:upper:]')"
    if [ -f "${specify_file}" ]; then
        if grep -Eq '(^|[^A-Za-z0-9_])AWAKE([^A-Za-z0-9_]|$)' "${specify_file}" && grep -Eq 'wire[[:space:]]+awake' "${behavioral_file}"; then
            need_awake=1
        fi
        if grep -Eq '(^|[^A-Za-z0-9_])COND0([^A-Za-z0-9_]|$)' "${specify_file}" && grep -Eq 'wire[[:space:]]+cond0' "${behavioral_file}"; then
            need_cond0=1
        fi
        if grep -Eq '(^|[^A-Za-z0-9_])COND1([^A-Za-z0-9_]|$)' "${specify_file}" && grep -Eq 'wire[[:space:]]+cond1' "${behavioral_file}"; then
            need_cond1=1
        fi
        if grep -Eq '(^|[^A-Za-z0-9_])RESETB_delayed([^A-Za-z0-9_]|$)' "${specify_file}" && grep -Eq 'RESET_B_delayed' "${behavioral_file}"; then
            need_resetb=1
        fi
        if grep -Eq '(^|[^A-Za-z0-9_])SETB_delayed([^A-Za-z0-9_]|$)' "${specify_file}" && grep -Eq 'SET_B_delayed' "${behavioral_file}"; then
            need_setb=1
        fi
    else
        specify_file=""
    fi

    awk \
        -v base_mod="${base_mod}" \
        -v strength_mod="${mod}" \
        -v guard="${guard}" \
        -v specify_file="${specify_file}" \
        -v need_awake="${need_awake}" \
        -v need_cond0="${need_cond0}" \
        -v need_cond1="${need_cond1}" \
        -v need_resetb="${need_resetb}" \
        -v need_setb="${need_setb}" \
        -v cell="${cell}" \
        '
        function print_specify(    spec_line) {
            if (inserted_specify) {
                return
            }
            if (need_awake || need_cond0 || need_cond1 || need_resetb || need_setb) {
                print ""
                print "    // Local aliases for condition names used by the PDK specify block."
                if (need_awake) {
                    print "    wire AWAKE;"
                    print "    assign AWAKE = awake;"
                }
                if (need_cond0) {
                    print "    wire COND0;"
                    print "    assign COND0 = cond0;"
                }
                if (need_cond1) {
                    print "    wire COND1;"
                    print "    assign COND1 = cond1;"
                }
                if (need_resetb) {
                    print "    wire RESETB_delayed;"
                    print "    assign RESETB_delayed = RESET_B_delayed;"
                }
                if (need_setb) {
                    print "    wire SETB_delayed;"
                    print "    assign SETB_delayed = SET_B_delayed;"
                }
            }
            if (specify_file != "") {
                print ""
                while ((getline spec_line < specify_file) > 0) {
                    print spec_line
                }
                close(specify_file)
            }
            inserted_specify = 1
        }

        {
            gsub(/SKY130_FD_SC_HS__[A-Z0-9_]+_BEHAVIORAL_V/, guard)
            if ($0 ~ ("module[[:space:]]+" base_mod "[[:space:]]*\\(")) {
                sub("module[[:space:]]+" base_mod "[[:space:]]*\\(", "module " strength_mod " (")
                in_port_list = 1
                print
                next
            }
            if (in_port_list) {
                if ($0 ~ /^[[:space:]]*\);/) {
                    if (port_prev != "") {
                        sub(/[[:space:]]*,[[:space:]]*$/, "", port_prev)
                        print port_prev
                        port_prev = ""
                    }
                    print
                    in_port_list = 0
                    next
                }
                if ($0 ~ /^[[:space:]]*(VPWR|VGND)[[:space:]]*,?[[:space:]]*$/) {
                    next
                }
                if (port_prev != "") {
                    print port_prev
                }
                port_prev = $0
                next
            }
            if ($0 ~ /^[[:space:]]*input[[:space:]]+VPWR[[:space:]]*;/ || $0 ~ /^[[:space:]]*input[[:space:]]+VGND[[:space:]]*;/) {
                next
            }
            if (!inserted_supply && $0 ~ /^[[:space:]]*\/\/ Local signals/) {
                print "    // Voltage supply signals"
                print "    supply1 VPWR;"
                print "    supply0 VGND;"
                print ""
                inserted_supply = 1
            }
            if ($0 ~ /^[[:space:]]*endmodule[[:space:]]*$/) {
                if (!inserted_supply) {
                    print "    // Voltage supply signals"
                    print "    supply1 VPWR;"
                    print "    supply0 VGND;"
                    print ""
                    inserted_supply = 1
                }
                print_specify()
            }
            print
        }
        ' "${behavioral_file}" \
        | sed -E 's/^([[:space:]]*wire[[:space:]]+)[A-Za-z][A-Za-z0-9_]*[[:space:]]+([A-Za-z_][A-Za-z0-9_]*[[:space:]]*;)/\1\2/' \
        > "${out_file}"
}

SKY130_FILELIST="${BUILD_DIR}/sky130_used_cells.f"
SKY130_MISSING="${BUILD_DIR}/sky130_missing_cells.txt"
SKY130_MISSING_SPECIFY="${BUILD_DIR}/sky130_missing_specify_cells.txt"
SKY130_TIMING_ALIAS_LOG="${BUILD_DIR}/sky130_timing_aliases.txt"
: > "${SKY130_FILELIST}"
: > "${SKY130_MISSING}"
: > "${SKY130_MISSING_SPECIFY}"
: > "${SKY130_TIMING_ALIAS_LOG}"

grep -o 'sky130_fd_sc_hs__[A-Za-z0-9_]*' "${NETLIST}" | sort -u | while read -r mod; do
    cell="${mod#sky130_fd_sc_hs__}"
    cell="$(printf '%s\n' "${cell}" | sed -E 's/_[0-9]+$//')"
    cell_file="${SKY130_CELL_ROOT}/${cell}/${mod}.v"
    behavioral_file="${SKY130_CELL_ROOT}/${cell}/sky130_fd_sc_hs__${cell}.behavioral.v"
    specify_file="${SKY130_CELL_ROOT}/${cell}/sky130_fd_sc_hs__${cell}.specify.v"
    if [ "${POST_SYNTH_CELL_MODEL}" = "timing" ] && [ -f "${cell_file}" ] && [ -f "${behavioral_file}" ]; then
        overlay_dir="${OVERLAY_ROOT}/${cell}"
        mkdir -p "${overlay_dir}"
        timing_file="${overlay_dir}/${mod}.timing.v"
        generate_timing_strength_model "${mod}" "${cell}" "${behavioral_file}" "${specify_file}" "${timing_file}"
        printf '%s\n' "${timing_file}" >> "${SKY130_FILELIST}"
        if [ ! -f "${specify_file}" ]; then
            printf '%s\n' "${mod}" >> "${SKY130_MISSING_SPECIFY}"
        fi
        if grep -Eq 'wire[[:space:]]+(AWAKE|COND0|COND1|RESETB_delayed|SETB_delayed)' "${timing_file}"; then
            grep -E 'wire[[:space:]]+(AWAKE|COND0|COND1|RESETB_delayed|SETB_delayed)' "${timing_file}" \
                | sed "s#^#${mod}: #" >> "${SKY130_TIMING_ALIAS_LOG}"
        fi
    elif [ "${POST_SYNTH_CELL_MODEL}" = "functional" ] && [ -f "${cell_file}" ]; then
        overlay_dir="${OVERLAY_ROOT}/${cell}"
        mkdir -p "${overlay_dir}"
        find "${SKY130_CELL_ROOT}/${cell}" -maxdepth 1 -type f -name '*.v' | while read -r src_model; do
            sed -E 's/^([[:space:]]*wire[[:space:]]+)[A-Za-z][A-Za-z0-9_]*[[:space:]]+([A-Za-z_][A-Za-z0-9_]*[[:space:]]*;)/\1\2/' \
                "${src_model}" > "${overlay_dir}/$(basename "${src_model}")"
        done
        printf '%s\n' "${overlay_dir}/$(basename "${cell_file}")" >> "${SKY130_FILELIST}"
    else
        printf '%s\n' "${mod}" >> "${SKY130_MISSING}"
    fi
done

if [ -s "${SKY130_MISSING}" ]; then
    echo "ERROR: missing Sky130 HS cell wrapper files. See ${SKY130_MISSING}" >&2
    exit 1
fi
if [ "${POST_SYNTH_CELL_MODEL}" = "timing" ] && [ -s "${SKY130_MISSING_SPECIFY}" ]; then
    echo "WARNING: some generated timing models have no PDK specify file. See ${SKY130_MISSING_SPECIFY}" >&2
fi

INCDIR_OPTS=(
    "+incdir+${PROJECT_ROOT}/rtl/include"
    "+incdir+${OVERLAY_ROOT}/anchor"
)
while read -r cell_file; do
    INCDIR_OPTS+=("+incdir+$(dirname "${cell_file}")")
done < "${SKY130_FILELIST}"

case "${TB_KIND}" in
    system)
        TB_FILES=(
            "${PROJECT_ROOT}/tb/unit_tb/axi4_slave_mem.sv"
            "${PROJECT_ROOT}/tb/unit_tb/system_tb.sv"
        )
        TOP="system_tb"
        ;;
    verification|vip)
        TB_FILES=(
            "${PROJECT_ROOT}/rtl/exp_approx_unit.sv"
            "${PROJECT_ROOT}/tb/unit_tb/axi4_slave_mem.sv"
            "${PROJECT_ROOT}/tb/verification/fa_axi_vip_lite.sv"
            "${PROJECT_ROOT}/tb/verification/fa_verification_tb.sv"
        )
        TOP="fa_verification_tb"
        ;;
    *)
        echo "ERROR: unsupported POST_SYNTH_TB=${TB_KIND}; use system or verification." >&2
        exit 1
        ;;
esac

if [ -z "${SDF_SCOPE}" ]; then
    SDF_SCOPE="${TOP}.dut"
fi

SDF_COMPILE_ARGS=()
if [ "${POST_SYNTH_SDF}" = "1" ]; then
    SDF_COMPILE_ARGS=(-sdf "${SDF_MODE}:${SDF_SCOPE}:${SDF_FILE}" +sdfverbose +maxdelays)
fi

VCS_DEFINE_ARGS=(+define+SIMULATION +define+GATE_SIM +define+UNIT_DELAY=)
if [ "${POST_SYNTH_CELL_MODEL}" = "functional" ]; then
    VCS_DEFINE_ARGS+=(+define+FUNCTIONAL)
fi

SIM_ARGS=()
if [ "${POST_SYNTH_SDF}" != "1" ]; then
    SIM_ARGS+=(+notimingcheck)
else
    if [[ " ${POST_SYNTH_SIM_ARGS:-} " != *"+FA_CLK_HALF_NS="* ]]; then
        SIM_ARGS+=("+FA_CLK_HALF_NS=${SDF_CLK_HALF_NS}")
    fi
fi
if [ -n "${POST_SYNTH_SIM_ARGS:-}" ]; then
    # Intentionally split user-supplied runtime plusargs/options.
    # shellcheck disable=SC2206
    EXTRA_SIM_ARGS=(${POST_SYNTH_SIM_ARGS})
    SIM_ARGS+=("${EXTRA_SIM_ARGS[@]}")
fi

echo "================================================"
echo " FlashAttention post-synthesis simulation - VCS"
echo "================================================"
echo "Project root : ${PROJECT_ROOT}"
echo "Build dir    : ${BUILD_DIR}"
echo "Netlist      : ${NETLIST}"
echo "Cell root    : ${SKY130_CELL_ROOT}"
echo "Cell model   : ${POST_SYNTH_CELL_MODEL}"
echo "Overlay      : ${OVERLAY_ROOT%/cells}"
echo "TB           : ${TB_KIND}"
echo "Top          : ${TOP}"
echo "SDF enabled  : ${POST_SYNTH_SDF}"
if [ "${POST_SYNTH_SDF}" = "1" ]; then
    if [ "${POST_SYNTH_NORMALIZE_SKY130_SDF}" = "1" ]; then
        echo "SDF original : ${SDF_ORIGINAL_FILE}"
        echo "SDF file     : ${SDF_FILE}"
        echo "SDF norm rpt : ${SDF_NORMALIZATION_REPORT}"
        echo "SDF async    : ${POST_SYNTH_NORMALIZE_SKY130_SDF_ASYNC}"
    else
        echo "SDF file     : ${SDF_FILE}"
    fi
    echo "SDF scope    : ${SDF_SCOPE}"
    echo "SDF mode     : ${SDF_MODE}"
    echo "SDF clk half : ${SDF_CLK_HALF_NS} ns"
fi
echo ""

if [ "${POST_SYNTH_SDF}" = "1" ]; then
    echo "[1/2] Compiling SDF gate simulation..."
else
    echo "[1/2] Compiling no-SDF gate simulation..."
fi
"${VCS_BIN}" -full64 -sverilog \
    "${INCDIR_OPTS[@]}" \
    "${VCS_DEFINE_ARGS[@]}" \
    -timescale=1ns/1ps \
    -top "${TOP}" \
    "${SDF_COMPILE_ARGS[@]}" \
    -f "${SKY130_FILELIST}" \
    "${NETLIST}" \
    "${TB_FILES[@]}" \
    +neg_tchk \
    -Mdir="${BUILD_DIR}/csrc" \
    -o "${BUILD_DIR}/post_synth_simv" \
    -l "${BUILD_DIR}/compile.log" \
    2>&1 | tee "${BUILD_DIR}/compile.stdout"

echo ""
if [ "${POST_SYNTH_SDF}" = "1" ]; then
    echo "[2/2] Running SDF gate simulation..."
else
    echo "[2/2] Running no-SDF gate simulation..."
fi
"${BUILD_DIR}/post_synth_simv" "${SIM_ARGS[@]}" \
    -l "${BUILD_DIR}/sim.log" \
    2>&1 | tee "${BUILD_DIR}/sim.stdout"

echo ""
echo "================================================"
echo " Post-synthesis simulation complete"
echo " Compile log    : ${BUILD_DIR}/compile.log"
echo " Simulation log : ${BUILD_DIR}/sim.log"
echo "================================================"
