#!/bin/bash
# "checkmounts.sh" found on strycore's github.com repo: https://github.com/strycore/scripts/blob/master/checkmounts
# retrieved 2023-07-05
# 
# has some good work with pipes and using the Linux holy trinity together: grep, sed, and awk.
# could be better, such as checking if uid 0, which is root, then exit if not with a warning sign.
# currently though it warns and tries to run. This was made quick and dirty, and author never came
# back to optomize. Pity.
echo "Run this as root"
for DEVICE in `fdisk -l | grep ^/dev | awk '{print $1}'`;
do
	PARTITION_TYPE=`fdisk -l | grep ^$DEVICE | sed "s/*//" |awk '{print $6 $7}'`
	IS_MOUNTED=`mount | grep $DEVICE | wc -l`
	DEST=`mount | grep $DEVICE | awk '{print $3}'`
	if [ $IS_MOUNTED -eq 1 ]
	then
		echo "Drive "$DEVICE" is mounted on "$DEST"("$PARTITION_TYPE")"
	else
		if [ $PARTITION_TYPE != "Extended" -a $PARTITION_TYPE != "Linuxswap" ]; then
			echo -e "\033[1mDrive "$DEVICE" is not mounted ("$PARTITION_TYPE")\033[0m"
		fi
	fi
done
