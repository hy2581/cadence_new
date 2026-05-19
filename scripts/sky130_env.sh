#!/usr/bin/env bash
# Sky130 standard-cell library defaults for DC 2025.

export SKY130_HOME="${SKY130_HOME:-${HOME}/pdk_download}"
export SKY130_LIB_NAME="${SKY130_LIB_NAME:-sky130_fd_sc_hd}"
export SKY130_CORNER="${SKY130_CORNER:-tt_025C_1v80}"

SKY130_HS_DEFAULT="${HOME}/cadence_codex_run_20260430_2114/pdk/sky130_fd_sc_hs/db/sky130_fd_sc_hs__tt_025C_1v80_noccsn.db"
SKY130_HD_DEFAULT="${SKY130_HOME}/sky130_hd_v3.db"

if [ -z "${SKY130_TARGET_LIB:-}" ]; then
    if [ -f "${SKY130_HS_DEFAULT}" ]; then
        export SKY130_LIB_NAME="sky130_fd_sc_hs"
        export SKY130_TARGET_LIB="${SKY130_HS_DEFAULT}"
    else
        export SKY130_TARGET_LIB="${SKY130_HD_DEFAULT}"
    fi
fi

if [ -f "${SKY130_TARGET_LIB}" ]; then
    export DC_TARGET_LIB="${DC_TARGET_LIB:-${SKY130_TARGET_LIB}}"
    export DC_PROCESS="${DC_PROCESS:-sky130}"
    export DC_CLOCK_PERIOD="${DC_CLOCK_PERIOD:-10.0}"
    export DC_INPUT_DELAY="${DC_INPUT_DELAY:-1.0}"
    export DC_OUTPUT_DELAY="${DC_OUTPUT_DELAY:-1.0}"
    export DC_MAX_TRANSITION="${DC_MAX_TRANSITION:-1.0}"
fi
