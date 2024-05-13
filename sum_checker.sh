#!/bin/bash

# sum_checker.sh
# Purpose: Conduct a sha256 checksum of iso files in the current directory and grep a
# file of checksums to validate accuracy of the isos

# Define the checksum file name as a variable
checksum_file="vendor_sums.txt"

# Ensure the checksum file exists
if [[ ! -f "$checksum_file" ]]; then
    echo "Error: $checksum_file not found."
    exit 1
fi

# Loop through all iso files in the current directory
for iso in *.iso; do
    if [[ -f "$iso" ]]; then
        # Calculate sha256 checksum of the current iso file
        calculated_sum=$(sha256sum "$iso" | awk '{print $1}')

        # Attempt to find a matching checksum and filename in the checksum file
        match=$(grep "$calculated_sum  $iso" "$checksum_file")

        if [[ $? -eq 0 ]]; then
            # Extract the filename from the match for clearer output
            filename=$(echo "$match" | awk '{print $2}')
            echo "Success: Checksum for $iso matches $filename in $checksum_file."
        else
            echo "Failure: Checksum for $iso not found in $checksum_file."
        fi
    fi
done
