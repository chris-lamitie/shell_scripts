#!/bin/bash
##########################################################################################
# CG Lamitie
# ethtool tester. 
# 
# The point of this is to use ethtool to print the  link status of all 
# interfaces on a host when testing if a link has a connection or not.
# 
# The nicArray vairable is an ip command below is finding links, then using awk to find 
# leading numbers, grabbing the 2nd value because that is the interface name,  using sed 
# to trim a trailing : character
##########################################################################################
nicArray=$(ip -f link a | awk '$1 ~ /[0-9]/ { print $2 }' |  sed 's/://g')

for str in ${nicArray[@]}; do
  echo "testing $str link"
  ethtool $str | grep Link
done

