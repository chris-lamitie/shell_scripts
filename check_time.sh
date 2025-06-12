#!/bin/bash
###############################################################################
# CG Lamitie, 2025-06-12
#
# check_time.sh
#
# This bash script chronyd time services and offset against its local settings 
# and a non-local time source.  It logs results to the local logger and sends 
# email alerts on negative results.
#
# Package requirements: 
#    sendmail (via postfix)
#    ntpdate (via ntpsec found in the epel repo for RHEL8+, 'ntpdate' in RHEL7 & Debian)
#
# Tested on RHEL 9 and clones like Rocky and Alma Linux. 
###############################################################################

# Define variables
DEBUG=false # set to true for std output
LOG_TAG="time-sync-check"
EMAIL_RECIPIENT="chris.lamitie@consolidatedtrading.com"
HOSTNAME=$(hostname)
OFFSET_THRESHOLD_MS=50
EMAIL_TRIGGERED=false

send_email_alert() {
    local subject="$1"
    local message="$2"
    echo -e "Subject: ${subject}\n\n${message}" | sendmail "${EMAIL_RECIPIENT}"
    if [ $? -eq 0 ]; then
        logger -i -t "${LOG_TAG}" -p "daemon.info" "Email alert sent to ${EMAIL_RECIPIENT} re: ${subject}"
    else
        logger -i -t "${LOG_TAG}" -p "daemon.err" "Failed to send email alert: ${subject}"
    fi
}

logger -i -t "${LOG_TAG}" -p "daemon.info" "Beginning time checks on $HOSTNAME."

# 1. Check if chronyd's service exists
systemctl list-unit-files | grep chronyd.service &>/dev/null
if [ $? -ne 0 ]; then
    logger -i -t "${LOG_TAG}" -p "daemon.err" "chronyd service is NOT present. The check_time.sh exited with status 1"
    ALERT_SUBJECT="System Time Alert for ${HOSTNAME} - chronyd.service is NOT present"
    ALERT_MESSAGE="The chronyd service is NOT present on $HOSTNAME!\n\nPlease investigate."
    send_email_alert "${ALERT_SUBJECT}" "${ALERT_MESSAGE}"
    if ${DEBUG}; then
        printf "The chronyd service is NOT present on $HOSTNAME!\n"
    fi
    exit 1
else
    logger -i -t "${LOG_TAG}" -p "daemon.info" "chronyd service is present."
    if ${DEBUG}; then
        printf "The chronyd service is present on $HOSTNAME!\n"
    fi
fi

# 2. Check if chronyd is active
systemctl is-active chronyd &>/dev/null
if [ $? -ne 0 ]; then
    logger -i -t "${LOG_TAG}" -p "daemon.err" "chronyd service is NOT active."
    CHRONYD_ACTIVE="FAILURE"
    EMAIL_TRIGGERED=true
    EMAIL_MESSAGE_CHRONYD_ACTIVE="chronyd service is NOT active!\n"
    if ${DEBUG}; then
        printf "chronyd service is NOT active!\n"
    fi
else
    logger -i -t "${LOG_TAG}" -p "daemon.info" "chronyd service is active."
    if ${DEBUG}; then
        printf "chronyd service is active on $HOSTNAME!\n"
    fi
fi

# 3. Check chrony RMS offset using 'chronyc tracking'
CHRONY_RMS_OFFSET=$(chronyc tracking | grep "RMS offset" | awk '{print $4}')
CHRONY_RMS_OFFSET_ABS=$(echo "${CHRONY_RMS_OFFSET}" | awk '{print ($1 < 0 ? -$1 : $1)}')
OFFSET_THRESHOLD_SECONDS=$(awk "BEGIN {printf \"%.9f\n\", $OFFSET_THRESHOLD_MS / 1000}")

if awk -v abs_offset="$CHRONY_RMS_OFFSET_ABS" -v threshold="$OFFSET_THRESHOLD_SECONDS" 'BEGIN {exit !(abs_offset > threshold)}'; then
    logger -i -t "${LOG_TAG}" -p "daemon.err" "chronyc RMS offset (${CHRONY_RMS_OFFSET}s) EXCEEDS threshold (${OFFSET_THRESHOLD_SECONDS}s)."
    CHRONY_OFFSET_CHECK="FAILURE"
    EMAIL_TRIGGERED=true
    EMAIL_CHRONY_OFFSET_MESSAGE="chronyc RMS offset (${CHRONY_RMS_OFFSET}s) EXCEEDS the threshold of (${OFFSET_THRESHOLD_SECONDS}s)!\n"
    if ${DEBUG}; then
        printf "chronyc RMS offset (${CHRONY_RMS_OFFSET}s) EXCEEDS the threshold of (${OFFSET_THRESHOLD_SECONDS}s)!\n"
    fi
else
    logger -i -t "${LOG_TAG}" -p "daemon.info" "Chrony RMS offset (${CHRONY_RMS_OFFSET}s) is WITHIN threshold (${OFFSET_THRESHOLD_SECONDS}s)."
    if ${DEBUG}; then
        printf "chronyc RMS offset (${CHRONY_RMS_OFFSET}s) is within the threshold of (${OFFSET_THRESHOLD_SECONDS}s)!\n"
    fi
fi

# 4. Check time offset with external time source using ntpdate
EXTERNAL_NTP_SERVER="time-a-g.nist.gov"
NTPDATE_QUERY_OUTPUT=$(ntpdate -q "${EXTERNAL_NTP_SERVER}" | awk '{print $4}')
NTPDATE_QUERY_OUTPUT_ABS=$(echo "${NTPDATE_QUERY_OUTPUT}" | awk '{print ($1 < 0 ? -$1 : $1)}')

if awk -v abs_offset="$NTPDATE_QUERY_OUTPUT_ABS" -v threshold="$OFFSET_THRESHOLD_SECONDS" 'BEGIN {exit !(abs_offset > threshold)}'; then
    logger -i -t "${LOG_TAG}" -p "daemon.err" "External time query of $EXTERNAL_NTP_SERVER has an offset of (${NTPDATE_QUERY_OUTPUT}s) which EXCEEDS the threshold of (${OFFSET_THRESHOLD_SECONDS}s)."
    EXTERNAL_OFFSET_CHECK="FAILURE"
    EMAIL_TRIGGERED=true
    EMAIL_EXTERNAL_TIME_MESSAGE="External time query of $EXTERNAL_NTP_SERVER has an offset of (${NTPDATE_QUERY_OUTPUT}s) EXCEEDS the threshold of (${OFFSET_THRESHOLD_SECONDS}s)!\n"
    if ${DEBUG}; then
        printf "External time query of $EXTERNAL_NTP_SERVER has an offset of (${NTPDATE_QUERY_OUTPUT}s) EXCEEDS the threshold of (${OFFSET_THRESHOLD_SECONDS}s)!\n"
    fi
else
    logger -i -t "${LOG_TAG}" -p "daemon.info" "External time query of $EXTERNAL_NTP_SERVER has an offset of (${NTPDATE_QUERY_OUTPUT}s) is within threshold (${OFFSET_THRESHOLD_SECONDS}s)."
    if ${DEBUG}; then
        printf "External time query of $EXTERNAL_NTP_SERVER has an offset of (${NTPDATE_QUERY_OUTPUT}s) is within the threshold of (${OFFSET_THRESHOLD_SECONDS}s)!\n"
    fi
fi

# Send email alert if any condition failed
if ${EMAIL_TRIGGERED}; then
    EMAIL_SUBJECT="System Time Alert for ${HOSTNAME}"
    FULL_ALERT_MESSAGE="One or more time conditions failed on ${HOSTNAME}:\n\n"
    [ "${CHRONYD_ACTIVE}" == "FAILURE" ] && FULL_ALERT_MESSAGE+="* ${EMAIL_MESSAGE_CHRONYD_ACTIVE}\n"
    [ "${CHRONY_OFFSET_CHECK}" == "FAILURE" ] && FULL_ALERT_MESSAGE+="* ${EMAIL_CHRONY_OFFSET_MESSAGE}"
    [ "${CHRONY_OFFSET_CHECK}" == "FAILURE" ] && FULL_ALERT_MESSAGE+="(RMS stands for Root Mean Square. This value represents the historical average of the time offsets between your system and the NTP server over a period. A value over $OFFSET_THRESHOLD_MS ms indicates that there have been significant time jumps in the past.)\n\n"
    [ "${EXTERNAL_OFFSET_CHECK}" == "FAILURE" ] && FULL_ALERT_MESSAGE+="* ${EMAIL_EXTERNAL_TIME_MESSAGE}\n"
    send_email_alert "${EMAIL_SUBJECT}" "${FULL_ALERT_MESSAGE}"
    logger -i -t "${LOG_TAG}" ""
fi

logger -i -t "${LOG_TAG}" -p "daemon.info" "Finished time checks on $HOSTNAME."

exit 0
