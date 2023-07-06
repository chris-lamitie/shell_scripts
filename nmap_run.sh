#!/bin/bash
# This script will run nmap to scan on a number of /24 subnets
# last written 2019-10-21 - Chris Lamitie
strDate=$(date +"%Y%m%d")
strDateTime=$(date +"%Y-%m-%d %H:%M")
echo "nmap scanning script started at $strDateTime."

# specify where to start counting
intStart="0"
#specify where to end counting
intEnd="255"
# a generic counter variable
i="0"

#create a directory for our scans
if [ ! -d nmap_scans ]; then
        mkdir -p nmap_scans
fi

#run a while loop
while [ $intStart -lt $intEnd ]
do
        # run nmap using the $intStart varable as the 3rd octet of a subnet
        echo "####################################"
        echo "Running nmap on 10.26.$intStart.0/24"
        echo "####################################"
        nmap -sV -O -oX nmap_scans/10.26.$intStart.0_scan.xml 10.26.$intStart.0/24
        python3 nmap_xml_parser.py -f nmap_scans/10.26.$intStart.0_scan.xml -csv nmap_scans/10.26.$intStart.0_scan.csv
        echo "------------------------------------"
        intStart=$[$intStart+1]
        i=$[$i+1]
done

echo "$i subnets evaluated."
echo "nmap scanning script took $(($SECONDS/3600)) hours : $(($SECONDS%3600/60)) minutes : $(($SECONDS%60)) seconds to run, started at $strDateTime"

exit 0

