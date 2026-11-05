#!/usr/bin/env bash

set -euo pipefail

# -------- Configuration / Input --------
TARGET_PATH="${1:-.}"

if [[ ! -d "$TARGET_PATH" ]]; then
  echo "ERROR: '$TARGET_PATH' is not a directory"
  exit 1
fi

cd "$TARGET_PATH"

# -------- Output Header --------
printf "Scanning path: %s\n\n" "$(pwd)"
printf "%-45s %15s %15s\n" "DIRECTORY" "SIZE_GB" "FILE_COUNT"
printf "%-45s %15s %15s\n" "---------" "-------" "----------"

total_bytes=0
total_files=0
dir_count=0

# -------- Main Loop --------
for d in */; do
  [[ -d "$d" ]] || continue

  size_bytes=$(du -sb "$d" | awk '{print $1}')
  file_count=$(find "$d" -type f | wc -l)

  size_gb=$(awk -v b="$size_bytes" 'BEGIN { printf "%.2f", b/1e9 }')

  printf "%-45s %15s %15d\n" "$d" "$size_gb" "$file_count"

  total_bytes=$((total_bytes + size_bytes))
  total_files=$((total_files + file_count))
  dir_count=$((dir_count + 1))
done

# -------- Summary --------
echo
echo "==================== SUMMARY ===================="

if [[ $dir_count -gt 0 ]]; then
  avg_bytes=$((total_bytes / dir_count))
  avg_files=$((total_files / dir_count))

  avg_gb=$(awk -v b="$avg_bytes" 'BEGIN { printf "%.2f", b/1e9 }')

  echo "Directories scanned : $dir_count"
  echo "Total size          : $(awk -v b="$total_bytes" 'BEGIN { printf "%.2f GB", b/1e9 }')"
  echo "Total files         : $total_files"
  echo
  echo "Average size/dir    : $avg_gb GB"
  echo "Average files/dir   : $avg_files"
else
  echo "No directories found in $TARGET_PATH"
fi
