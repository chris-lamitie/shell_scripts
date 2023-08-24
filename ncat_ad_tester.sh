#!/bin/bash
#####################################
# NCat testing script for AD ports.
# Takes input from CLI in the form of a domain name then looks up SRV records for the domain.
# Loops through the results and uses ncat, specifically 'nc', to test a list of TCP & UDP
# ports and prints success or failure results to stdout.
#
# By Chris Lamitie, August 2023
#####################################

# list of known AD ports, some are TCP and UDP, some are TCP only.
# see: https://access.redhat.com/solutions/1364713
known_tcp_and_udp_ports=(53 88 389 464)
known_tcp_ports=(636 3268 3269)

# Get the domain name argument from the CLI.
domain_name=$1

# Check if the first argument is empty.
if [ -z "$1" ]; then
  # The first argument is empty, so print an error message and exit.
  echo "USAGE: Provide a domain name to this script via ./ncat_ad_tester.sh <domain name>. Exiting"
  exit 1
fi

# Check nc is installed, if not, exit.
if ! which nc >/dev/null; then
  echo "nc is not installed. Exiting."
  exit 1
fi

# Get the list of hostnames from the Active Directory domain
hostnames=$(dig +short -t SRV _ldap._tcp.dc._msdcs.$domain_name | awk '{print $4}')

# Print the hostnames in a for loop
for hostname in $hostnames; do
  error_code=0
  # trim trailing '.' from dig output
  hostname=${hostname%.}

  # Check ports that should be open on both TCP and UDP
  for port in "${known_tcp_and_udp_ports[@]}"; do
    nc -z $hostname $port
    if [ $? -ne 0 ]; then
      echo "$hostname Connection to tcp $port failed"
      ((error_code++))
    fi
    nc -zu $hostname $port
    if [ $? -ne 0 ]; then
      echo "$hostname Connection to udp $port failed"
      ((error_code++))
    fi
  done

  # Check ports that should be open on TCP only
  for port in "${known_tcp_ports[@]}"; do
    nc -z $hostname $port
    if [ $? -ne 0 ]; then
      echo "$hostname Connection to tcp $port failed"
      ((error_code++))
    fi
  done

  # if error_code is 0, all port checks passed.
  if [ $error_code -eq 0 ]; then
    echo "$hostname Active Directory port checks passed."
  fi
done
