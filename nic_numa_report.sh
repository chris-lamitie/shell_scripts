#!/bin/bash
##############################################################################
# nic_numa_report.sh
# A report script that identifies NICs and networks then shows what NUMA nodes
# nodes those NICs and networks are on as well as what CPU cores are available
# for each NIC/network. Handy for planning CPU isolations and pinning.
# By Chris Lamitie
# 2026-04
##############################################################################

# ─── Helpers ─────────────────────────────────────────────────────────────────

get_local_cpus_for_pci() {
    local pci=$1
    cat /sys/bus/pci/devices/${pci}/local_cpulist 2>/dev/null
}

get_pci_for_iface() {
    local iface=$1
    local syspath
    syspath=$(readlink -f /sys/class/net/$iface/device 2>/dev/null)
    [[ -d "$syspath" ]] && basename "$syspath" || echo ""
}

get_numa_for_iface() {
    local iface=$1
    local syspath
    syspath=$(readlink -f /sys/class/net/$iface/device 2>/dev/null)
    [[ -d "$syspath" ]] || { echo "N/A"; return; }
    local numa
    numa=$(cat "$syspath/numa_node" 2>/dev/null)
    [[ "$numa" == "-1" ]] && echo "N/A" || echo "$numa"
}

get_vlan_parent() {
    local iface=$1
    local parent
    parent=$(awk '/^[[:space:]]*Device:/{print $2}' /proc/net/vlan/$iface 2>/dev/null)
    [[ -n "$parent" ]] && echo "$parent" && return
    awk -v dev="$iface" '$1 == dev {print $5}' /proc/net/vlan/config 2>/dev/null
}

get_iface_type() {
    local iface=$1
    [[ -d /sys/class/net/$iface/bonding ]]         && echo "bond"      && return
    [[ -d /sys/class/net/$iface/master ]]           && echo "bond-slave" && return
    [[ -f /proc/net/vlan/$iface ]]                  && echo "vlan"      && return
    local syspath
    syspath=$(readlink -f /sys/class/net/$iface/device 2>/dev/null)
    [[ -d "$syspath" ]]                             && echo "physical"  && return
    echo "unknown"
}

# Recursively resolve an interface down to its physical NIC(s)
resolve_physical() {
    local iface=$1
    local syspath
    syspath=$(readlink -f /sys/class/net/$iface/device 2>/dev/null)
    if [[ -d "$syspath" ]]; then
        echo "$iface"
        return
    fi
    local lowers
    lowers=$(ls /sys/class/net/$iface/ 2>/dev/null | grep '^lower_' | sed 's/^lower_//')
    if [[ -z "$lowers" && -f /sys/class/net/$iface/bonding/slaves ]]; then
        lowers=$(cat /sys/class/net/$iface/bonding/slaves)
    fi
    if [[ -n "$lowers" ]]; then
        for lower in $lowers; do
            resolve_physical "$lower"
        done
    fi
}

get_bond_slaves() {
    local iface=$1
    cat /sys/class/net/$iface/bonding/slaves 2>/dev/null | tr ' ' ','
}

# ─── Network → NIC → NUMA Summary ───────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════════════"
echo "  Network Interface Summary"
echo "══════════════════════════════════════════════════════════════════"

for iface in $(ls /sys/class/net/ | grep -Ev '^(lo|bonding_masters)$' | sort); do
    type=$(get_iface_type "$iface")

    case "$type" in
        physical)
            # Already covered in the section above, skip
            continue
            ;;
        bond)
            slaves=$(get_bond_slaves "$iface")
            physicals=($(resolve_physical "$iface"))
            pci=$(get_pci_for_iface "${physicals[0]}")
            numa=$(get_numa_for_iface "${physicals[0]}")
            detail="slaves: $slaves"
            ;;
        bond-slave)
            # Shown as part of the bond entry, skip
            continue
            ;;
        vlan)
            parent=$(get_vlan_parent "$iface")
            physicals=($(resolve_physical "$iface"))
            pci=$(get_pci_for_iface "${physicals[0]}")
            numa=$(get_numa_for_iface "${physicals[0]}")
	    vid=$(awk '/VID:/{print $3}' /proc/net/vlan/$iface 2>/dev/null)
            detail="vlan-id: ${vid:-?}  parent: ${parent:-unknown}"
            ;;
        unknown)
            continue
            ;;
    esac

    echo ""
    echo "  Network   : $iface"
    echo "  Type      : $type"
    echo "  Detail    : $detail"
    echo "  Phys NIC  : ${physicals[*]}"
    echo "  PCI       : $pci"
    echo "  NUMA Node : $numa"
    echo "  ──────────────────────────────────────────────────────────────"
done

# ─── Physical NIC Section ────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════════════"
echo "  Physical NIC → NUMA → CPU Mapping"
echo "══════════════════════════════════════════════════════════════════"

for iface in $(ls /sys/class/net/ | sort); do
    [[ "$iface" == "lo" ]] && continue

    syspath=$(readlink -f /sys/class/net/$iface/device 2>/dev/null)
    [[ -d "$syspath" ]] || continue

    pci=$(basename "$syspath")
    numa=$(cat "$syspath/numa_node" 2>/dev/null)
    [[ "$numa" == "-1" ]] && numa="N/A"

    devinfo=$(lspci -s "$pci" 2>/dev/null | cut -d' ' -f2-)
    local_cpulist=$(get_local_cpus_for_pci "$pci")

    echo ""
    echo "  Interface : $iface"
    echo "  PCI       : $pci"
    echo "  NUMA Node : $numa"
    echo "  Device    : $devinfo"
    echo "  Local CPUs: $local_cpulist"
    echo "  ──────────────────────────────────────────────────────────────"
done

# ─── NUMA Summary ────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════════════"
echo "  NUMA Node Summary"
echo "══════════════════════════════════════════════════════════════════"

for node_path in /sys/devices/system/node/node*/; do
    node=$(basename "$node_path" | tr -d 'node')
    cpulist=$(cat "$node_path/cpulist" 2>/dev/null)
    mem_kb=$(awk '/MemTotal/{print $4}' "$node_path/meminfo" 2>/dev/null)
    mem_gb=$(awk "BEGIN {printf \"%.1f\", ${mem_kb:-0}/1048576}")
    echo ""
    echo "  NUMA $node"
    echo "    CPUs  : $cpulist"
    echo "    Memory: ${mem_gb} GB"
done

echo ""
