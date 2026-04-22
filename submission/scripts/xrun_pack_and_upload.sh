#!/bin/bash
# ============================================================
# Client-side helper: pack submission/ (RTL + TB + scripts) into
# a small tarball and upload it to the Cadence Cloud FILES tab.
#
# Run from the repo root:
#   bash submission/scripts/xrun_pack_and_upload.sh
#
# Produces /tmp/submission_xrun.tar.gz, uploads it as
# submission_xrun.tar.gz. Then on the remote side run:
#   cd /tmp && rm -rf submission \
#     && tar xzf "$HOME/neere/Start Mate Desktop/submission_xrun.tar.gz" \
#     && cd submission && nohup bash scripts/xrun_remote_driver.sh \
#        > /tmp/xrun_outer.log 2>&1 & echo PID=$!
# ============================================================
set -eu
cd "$(dirname "$0")/../.."   # repo root

TARBALL=/tmp/submission_xrun.tar.gz
REMOTE_NAME=submission_xrun.tar.gz

# Pack submission/ — exclude huge/binary artefacts that are not needed on the remote.
tar --exclude='submission/baseline/docs' \
    --exclude='submission/scripts/run_gate_rerun.sh' \
    --exclude='submission/*.docx' \
    --exclude='submission/*.md.bak' \
    -czf "$TARBALL" \
    submission/baseline submission/bonus submission/scripts
ls -lh "$TARBALL"

# Upload (cadence_runner.upload auto-removes existing file with the same name).
python3 tools/cadence_runner.py rm "$REMOTE_NAME" 2>/dev/null || true
python3 tools/cadence_runner.py upload "$TARBALL"

echo "Uploaded $TARBALL as $REMOTE_NAME. Now trigger the remote driver via cadence_runner.py exec."
