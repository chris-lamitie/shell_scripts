#! /bin/bash
###########################################
# Recon script, outputs info of commands 
# useful about a host. virt vs phys, CPU
# RAM, disk, and IP info
#
# Chris Lamitie, August 2023
###########################################

echo "----------------------------------"
echo "Recon of hostname: $(hostname -A)"
echo "----------------------------------"
os_info=$(cat /etc/*release | grep PRETTY_NAME | sed 's/PRETTY_NAME="//; s/"$//')
echo "OS Info: $os_info"
echo "----------------------------------"
echo "System Product Info:"
echo "$(sudo dmidecode -s system-product-name)"
echo "Serial Number: $(sudo dmidecode -s system-serial-number)"
echo "----------------------------------"
echo "Processor(s): "
sudo dmidecode -s processor-version
#lscpu | grep Model\ name
echo "----------------------------------"
echo "RAM:"
#grep MemTotal /proc/meminfo
free -h
echo "----------------------------------"
echo "Storage:"
disks=$(sudo fdisk -l | grep -E '^Disk /dev/s' | awk '{print $2}' | sed 's/://')
for disk in $disks; do
    sudo fdisk -l $disk | sed -n '1,2p' | awk '{print $2, $3, $4}' | tr -d ','
done
echo "----------------------------------"
echo "Interfaces and IPs:"
interfaces=$(ip link show | awk -F ": " '{print $2}' | grep -v "lo")
for iface in $interfaces; do
        ip_address=$(ip addr show $iface | awk '/inet / {print $2}')
        echo "Interface $iface - IP Address: $ip_address"
done
echo "----------------------------------"
