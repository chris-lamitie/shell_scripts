#!/bin/bash

# Function to display usage information
usage() {
  echo "Usage: $0 [filename_of_hosts | host1 host2 ...]"
  echo "  If a single argument is provided, it's treated as a file containing hostnames (one per line)."
  echo "  If multiple arguments are provided, they are treated as individual hostnames."
  exit 1
}

# Check if any arguments are provided
if [ "$#" -eq 0 ]; then
  usage
fi

# Initialize an empty array for hosts
hosts=()

# Determine if input is a file or direct hostnames
if [ "$#" -eq 1 ] && [ -f "$1" ]; then
  # Input is a single file
  HOST_FILE="$1"
  echo "Reading hosts from file: $HOST_FILE"
  readarray -t hosts < "$HOST_FILE"
elif [ "$#" -ge 1 ]; then
  # Input is a list of hostnames directly from CLI
  echo "Using hosts from command line arguments."che
  hosts=("$@")
else
  # Invalid input (e.g., single argument that isn't a file)
  usage
fi

# Check if the hosts array is empty after processing input
if [ ${#hosts[@]} -eq 0 ]; then
  echo "Error: No hosts found to process."
  exit 1
fi

# Iterate through the array of hosts
for host in "${hosts[@]}"; do
  echo "--- Checking $host ---"
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" "ps aux | grep ' D'"
  echo "" # Add an empty line for better readability between hosts
done

echo "Finished checking for deadlocks."
