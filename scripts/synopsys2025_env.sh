#!/usr/bin/env bash
# Source this file before running VCS/DC on the Synopsys 2025 server.

export SNPS2025_ROOT="${SNPS2025_ROOT:-/eda/synopsys2025}"

if [ -d "${SNPS2025_ROOT}/vcs/X-2025.06" ]; then
    export VCS_HOME="${VCS_HOME:-${SNPS2025_ROOT}/vcs/X-2025.06}"
fi

if [ -d "${SNPS2025_ROOT}/syn/X-2025.06-SP4" ]; then
    export SYNOPSYS="${SYNOPSYS:-${SNPS2025_ROOT}/syn/X-2025.06-SP4}"
fi

if [ -f /eda/license/Synopsys.dat ]; then
    export SNPSLMD_LICENSE_FILE="${SNPSLMD_LICENSE_FILE:-/eda/license/Synopsys.dat}"
    export LM_LICENSE_FILE="${LM_LICENSE_FILE:-${SNPSLMD_LICENSE_FILE}}"
fi

prepend_path() {
    case ":${PATH}:" in
        *":$1:"*) ;;
        *) PATH="$1:${PATH}" ;;
    esac
}

if [ -n "${VCS_HOME:-}" ] && [ -d "${VCS_HOME}/bin" ]; then
    prepend_path "${VCS_HOME}/bin"
fi

if [ -n "${SYNOPSYS:-}" ] && [ -d "${SYNOPSYS}/bin" ]; then
    prepend_path "${SYNOPSYS}/bin"
fi

export PATH
