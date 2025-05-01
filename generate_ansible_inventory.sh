#!/bin/bash
####################################################################
# This script reads a basic Ansible hosts.txt file of IPs and hostnames
# then builds a nice ansible yaml file with some extra vars related
# to the found hosts, such as the host's public ssh-key.
#
# Written 2024.
###################################################################
# Default input file name
default_input_file="hosts.txt"

# Check for the presence of dig
if ! command -v dig &> /dev/null; then
  echo "dig could not be found. Please install bind-utils."
  exit 1
fi

# Check if the input file exists
if [ ! -f "$default_input_file" ]; then
  echo "Input file '$default_input_file' not found."
  read -p "Please enter the file name containing the list of FQDN hosts: " input_file
  if [ ! -f "$input_file" ]; then
    echo "File '$input_file' not found. Exiting..."
    exit 1
  fi
else
  input_file="$default_input_file"
fi

# Output inventory file
output_file="inventory/98-found-hosts.yml"

# Create the inventory directory if it doesn't exist
mkdir -p inventory

# Start the YAML file
echo "found_hosts:" > $output_file
echo "  hosts:" >> $output_file

# Read each line (FQDN) from the input file
while IFS= read -r fqdn; do
  # Get the IP address using dig
  ip=$(dig +short "$fqdn")

  # Check if the IP was found
  if [ -z "$ip" ]; then
    echo "No IP found for $fqdn, skipping..."
    continue
  fi

  # Try to get the SSH public key for different key types
  ssh_key=""
  for key_type in rsa ecdsa ed25519; do
    ssh_key=$(ssh-keyscan -t $key_type "$fqdn" 2>/dev/null | awk '{print $3}' | tr -d '\n')
    if [ ! -z "$ssh_key" ]; then
      break
    fi
  done

  # Check if the SSH key was found
  if [ -z "$ssh_key" ]; then
    echo "No SSH public key found for $fqdn, skipping..."
    continue
  fi

  # Add the host entry to the YAML file
  echo "    $fqdn:" >> $output_file
  echo "      ansible_host: $ip" >> $output_file
  echo "      public_key: $ssh_key" >> $output_file

done < "$input_file"

echo "Ansible inventory has been generated at $output_file"

