#!/bin/bash

# Ensure the script is run as root for smartctl access
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (sudo)."
   exit 1
fi

echo "========================================================="
echo "                DISK RECONNAISSANCE REPORT               "
echo "========================================================="
echo "Generated on: $(date)"
echo "---------------------------------------------------------"

# Get only physical device names (sda, sdb, nvme0n1)
DRIVES=$(lsblk -dno name)

for dev in $DRIVES; do
    DEVICE_PATH="/dev/$dev"
    
    echo "DEVICE: $DEVICE_PATH"
    
    # Run smartctl -i and filter for all common SATA/SAS/NVMe fields
    # -i: case-insensitive
    # -E: extended regex for multiple patterns
    sudo smartctl -i "$DEVICE_PATH" | grep -Ei "Model Family|Device Model|Vendor|Product|User Capacity|Serial Number|Rotation Rate|Transport protocol" | sed 's/^/  /'
    
    # Check SMART Health Status briefly
    HEALTH=$(sudo smartctl -H "$DEVICE_PATH" | grep -Ei "test result|health status" | awk -F: '{print $2}' | xargs)
    [[ -z "$HEALTH" ]] && HEALTH="Unknown/Not Supported"
    echo "  SMART Health: $HEALTH"
    
    echo "---------------------------------------------------------"
done
