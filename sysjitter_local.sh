#!/bin/bash
#
# sysjitter_local.sh
#
# Run sysjitter on this host and upload the raw results to the report server.
#
# sysjitter runs a busy thread on each selected CPU core and records every
# time that thread is interrupted (by the kernel, IRQs, other tasks, etc.).
# Cores with fewer and shorter interruptions are the best choices for pinning
# latency-sensitive trading threads.
#
# How it works:
#   1. Runs /usr/bin/sysjitter on the cores given with --cores.
#   2. Saves the output to /tmp/sysjitter/<YYYYmmdd>/<host>-sysjitter-<YYYYmmdd>.
#   3. Adds the report server's SSH host key to /root/.ssh/known_hosts if it
#      is not already there.
#   4. Uploads the file with sftp to report-dropper@cha-slp-admin01 in
#      /sysjitter/<YYYYmmdd>/, creating that directory if needed.
#
# This script does not build the HTML report. report_sysjitter.sh does that
# from the uploaded files.
#
# Options:
#   --cores, -c      Cores to test, e.g. 5,7,9-13 (required)
#   --threshold, -t  Ignore interruptions shorter than this many ns (default: 200)
#   --runtime, -r    How long to run, in seconds. If not given, sysjitter's own
#                    default is used.
#
# Requirements:
#   - Run as root (writes to /root/.ssh/known_hosts).
#   - /usr/bin/sysjitter installed.
#   - SSH key access to report-dropper@cha-slp-admin01.
#
# Notes:
#   - Keep the tested cores idle during the run, or the results will include
#     interruptions from your own workload.
#   - Running it again on the same day overwrites that day's file.
#
# Usage:
#   sudo ./sysjitter_local.sh --cores 5,7,9-13 [--threshold 500] [--runtime 120]
#

set -euo pipefail

usage() {
    echo "Usage: $0 --cores <core_list> [--threshold <nsec>] [--runtime <sec>]" >&2
    echo "  --cores      Comma-separated list of cores and/or ranges (required)" >&2
    echo "  --threshold  Ignore interruptions shorter than this many nanoseconds (default: 200)" >&2
    echo "  --runtime    How long to run in seconds (default: 70)" >&2
    echo "  Example: $0 --cores 5,7,9-13 --threshold 500 --runtime 120" >&2
    exit 1
}

# Script variables
CORES=""
THRESHOLD=200
RUNTIME=""
REPORT_USER="report-dropper"
REPORT_HOST="cha-slp-admin01"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cores|-c)     CORES="$2";     shift 2 ;;
        --threshold|-t) THRESHOLD="$2"; shift 2 ;;
        --runtime|-r)   RUNTIME="$2";   shift 2 ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done

[[ -z "$CORES" ]] && usage

[[ -x /usr/bin/sysjitter ]] || { echo "ERROR: /usr/bin/sysjitter not found or not executable" >&2; exit 1; }

HOSTNAME=$(hostname -s)
TIMESTAMP=$(date +%Y%m%d)
OUTPUT_DIR="/tmp/sysjitter/${TIMESTAMP}"
RAW_FILE="${OUTPUT_DIR}/${HOSTNAME}-sysjitter-${TIMESTAMP}"
REPORT_PATH="/sysjitter/${TIMESTAMP}/"

mkdir -p "${OUTPUT_DIR}"

SYSJITTER_CMD="/usr/bin/sysjitter --cores ${CORES}"
[[ -n "$RUNTIME" ]] && SYSJITTER_CMD+=" --runtime ${RUNTIME}"
SYSJITTER_CMD+=" ${THRESHOLD}"

${SYSJITTER_CMD} > "${RAW_FILE}" 2>&1

echo "Raw output: ${RAW_FILE}"

if ! ssh-keygen -F "${REPORT_HOST}" > /dev/null 2>&1; then
    echo "Adding ${REPORT_HOST} to known_hosts"
    ssh-keyscan "${REPORT_HOST}" >> /root/.ssh/known_hosts
fi

echo "mkdir ${REPORT_PATH}" | sftp "${REPORT_USER}@${REPORT_HOST}" 2>/dev/null || true
echo "put ${RAW_FILE} ${REPORT_PATH}" | sftp "${REPORT_USER}@${REPORT_HOST}"
echo "Transferred ${RAW_FILE} to ${REPORT_USER}@${REPORT_HOST}:${REPORT_PATH}"
