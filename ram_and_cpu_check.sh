#!/bin/sh
# RAM and CPU checker, also has some java checks.
# Written by Chris Lamitie, cira September 2016 to check stats on troublesome Email Archive server written in Java.
DAY=`date +%d`
MONTH=`date +%m`
YEAR=`date +%Y`
HOUR=`date +%H`
MINUTE=`date +%M`
SECOND=`date +%S`
echo
echo "Running ram_and_cpu_check.sh at $YEAR-$MONTH-$DAY AT $HOUR:$MINUTE:$SECOND"
echo "==============================="
free -m | awk 'NR==2{printf "Memory Usage: %s/%sMB (%.2f%%)\n", $3,$2,$3*100/$2 }'
# This df command will show disk usage of the root (/) partition
#df -h | awk '$NF=="/"{printf "Disk Usage: %d/%dGB (%s)\n", $3,$2,$5}'
top -bn1 | grep load | awk '{printf "CPU Load: %.2f\n", $(NF-2)}' 
echo "top stats including java"
top -bn1 | grep -E "Mem|Swap|PID|java"

