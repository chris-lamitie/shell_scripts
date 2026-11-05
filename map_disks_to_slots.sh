#!/usr/bin/env bash
#
# map_disks_to_slots.sh
#
# Map each /dev/sdX disk to its physical slot in a SAS enclosure (JBOD/backplane).
#
# How it works:
#   1. Finds the enclosure's SCSI generic device (/dev/sgN) via `lsscsi -g`.
#   2. Reads the SES "Additional Element Status" page (`sg_ses --page=aes`) and
#      builds a table of SAS address -> slot (element index).
#   3. For every /dev/sd? disk, looks up its WWN with `udevadm` and matches it
#      against the SES table.
#   4. Prints DEVICE, WWN, SLOT and MODEL for each disk.
#
# Matching note:
#   A disk's SAS port address and its WWN usually differ only in the last hex
#   digit (dual-port offset), so both are compared with that digit stripped.
#
# Output:
#   SLOT is the SES element index, which normally matches the slot number
#   printed on the chassis. A "?" means the disk wasn't found in the enclosure
#   (e.g. an internal/boot drive). Disks with no WWN are skipped.
#
# Requirements:
#   - Root (or permission to read /dev/sg* devices)
#   - sg3_utils (sg_ses), lsscsi, udevadm, lsblk
#
# Limitations:
#   - Assumes exactly one enclosure; with several, set ENCLOSURE by hand below.
#   - Only checks /dev/sd? (sda-sdz), not /dev/sdaa and beyond.
#
# Usage:
#   sudo ./map_disks_to_slots.sh
#

#ENCLOSURE="/dev/sg14"
ENCLOSURE=$(lsscsi -g | grep enclo | awk '{ print $7 }')

echo "Building SES map from $ENCLOSURE..."
echo

# Get SES data once
SES_OUTPUT=$(sg_ses --page=aes "$ENCLOSURE")

# Build associative array: truncated SAS → slot index
declare -A SLOT_MAP

while read -r line; do
    if [[ $line =~ Element\ index:\ ([0-9]+) ]]; then
        INDEX="${BASH_REMATCH[1]}"
    fi

    if [[ $line =~ SAS\ address:\ (0x[0-9a-fA-F]+) ]]; then
        ADDR="${BASH_REMATCH[1]}"
        # Normalize: strip last hex digit (handles dual-port offset)
        KEY="${ADDR:0:${#ADDR}-1}"
        SLOT_MAP["$KEY"]="$INDEX"
    fi
done <<< "$SES_OUTPUT"

echo "Disk → Slot Mapping"
echo "-----------------------------------------------"
printf "%-8s %-20s %-6s %-10s\n" "DEVICE" "WWN" "SLOT" "MODEL"

for dev in /dev/sd?; do
    # Get WWN
    WWN=$(udevadm info --query=all --name="$dev" | grep ID_WWN= | cut -d= -f2)

    # Skip if no WWN
    [[ -z "$WWN" ]] && continue

    # Normalize WWN (strip last hex digit)
    KEY="${WWN:0:${#WWN}-1}"

    SLOT="${SLOT_MAP[$KEY]}"

    # Get model
    MODEL=$(lsblk -ndo MODEL "$dev")

    printf "%-8s %-20s %-6s %-10s\n" "$dev" "$WWN" "${SLOT:-?}" "$MODEL"
done

echo
echo "Done."

