#!/usr/bin/bash
#
# recon_nfs_export.sh
#
# Write a report of this host's mounts and NFS exports to a text file.
#
# How it works:
#   1. Creates <short-hostname>_export_report_<YYYYmmdd_HHMMSS>.txt in the
#      current directory.
#   2. Adds the contents of /etc/fstab (what is configured to be mounted).
#   3. Adds `df -h` output (what is actually mounted, with size and usage).
#   4. Reads each exported path from /etc/exports and adds its disk usage,
#      two directory levels deep (`du -hd2`).
#   The report starts and ends with "### begin/end <hostname> ###" markers,
#   so reports from several hosts can be joined into one file.
#
# Why:
#   Gives a quick record of what a server mounts and exports, and how much
#   data is in each export. Useful before migrating or cleaning up NFS
#   shares.
#
# Notes:
#   - Run as root so `du` can read every directory in the exports.
#   - `du` walks every export and can take a long time on large shares.
#   - Only /etc/exports is read; exports in /etc/exports.d/ are not included.
#   - Comment lines in /etc/exports are passed to `du` and cause harmless
#     "No such file or directory" errors.
#
# Usage:
#   sudo ./recon_nfs_export.sh
#

FILENAME=$(hostname -s)_export_report_$(date +%Y%m%d_%H%M%S).txt
echo "### begin $(hostname) ###"  >> $FILENAME
echo "" >> $FILENAME
echo "cat /etc/fstab" >> $FILENAME
cat /etc/fstab >> $FILENAME
echo "" >> $FILENAME
echo "df -h" >> $FILENAME
df -h >> $FILENAME
echo "" >> $FILENAME
echo "Disk Usage of any local NFS exports:" >> $FILENAME
cat /etc/exports | awk '{print $1}' | xargs du -hd2 >> $FILENAME
echo "### end $(hostname) ###"  >> $FILENAME
