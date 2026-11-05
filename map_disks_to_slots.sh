#!/usr/bin/env bash

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
