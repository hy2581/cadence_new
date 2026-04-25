#!/usr/bin/env bash
# TSMC 12nm standard-cell library defaults for DC 2025.

export TSMCHOME="${TSMCHOME:-${HOME}/lib_new/TSMCHOME}"
export TSMC12_LIB_NAME="${TSMC12_LIB_NAME:-tcbn12ffcllbwp6t16p96cpd}"
export TSMC12_LIB_REV="${TSMC12_LIB_REV:-120a}"
export TSMC12_CORNER="${TSMC12_CORNER:-ssgnp0p72v125c}"
export TSMC12_LIB_DIR="${TSMC12_LIB_DIR:-${TSMCHOME}/digital/Front_End/timing_power_noise/NLDM/${TSMC12_LIB_NAME}_${TSMC12_LIB_REV}}"
export TSMC12_TARGET_LIB="${TSMC12_TARGET_LIB:-${TSMC12_LIB_DIR}/${TSMC12_LIB_NAME}${TSMC12_CORNER}.db}"

if [ -f "${TSMC12_TARGET_LIB}" ]; then
    export DC_TARGET_LIB="${DC_TARGET_LIB:-${TSMC12_TARGET_LIB}}"
fi
