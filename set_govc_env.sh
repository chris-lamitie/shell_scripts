#!/bin/bash
  
# This script sets the environment variables necessary for govc

# Prompt the user for input to avoid hardcoding sensitive information
echo "usage: 'source set_govc_env.sh' follow prompts to load govc vars into your environment variables."
read -p "Enter vCenter Server URL (e.g., https://your-vcenter-server/sdk): " server_url
read -p "Enter your vCenter Username: " username
# Use -s to hide password input
read -sp "Enter your vCenter Password: " password
echo # Adds a newline after password input

# Export the environment variables
export GOVC_URL=$server_url
export GOVC_USERNAME=$username
export GOVC_PASSWORD=$password
export GOVC_INSECURE=true  # Set this to true to skip SSL certificate verification

echo "GOVC environment variables set successfully. You may test with 'govc ls /vm'"
