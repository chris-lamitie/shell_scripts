#!/usr/bin/bash
########################################################
# topsave.sh
#
# Collects topdata to a file. It should be
# run from cron every minute. Saves to /var/tmp/topsave/
# and makes day of week dir that only root can access.
#
# * * * * * /root/bin/topsave
########################################################
#variables
STATE_OK=0
STATE_CRITICAL=1
GROUP="root"
VER=`date +"%H%M"`
DAY=`date +"%A"`
TARGET="/var/tmp/topsave"

###############################################
# function for error checking in a shell      #
# script                                      #
###############################################
function chkerr_exit {
     $@
     if [ $? -ne 0 ]
     then
        # epic fail.
        echo "failed executing $@ "
        exit $STATE_CRITICAL
     fi
}



###############################################
# ok, lets chek our variables
###############################################
if [ -z $TARGET ]
then
    echo "TARGET not set .. exiting"
        exit $STATE_CRITICAL
fi

if [ -z $DAY ]
then
    echo "DAY not set .. exiting"
        exit $STATE_CRITICAL
fi

if [ ! -d $TARGET/$DAY ]
then
    chkerr_exit "mkdir -p $TARGET/$DAY"
        chkerr_exit "chgrp $GROUP  $TARGET/$DAY"
        chkerr_exit "chmod 770 $TARGET/$DAY"
fi



if [ $VER -eq "0000" ]
then
    chkerr_exit "rm -rf $TARGET/$DAY/*"
fi

/usr/bin/top -b -n 1 > $TARGET/$DAY/$VER

exit $STATE_OK
