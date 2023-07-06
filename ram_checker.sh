#!/bin/sh
# RAM and CPU checker, also has some java checks.
# Written by Chris Lamitie, cira September 2016 to check stats on troublesome Email Archive server written in Java.
# then later became a teaching tool for awk
DAY=`date +%d`
MONTH=`date +%m`
YEAR=`date +%Y`
HOUR=`date +%H`
MINUTE=`date +%M`
SECOND=`date +%S`
my_uid=$(echo $EUID)
used_swap=$(cat /proc/swaps | awk 'NR>1 {swap_sum+=$4} END {print swap_sum}')
spacer="==============================="
 
echo "Running ram_and_cpu_check.sh at $YEAR-$MONTH-$DAY AT $HOUR:$MINUTE:$SECOND"
if [ $my_uid -ne 0 ]
then
        echo -e "$spacer\nNot running as root, output will be limited to uid: $my_uid\n$spacer\n"
else
        echo -e "$spacer\n"
fi
 
free -m | awk 'NR==2{printf "Current Memory Usage:       %s/%sMB (%.2f%%)\n", $3,$2,$3*100/$2 }'
free -m | awk 'NR==2{printf "Available Memory:           %s/%sMB (%.2f%%)\n", $7,$2,$7*100/$2 }'
free -m | awk 'NR==3{printf "Current Swap Usage:         %s/%sMB (%.2f%%)\n", $3,$2,$3*100/$2 }'
free -m | awk 'NR==2{printf "Current buffer/cache Usage: %s/%sMB (%.2f%%)\n", $6,$3,$6*100/$3 }'
 
# This df command will show disk usage of the root (/) partition
#df -h | awk '$NF=="/"{printf "Disk Usage: %d/%dGB (%s)\n", $3,$2,$5}'i
 
# now we check inf smem is installed, and if so, use to to display things
smem_installed=$(which smem > /dev/null 2>&1)
#echo "smem_installed exit code: $?"
if [ $? -eq 0 ]
then
        smem_ram_by_user=$(smem -uk | column -t)
        echo -e "\nsmem ram use by user:\n$spacer\n$smem_ram_by_user\n$spacer"
 
# uncomment the section below if you want to see gory details about swap through smem
#       if [ $my_uid -eq 0 ] && [ $used_swap -gt 0 ] # we are root and we are swapping,do more with smem!
#       then
#               smem_totals_sorted_swap=$(smem -tkrs swap | awk 'NR <= 41 {print}')
#               echo -e "\nTop 40 processes using swap:\n$spacer\n$smem_totals_sorted_swap\n$spacer"
#       fi
 
else
        echo -e "\nsmem is not installed. Consider installing it for more output\n$spacer"
fi
 
# now we are going to get top stats and do things with the outupt
# we could simply dump the top 20 lines of top, but this exercise
# came of learning to do things with awk to format output.
top_output=$(top -bn1 | head -n 20)
top_load_average=$(echo "$top_output" | grep load | awk '{printf "CPU 5 min. Load: %.2f\n", $(NF-2)}')
#top_memory_stats=$(echo "$top_output" | grep -E "Mem|Swap")
top_process_stats=$(echo "$top_output" | awk '/^ *PID/ {p=1} p && p++')
echo "top stats:"
echo "$top_load_average"
#echo "$top_memory_stats"
echo "$top_process_stats"
