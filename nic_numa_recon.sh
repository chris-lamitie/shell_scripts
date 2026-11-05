#!/bin/bash
##############################################################################
# nic_numa_recon.sh
# A short recon script that identifies NICs and networks then shows what NUMA
# nodes those NICs and networks are on.
# By Chris Lamitie
# 2026-04
##############################################################################

# ─── Helpers ────────────────────────────────────────────────────────────────

get_pci_and_numa() {
    local iface=$1
    local syspath
    syspath=$(readlink -f /sys/class/net/$iface/device 2>/dev/null)
    if [[ -d "$syspath" ]]; then
        local pci numa
        pci=$(basename "$syspath")
        numa=$(cat "$syspath/numa_node" 2>/dev/null)
        [[ "$numa" == "-1" ]] && numa="N/A"
        echo "$pci|$numa"
    else
        echo "N/A|N/A"
    fi
}

get_devinfo() {
    local pci=$1
    [[ "$pci" == "N/A" ]] && echo "" || lspci -s "$pci" 2>/dev/null | cut -d ' ' -f 2-
}

# Recursively resolve an interface down to its physical NIC(s)
# Returns a space-separated list of physical interface names
resolve_physical() {
    local iface=$1

    # If it has a PCI device, it's physical
    local syspath
    syspath=$(readlink -f /sys/class/net/$iface/device 2>/dev/null)
    if [[ -d "$syspath" ]]; then
        echo "$iface"
        return
    fi

    # Walk lower_* links (covers VLANs, macvlan, bonds as slave, etc.)
    local lowers
    lowers=$(ls /sys/class/net/$iface/ 2>/dev/null | grep '^lower_' | sed 's/^lower_//')

    # Bond: members listed under bonding/slaves instead of lower_*
    if [[ -z "$lowers" && -f /sys/class/net/$iface/bonding/slaves ]]; then
        lowers=$(cat /sys/class/net/$iface/bonding/slaves)
    fi

    if [[ -n "$lowers" ]]; then
        local result=()
        for lower in $lowers; do
            result+=($(resolve_physical "$lower"))
        done
        echo "${result[*]}"
    else
        echo ""
    fi
}

get_iface_type() {
    local iface=$1

    # Bond master
    [[ -d /sys/class/net/$iface/bonding ]] && echo "bond" && return

    # Bond slave
    [[ -d /sys/class/net/$iface/master ]] && echo "bond-slave" && return

    # VLAN (via /proc/net/vlan or lower_ link on a non-bond)
    if [[ -f /proc/net/vlan/$iface ]]; then
        echo "vlan"
        return
    fi

    # Has lower_ links but not a bond → generic virtual (macvlan, etc.)
    local lowers
    lowers=$(ls /sys/class/net/$iface/ 2>/dev/null | grep '^lower_')
    [[ -n "$lowers" ]] && echo "virtual" && return

    # Has PCI device → physical
    local syspath
    syspath=$(readlink -f /sys/class/net/$iface/device 2>/dev/null)
    [[ -d "$syspath" ]] && echo "physical" && return

    echo "unknown"
}

get_vlan_parent() {
    local iface=$1

    # Method 1: /proc/net/vlan/<iface> — look for the "Device:" line
    local parent
    parent=$(awk '/^[[:space:]]*Device:/{print $2}' /proc/net/vlan/$iface 2>/dev/null)
    [[ -n "$parent" ]] && echo "$parent" && return

    # Method 2: /proc/net/vlan/config — format is "name | VID | parent"
    awk -v dev="$iface" '$1 == dev {print $5}' /proc/net/vlan/config 2>/dev/null
}

get_bond_slaves() {
    local iface=$1
    cat /sys/class/net/$iface/bonding/slaves 2>/dev/null | tr ' ' ','
}

get_bond_master() {
    local iface=$1
    local master
    master=$(readlink /sys/class/net/$iface/master 2>/dev/null)
    basename "$master" 2>/dev/null
}

# ─── Main ────────────────────────────────────────────────────────────────────

headers=("Interface" "Type" "PCI Addr" "NUMA" "Parent / Members" "Device Info")

# Parallel arrays — one entry per row
col_iface=()
col_type=()
col_pci=()
col_numa=()
col_relation=()
col_devinfo=()

for iface in $(ls /sys/class/net/ | grep -Ev '^(lo|bonding_masters)$' | sort); do
    type=$(get_iface_type "$iface")
    pci_numa=$(get_pci_and_numa "$iface")
    pci="${pci_numa%|*}"
    numa="${pci_numa#*|}"

    case "$type" in
        physical)
            devinfo=$(get_devinfo "$pci")
            relation=""
            ;;
        bond)
            slaves=$(get_bond_slaves "$iface")
            relation="slaves: ${slaves:-none}"
            physicals=($(resolve_physical "$iface"))
            if [[ ${#physicals[@]} -gt 0 ]]; then
                pci_numa=$(get_pci_and_numa "${physicals[0]}")
                numa="${pci_numa#*|}*"
            fi
            devinfo=""
            ;;
        bond-slave)
            master=$(get_bond_master "$iface")
            relation="master: $master"
            devinfo=$(get_devinfo "$pci")
            ;;
        vlan)
            parent=$(get_vlan_parent "$iface")
            relation="parent: ${parent:-unknown}"
            physicals=($(resolve_physical "$iface"))
            if [[ ${#physicals[@]} -gt 0 ]]; then
                pci_numa=$(get_pci_and_numa "${physicals[0]}")
                pci="${pci_numa%|*}"
                numa="${pci_numa#*|}*"
            fi
            devinfo=$(get_devinfo "${pci_numa%|*}")
            ;;
        virtual)
            physicals=($(resolve_physical "$iface"))
            if [[ ${#physicals[@]} -gt 0 ]]; then
                pci_numa=$(get_pci_and_numa "${physicals[0]}")
                pci="${pci_numa%|*}"
                numa="${pci_numa#*|}*"
                relation="via: ${physicals[*]}"
            else
                relation=""
            fi
            devinfo=""
            ;;
        *)
            relation=""
            devinfo=""
            ;;
    esac

    col_iface+=("$iface")
    col_type+=("$type")
    col_pci+=("$pci")
    col_numa+=("$numa")
    col_relation+=("$relation")
    col_devinfo+=("$devinfo")
done

# ─── Measure column widths ───────────────────────────────────────────────────

w0=${#headers[0]}; w1=${#headers[1]}; w2=${#headers[2]}
w3=${#headers[3]}; w4=${#headers[4]}; w5=${#headers[5]}

for i in "${!col_iface[@]}"; do
    (( ${#col_iface[$i]}     > w0 )) && w0=${#col_iface[$i]}
    (( ${#col_type[$i]}      > w1 )) && w1=${#col_type[$i]}
    (( ${#col_pci[$i]}       > w2 )) && w2=${#col_pci[$i]}
    (( ${#col_numa[$i]}      > w3 )) && w3=${#col_numa[$i]}
    (( ${#col_relation[$i]}  > w4 )) && w4=${#col_relation[$i]}
    (( ${#col_devinfo[$i]}   > w5 )) && w5=${#col_devinfo[$i]}
done

# ─── Print ───────────────────────────────────────────────────────────────────

fmt="%-${w0}s | %-${w1}s | %-${w2}s | %-${w3}s | %-${w4}s | %s\n"
sep="$(printf '%*s' $w0 '' | tr ' ' '-')-+-$(printf '%*s' $w1 '' | tr ' ' '-')-+-$(printf '%*s' $w2 '' | tr ' ' '-')-+-$(printf '%*s' $w3 '' | tr ' ' '-')-+-$(printf '%*s' $w4 '' | tr ' ' '-')-+-$(printf '%*s' $w5 '' | tr ' ' '-')"

printf "$fmt" "${headers[@]}"
echo "$sep"

for i in "${!col_iface[@]}"; do
    printf "$fmt" \
        "${col_iface[$i]}" "${col_type[$i]}" "${col_pci[$i]}" \
        "${col_numa[$i]}" "${col_relation[$i]}" "${col_devinfo[$i]}"
done

echo ""
echo "  * NUMA node inherited from underlying physical NIC"
