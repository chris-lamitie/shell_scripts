#! /bin/bash
set -euo pipefail
###########################################
# Recon script, outputs info of commands 
# useful about a host. virt vs phys, CPU
# RAM, disk, and IP info
#
# Chris Lamitie, written August 2023, last updated Dec 2025
###########################################
SPACER="=================================================================="
echo -e "$SPACER"
echo -e "Recon of hostname: $(hostname)"
TODAY="$(date '+%Y-%m-%d %H:%M:%S')"
echo -e "Recon as of: $TODAY"

echo -e "$SPACER"
os_info=$(cat /etc/*release | grep PRETTY_NAME | sed 's/PRETTY_NAME="//; s/"$//')
echo -e "OS Info: $os_info"
KERNEL=$(uname -r)
echo -e "Kernel Version: $KERNEL"
PYTHON=$(/bin/python --version 2>&1 | awk '{print $2}')
echo -e "Default Python Version: $PYTHON"
UPTIME=$(cat /proc/uptime | cut -f1 -d.)
upDays=$((UPTIME/60/60/24))
upHours=$((UPTIME/60/60%24))
upMins=$((UPTIME/60%60))
upSecs=$((UPTIME%60))
echo -e "System Uptime: $upDays days, $upHours hours, $upMins minutes, $upSecs seconds"
LOAD=`cat /proc/loadavg | awk {'print $1", "$2", "$3'}`
echo -e "Load Average (1, 5, 15 min): $LOAD"


echo -e "$SPACER"
echo -e "System Product Info:"
echo -e "$(sudo dmidecode -s system-product-name)"
echo -e "Serial Number: $(sudo dmidecode -s system-serial-number)"

echo -e "$SPACER"
echo -e "Processor(s): "
sudo dmidecode -s processor-version
#lscpu | grep Model\ name
echo -e "$SPACER"
echo -e "RAM:"
#grep MemTotal /proc/meminfo
free -h

echo -e "$SPACER"
echo -e "Interfaces and IPs:"

# Extract interface names, removing any trailing '@' and everything after it.
interfaces=$(ip link show | awk -F ": " '{print $2}' | sed 's/@.*//' | grep -v "lo" | sort -u)

# Define the AWK script for formatting the output
AWK_SCRIPT='
BEGIN {
    # Set the field separator for input to comma (used by printf in the loop)
    FS=",";
    # Define widths for columns to ensure alignment
    FORMAT = "%-12s | %-8s | %-9s | %-22s | %-17s | %-8s | %-8s | %-10s | %-16s | %-12s | %-8s | %-12s\n";
    
    # Print the header row
    printf FORMAT, "INTERFACE", "STATE", "NUMA_NODE", "IP_ADDRESS", "MAC_ADDRESS", "SPEED", "DUPLEX", "STATUS", "MODE/MASTER", "PRIMARY", "VLAN_ID", "VLAN_PARENT";
    # Print the separator line
    printf "----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\n";
}
# Process every line of output piped from the loop
{
    printf FORMAT, $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12;
}
'

# Prepare the data stream for AWK
for iface in $interfaces; do
    # Redirect errors from ip addr show to /dev/null
    IP_ADDRESS=$(ip addr show "$iface" 2>/dev/null | awk '/inet / {print $2}' | tr '\n' ' ')
    if [ -z "$IP_ADDRESS" ]; then
        IP_ADDRESS="N/A"
    fi
    
    # Initialize SysFS-based variables
    MAC="N/A"
    OPERSTATE="N/A"
    SPEED="N/A"
    DUPLEX="N/A"
    NUMA_NODE="N/A"
    
    if [ -d "/sys/class/net/$iface" ]; then
        MAC="$(cat /sys/class/net/$iface/address)";
        OPERSTATE="$(cat /sys/class/net/$iface/operstate)";
        SPEED="$(cat /sys/class/net/$iface/speed 2>/dev/null || echo "N/A")";
        DUPLEX="$(cat /sys/class/net/$iface/duplex 2>/dev/null || echo "N/A")";

        if [ -f "/sys/class/net/$iface/device/numa_node" ]; then
            NUMA_NODE="$(cat /sys/class/net/$iface/device/numa_node)";
        fi
    fi

    # Bonding Status and Details
    BOND_STATUS="None"
    BOND_DETAIL="N/A"
    BOND_PRIMARY="N/A"
    
    if [ -d "/sys/class/net/$iface/bonding" ]; then
        BOND_STATUS="Master"
        BOND_MODE_LINE="$(head -n 1 /sys/class/net/$iface/bonding/mode)"
        BOND_DETAIL="$(echo "$BOND_MODE_LINE" | awk '{print $1}')"
        BOND_PRIMARY="$(head -n 1 /sys/class/net/$iface/bonding/primary)"

    elif [ -d "/sys/class/net/$iface/bonding_slave" ]; then
        BOND_STATUS="Slave"
        BOND_DETAIL="$(head -n 1 /sys/class/net/$iface/subsystem/bonding_masters)"
    fi

    # VLAN Status and Details
    VLAN_ID="N/A"
    VLAN_PARENT="N/A"

    # The bonding checks should already handle Master/Slave, so we focus on VLAN here
    if [ -f "/proc/net/vlan/$iface" ]; then
        VLAN_ID="$(sudo grep -i 'vid' /proc/net/vlan/$iface 2>/dev/null | awk '{print $3}')"
        VLAN_PARENT="$(sudo grep -i 'device' /proc/net/vlan/$iface 2>/dev/null | awk '{print $NF}')"
        
        if [ -n "$VLAN_ID" ]; then
             BOND_STATUS="VLAN"
             BOND_DETAIL="N/A" 
        fi
    fi

    # --- 4. Output (Now printed as a single comma-separated line for AWK to process) ---
    printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
        "$iface" \
        "$OPERSTATE" \
        "$NUMA_NODE" \
        "$IP_ADDRESS" \
        "$MAC" \
        "$SPEED" \
        "$DUPLEX" \
        "$BOND_STATUS" \
        "$BOND_DETAIL" \
        "$BOND_PRIMARY" \
        "$VLAN_ID" \
        "$VLAN_PARENT"
done | awk "$AWK_SCRIPT"

echo -e "\nRoutes:"
ip route show

echo -e "\nNIC PCI and model information:"
echo "$(/usr/sbin/lspci | grep -i ethernet)"

SFKEY_PATH="/usr/sbin/sfkey"
if [ -f "$SFKEY_PATH" ]; then
    echo -e "\nRunning $SFKEY_PATH --all --report..."
    sudo "$SFKEY_PATH" --all --report
fi

echo -e "$SPACER"
echo -e "Storage:"
disks=$(sudo fdisk -l | grep -E '^Disk /dev/s' | awk '{print $2}' | sed 's/://')
for disk in $disks; do
    sudo fdisk -l $disk | sed -n '1,2p' | awk '{print $2, $3, $4}' | tr -d ','
done
echo -e "$SPACER\ndf output:"
df -h
echo -e "$SPACER\nlsblk output:"
lsblk
echo -e "$SPACER"

