#! /bin/bash
###########################################
# Recon script, outputs info of commands
# useful about a host. virt vs phys, CPU
# RAM, disk, and IP info
#
# Chris Lamitie, written August 2023, last updated May 2025
###########################################
SPACER="=================================================================="
echo -e "$SPACER"
echo -e "Recon of hostname: $(hostname -A)"

echo -e "$SPACER"
os_info=$(cat /etc/*release | grep PRETTY_NAME | sed 's/PRETTY_NAME="//; s/"$//')
echo -e "OS Info: $os_info"

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
interfaces=$(ip link show | awk -F ": " '{print $2}' | grep -v "lo")
for iface in $interfaces; do
        ip_address=$(ip addr show $iface | awk '/inet / {print $2}')
        echo -e "Interface $iface - IP Address: $ip_address"
done
echo -e "\nRoutes:"
ip route show

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
