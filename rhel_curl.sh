#!/bin/bash

# Source of this script: https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/performing_a_standard_rhel_8_installation/downloading-beta-installation-images_installing-rhel#downloading-an-iso-image-with-curl_downloading-beta-installation-images
# you ma need to get your own offline token and checksums.
# Purpose: to use curl and jq to pull Red Hat isos from redhat.com for later use.
# Requires: curl and jq installed on the system.

# set the offline token
offline_token="eyJhbGciOiJIUzUxMiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICI0NzQzYTkzMC03YmJiLTRkZGQtOTgzMS00ODcxNGRlZDc0YjUifQ.eyJpYXQiOjE3MTU2Mjg1NjEsImp0aSI6IjIwYTU5NWViLTIwNjktNGMyMy1iMjFlLWM2MDVmMzJiMTNjMiIsImlzcyI6Imh0dHBzOi8vc3NvLnJlZGhhdC5jb20vYXV0aC9yZWFsbXMvcmVkaGF0LWV4dGVybmFsIiwiYXVkIjoiaHR0cHM6Ly9zc28ucmVkaGF0LmNvbS9hdXRoL3JlYWxtcy9yZWRoYXQtZXh0ZXJuYWwiLCJzdWIiOiJmOjUyOGQ3NmZmLWY3MDgtNDNlZC04Y2Q1LWZlMTZmNGZlMGNlNjpjaHJpc2wtc3RvbmV4IiwidHlwIjoiT2ZmbGluZSIsImF6cCI6InJoc20tYXBpIiwic2Vzc2lvbl9zdGF0ZSI6IjZiMDM4MDBhLTQzNWItNDZiYy04NmQxLTIxMDVkYTRmZGJhZiIsInNjb3BlIjoicm9sZXMgd2ViLW9yaWdpbnMgb2ZmbGluZV9hY2Nlc3MiLCJzaWQiOiI2YjAzODAwYS00MzViLTQ2YmMtODZkMS0yMTA1ZGE0ZmRiYWYifQ.8s2tbJzhOPTvQTrTG4Mqe0D9U8toTELEE2psBft-tjwLI2nUJv1d070KJ9JLQ9pB1c5zoIe9iD6gUl734cKBTA"

# List of checksums
checksums=(
  "0f2002c201ac5d8565dd8891e56be3711f45a0ac482f58294bb6d3654ac621d7" # Red Hat Enterprise Linux 7.9 Boot ISO
  "2cb36122a74be084c551bc7173d2d38a1cfb75c8ffbc1489c630c916d1b31b25" # rhel 7.9 dvd checksum
  "61fe463758f6ee9b21c4d6698671980829ca4f747a066d556fa0e5eefc45382c" # Red Hat Enterprise Linux 8.5 Boot ISO 
  "1f78e705cd1d8897a05afa060f77d81ed81ac141c2465d4763c0382aa96cadd0" # rhel 8.5 dvd checksum
  "1419ea8ae06722f858734bcc8060285314c335522e2086f0963941cd00432f8c" # Red Hat Enterprise Linux 8.8 Boot ISO 
  "517abcc67ee3b7212f57e180f5d30be3e8269e7a99e127a3399b7935c7e00a09" # rhel 8.8 dvd checksum
  "17b013f605e6b85affd37431b533b6904541f8b889179ae3f99e1e480dd4ae38" # Red Hat Enterprise Linux 9.4 Boot ISO 
  "398561d7b66f1a4bf23664f4aa8f2cfbb3641aa2f01a320068e86bd1fc0e9076" # rhel 9.4 dvd checksum
)

# Get an access token
access_token=$(curl -s https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token -d grant_type=refresh_token -d client_id=rhsm-api -d refresh_token=$offline_token | jq -r '.access_token')

# Loop through each checksum and download the corresponding file
for checksum in "${checksums[@]}"; do
  image=$(curl -s -H "Authorization: Bearer $access_token" "https://api.access.redhat.com/management/v1/images/$checksum/download")
  filename=$(echo "$image" | jq -r '.body.filename')
  url=$(echo "$image" | jq -r '.body.href')

  # Download the file
  curl -o "$filename" "$url"
  echo "Downloaded $filename"
done
