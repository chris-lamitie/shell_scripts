#!/bin/bash

echo "Interface  | PCI Address     | NUMA Node | Device Info"
echo "-----------|-----------------|-----------|-------------------------------"

for iface in $(ls /sys/class/net/ | grep -v lo); do
    syspath=$(readlink -f /sys/class/net/$iface/device)

    if [[ -d "$syspath" ]]; then
        pciaddr=$(basename "$syspath")
        numanode=$(cat "$syspath/numa_node" 2>/dev/null)

        # Handle missing NUMA info
        [[ "$numanode" == "-1" ]] && numanode="N/A"

        # Get device description from lspci
        devinfo=$(lspci -s "$pciaddr" | cut -d ' ' -f 2-)

        printf "%-10s | %-15s | %-9s | %s\n" "$iface" "$pciaddr" "$numanode" "$devinfo"
    else
        printf "%-10s | %-15s | %-9s | %s\n" "$iface" "N/A" "N/A" "PCI device not found"
    fi
done
