#!/bin/bash

debug=1

# Regular expression patterns for IPv4 address and FQDN hostname
ipv4_pattern='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
fqdn_pattern='^([a-zA-Z0-9]+(-[a-zA-Z0-9]+)*\.)+[a-zA-Z]{2,}$'

echo "check_hosts.sh will test DNS, ping and ssh access to a list of hosts or IPs"
echo "Enter the file name you want to parse: "
read filename

if [ "$debug" -eq 1 ]; then
	echo "  $filename given."
fi

# Check if the file exists
if [ ! -f "$filename" ]; then
    echo "File not found: $filename"
    exit 1
fi

echo "Parsing $filename:"

while IFS= read -r host; do
	echo "Testing: $host"
	# set variables
	dns_test=1
	ping_test=1
	ssh_test=1
	ipv4_test=1
	fqdn_test=1
	impossible_test=0

	if echo "$host" | grep -E -q "$ipv4_pattern"; then
		echo "$host is an IPv4 address."
		ipv4_test=0
	elif echo "$host" | grep -E -q "$fqdn_pattern"; then
		echo "$host is an FQDN hostname."
		fqdn_test=0
	else
		echo "Cannot determine if $host is an IPv4 address or an FQDN hostname."
		impossible_test=1
	fi
	
	if [ "$fqdn_test" -eq 0 ] && [ dig +short "$host" &> /dev/null ]; then
		if [ "$debug" -eq 1 ]; then
			echo "  $host is resolvable." 
	   	fi
		dns_test=0
	fi

	if ping -c 1 "$host" &> /dev/null; then
		if  [ "$debug" -eq 1 ]; then 
			echo "  $host is pingable." 
		fi
		ping_test=0
	fi
	
	if nc -z "$host" 22 &> /dev/null; then
		if [ "$debug" -eq 1 ]; then
			echo "  $host is listening on port 22."
		fi
		ssh_test=0
	fi
	
	if [ "$dns_test" -eq 0 ] && [ "$ping_test" -eq 0 ] && [ "$ssh_test" -eq 0 ]; then
		echo "  $host can be accessed."
		echo $host >> good_host_list.txt
	else
		echo $host >> bad_host_list.txt
		echo "  $host cannot be accessed."
		if [ "$dns_test" -eq 1 ]; then
			echo "  DNS check failed"
		fi
		if [ "$ping_test" -eq 1 ]; then 
			echo "  Ping test failed."
	 	fi
		if [ "$ssh_test" -eq 1 ]; then
			echo "  ssh test failed."
		fi
	fi
done < "$filename"

