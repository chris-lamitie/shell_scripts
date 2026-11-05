#!/bin/bash
# This script should be placed in /usr/local/bin/dynmotd.sh
# Then add /usr/local/bin/dynmotd.sh to the end of /etc/profile.d/sh.local
# so the script runs on login and has a pleasant output for the user. 
# Note, if you su - <some other account>, you this script will run again.
# This works on python3 native systems like RHEL 8+, it will have issues on
# python2 systems like RHEL7.

OSRELEASE=`cat /etc/redhat-release`

USER=`whoami`
HOSTNAME=`uname -n`

MEMORY=`free -t -m | grep "Mem" | awk '{print $3" MB / "$2" MB"}'`
SWAP=`free -t -m | grep "Swap" | awk '{print $3" MB / "$2" MB"}'`
PSA=`ps -Afl | wc -l`

KERNEL=`uname -r`
PYTHON=`python3 --version | awk '{print $2}'`

# time of day
HOUR=$(date +"%H")
if [ $HOUR -lt 12  -a $HOUR -ge 0 ]
then    TIME="morning"
elif [ $HOUR -lt 17 -a $HOUR -ge 12 ]
then    TIME="afternoon"
else
    TIME="evening"
fi

#System uptime
uptime=`cat /proc/uptime | cut -f1 -d.`
upDays=$((uptime/60/60/24))
upHours=$((uptime/60/60%24))
upMins=$((uptime/60%60))
upSecs=$((uptime%60))

#System load
LOAD=`cat /proc/loadavg | awk {'print $1", "$2", "$3'}`

echo "
===========================================================================
 - Hostname..............: $HOSTNAME
 - Operating System......: $OSRELEASE
 - Kernel................: $KERNEL
 - Users.................: Currently `users | wc -w` user(s) logged on
===========================================================================
 - CPU load avgerage.....: $LOAD (1, 5, 15 min)
 - Memory used...........: $MEMORY
 - Swap in use...........: $SWAP
 - Processes.............: $PSA running
 - System uptime.........: $upDays days $upHours hours $upMins minutes $upSecs seconds
 - Base Python Version...: $PYTHON
===========================================================================

Good $TIME $USER
"
