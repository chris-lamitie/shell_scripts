#!/bin/bash
#####################################
# nmap testing script for AD ports.
# Takes a domain name from CLI then looks up SRV records for the domain. 
# Then it loops through the results with nmap to test if a list of TCP & UDP 
# ports are open. Results are printed to stdout and an xml file in the local
# directory. Nmap must be run as root or with sudo.
#
# By Chris Lamitie, August 2023
#####################################

# Check if the current user is root or sudo.
if [[ $EUID -ne 0 ]]; then
  # The current user is not root or sudo, so exit.
  echo "This script must be run as root or sudo."
  exit 1
fi

# Check nmap is installed, if not, exit.
if ! which nmap >/dev/null; then
  echo "nmap is not installed."
  exit 1
fi

echo "This script will use nmap to scan known Active Directory"
echo "ports and print the results to stdout and a file known as"
echo "'nmap_ad_scan.xml'. What domain would you like to scan?"
echo ""
echo "Enter a domain name to continue (e.g. example.com): "
read domain_name

# list of known AD ports, some are TCP and UDP, some are TCP only.
# see: https://access.redhat.com/solutions/1364713
known_tcp_and_udp_ports="53,88,389,464"
known_tcp_ports="636,3268,3269"

# Get the list of hostnames from the Active Directory domain
hostnames=$(dig +short -t SRV _ldap._tcp.dc._msdcs.$domain_name | awk '{print $4}')

if [[ -z "$hostnames" ]]; then
  echo "could not find SRV records for the given domain: '$domain_name'"
  exit 1
fi

# Loop through the hostnames and scan them with nmap
for hostname in $hostnames; do
  # trim trailing '.' from dig output
  hostname=${hostname%.}

  nmap -sT -sU -p $known_tcp_and_udp_ports -oX nmap_ad_scan.xml -append-output $hostname
  nmap -sT -p $known_tcp_ports -oX nmap_ad_scan.xml -append-output $hostname

done

echo ""
echo "Script done. Look for a file called 'nmap_ad_scan.xml' in the current working directory."
exit 0
