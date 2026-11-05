#!/usr/bin/env bash
# scan_hosts.sh
# Scans SSH host keys and appends them to ~/.ssh/known_hosts, skipping duplicates.
# Usage:
#   ./scan_hosts.sh -f <host_file>    # reads from a file
#   ./scan_hosts.sh web01             # scans a single host
#   ./scan_hosts.sh web01 web02 web03 # scans multiple hosts
set -euo pipefail

readonly KNOWN_HOSTS="${HOME}/.ssh/known_hosts"

usage() {
  echo "Usage: $0 -f <host_file>" >&2
  echo "       $0 <host1> [host2 ...]" >&2
  exit 1
}

# --- Resolve host list ---
arrHostList=()

if [[ $# -eq 0 ]]; then
  echo "Error: No hosts or file provided." >&2
  usage
fi

if [[ "$1" == "-f" ]]; then
  [[ $# -lt 2 ]] && { echo "Error: -f requires a filename argument." >&2; usage; }

  host_file="$2"

  if [[ ! -f "$host_file" ]]; then
    echo "Error: File '$host_file' not found." >&2
    exit 1
  fi

  if [[ ! -r "$host_file" ]]; then
    echo "Error: File '$host_file' is not readable." >&2
    exit 1
  fi

  readarray -t arrHostList < "$host_file"
else
  arrHostList=("$@")
fi

if [[ ${#arrHostList[@]} -eq 0 ]]; then
  echo "Error: Host list is empty." >&2
  exit 1
fi

# --- Ensure ~/.ssh exists with correct permissions ---
mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"
touch "$KNOWN_HOSTS"
chmod 600 "$KNOWN_HOSTS"

# --- Scan ---
for host in "${arrHostList[@]}"; do
  # Skip blank lines and comments
  [[ -z "$host" || "$host" == \#* ]] && continue

  echo "Scanning $host..."

  # Check if the host already has ANY entry in known_hosts
  if ssh-keygen -F "$host" -f "$KNOWN_HOSTS" &>/dev/null; then
    echo "  ⓘ $host is already in $KNOWN_HOSTS — skipping."
    continue
  fi

  # Fetch keys, filter out any lines already present, append only new ones
  new_keys=$(ssh-keyscan -T 5 "$host" 2>/dev/null)

  if [[ -z "$new_keys" ]]; then
    echo "  ✗ Failed to scan $host (no keys returned or host unreachable)" >&2
    continue
  fi

  added=0
  while IFS= read -r line; do
    if ! grep -qxF "$line" "$KNOWN_HOSTS"; then
      echo "$line" >> "$KNOWN_HOSTS"
      ((added++))
    fi
  done <<< "$new_keys"

  if [[ $added -gt 0 ]]; then
    echo "  ✓ Added $added key(s) for $host"
  else
    echo "  ⓘ All keys for $host already present — nothing added."
  fi
done
