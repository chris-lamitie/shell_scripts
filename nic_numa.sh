#!/bin/bash
#
# nic_numa.sh
#
# Show which NUMA node each network interface is attached to.
#
# How it works:
#   1. Lists every interface in /sys/class/net (except loopback).
#   2. Follows the interface's sysfs "device" link to find its PCI address.
#   3. Reads the NUMA node from that PCI device's numa_node file.
#   4. Gets the device description from `lspci`.
#   5. Prints Interface, PCI Address, NUMA Node and Device Info for each one.
#
# Why it matters:
#   For low-latency work, the threads that handle a NIC's traffic should run
#   on CPUs in the same NUMA node as the NIC. Traffic that crosses NUMA nodes
#   adds latency. Use this output to choose CPU affinity / IRQ pinning.
#
# Output:
#   NUMA Node "N/A"            - the kernel reports no NUMA locality (-1),
#                                common on single-socket machines.
#   "PCI device not found"     - a virtual interface with no physical device
#                                (bond, bridge, VLAN, veth, tun, etc.).
#
# Requirements:
#   - pciutils (lspci). Does not need root.
#
# Usage:
#   ./nic_numa.sh
#

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
