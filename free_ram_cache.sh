#!/bin/sh
# Written by Chris Lamitie, circa Sept. 2016
# simple drop of caches on a Linux system, also reports RAM status before and after drop command.
# script inspration taken from:
# http://unix.stackexchange.com/questions/87908/how-do-you-empty-the-buffers-and-cache-on-a-linux-system
DAY=`date +%d`
MONTH=`date +%m`
YEAR=`date +%Y`
HOUR=`date +%H`
MINUTE=`date +%M`
SECOND=`date +%S`

echo "======================================="
echo "$YEAR-$MONTH-$DAY $HOUR:$MINUTE:$SECOND"
echo "Current state of memory in MB"
free -m
echo
echo "Dropping caches now"
echo 3 > /proc/sys/vm/drop_caches
echo
echo "Memory after dropping caches"
free -m

