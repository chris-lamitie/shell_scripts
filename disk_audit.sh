#!/bin/bash
echo "===================================================================================================="
echo "Disk Health Audit Report - $(date)"
echo "Host: $(hostname)"
echo "===================================================================================================="

# ── SLOT MAP (from SES enclosure) ────────────────────────────────────────────
declare -A DEV_TO_SLOT

ENCLOSURE=$(lsscsi -g 2>/dev/null | grep -i enclo | awk '{print $7}' | head -1)

if [[ -n "$ENCLOSURE" ]]; then
    SES_OUTPUT=$(sg_ses --page=aes "$ENCLOSURE" 2>/dev/null)

    # Build SAS-address → slot-index map
    declare -A SLOT_MAP
    while read -r line; do
        if [[ $line =~ Element\ index:\ ([0-9]+) ]]; then
            INDEX="${BASH_REMATCH[1]}"
        fi
        if [[ $line =~ SAS\ address:\ (0x[0-9a-fA-F]+) ]]; then
            ADDR="${BASH_REMATCH[1]}"
            KEY="${ADDR:0:${#ADDR}-1}"   # strip last hex digit (dual-port offset)
            SLOT_MAP["$KEY"]="$INDEX"
        fi
    done <<< "$SES_OUTPUT"

    # Resolve each sd* device to a slot via its WWN
    for dev in /dev/sd?; do
        WWN=$(udevadm info --query=all --name="$dev" 2>/dev/null | grep ID_WWN= | cut -d= -f2)
        [[ -z "$WWN" ]] && continue
        KEY="${WWN:0:${#WWN}-1}"
        [[ -n "${SLOT_MAP[$KEY]}" ]] && DEV_TO_SLOT["$dev"]="${SLOT_MAP[$KEY]}"
    done
else
    echo "  [WARN] No SES enclosure found — Slot column will show '-'"
fi
# ─────────────────────────────────────────────────────────────────────────────

printf "%-15s %-6s %-20s %-10s %-8s %-15s %-15s\n" \
    "Location" "Slot" "Serial_Number" "Status" "Age_Yrs" "Non-Med_errs" "Medium_errs"
echo "----------------------------------------------------------------------------------------------------"

crit_count=0; warn_count=0; aged_count=0; ok_count=0

IS_MEGARAID=0
if /sbin/smartctl -a /dev/sda 2>&1 | grep -q "MegaRaid"; then
    IS_MEGARAID=1
    ITER_LIST=$(seq 0 24)
else
    ITER_LIST=$(/bin/lsblk -dno name | grep '^sd')
fi

for item in $ITER_LIST; do
    if [ "$IS_MEGARAID" -eq 1 ]; then
        loc_label="Slot_$item"
        smart_data=$(/sbin/smartctl -d megaraid,"$item" -a /dev/sda 2>/dev/null)
        [[ ! "$smart_data" =~ "Serial number" ]] && continue
        un_corr=$(/sbin/smartctl -d megaraid,"$item" -l error /dev/sda 2>/dev/null | grep -i "read:" | awk '{print $NF}')
        slot="-"   # SES slot lookup not applicable through MegaRAID
    else
        loc_label="/dev/$item"
        smart_data=$(/sbin/smartctl -a "$loc_label" 2>/dev/null)
        un_corr=$(/sbin/smartctl -l error "$loc_label" 2>/dev/null | grep -i "read:" | awk '{print $NF}')
        slot="${DEV_TO_SLOT[$loc_label]:-?}"
    fi

    # 1. Extract Serial Number
    sn=$(echo "$smart_data" | grep -i "Serial number" | awk '{print $NF}')
    [[ -z "$sn" ]] && sn="Unknown"

    # 2. Parse Errors
    non_med=$(echo "$smart_data" | grep "Non-medium error count" | awk '{print $4}')
    [[ -z "$non_med" ]] && non_med=0
    [[ -z "$un_corr" ]] && un_corr=0

    # 3. Age Calculation
    hours=$(echo "$smart_data" | grep -i "number of hours powered up" | awk -F'=' '{print $2}' | xargs)
    [[ -z "$hours" ]] && hours=$(echo "$smart_data" | grep "Power_On_Hours" | awk '{print $10}')
    if [[ -n "$hours" && "$hours" != "N/A" ]]; then
        age_yrs=$(echo "$hours" | awk '{printf "%.1f", $1 / 8760}')
    else
        age_yrs="0.0"
    fi

    # 4. Triage Logic
    status="OK"
    if [ "$non_med" -gt 5000 ] || [[ "$un_corr" != "0" && "$un_corr" != "" ]]; then
        status="CRITICAL"; ((crit_count++))
    elif [ "$non_med" -gt 100 ]; then
        status="WARNING"; ((warn_count++))
    elif (( $(echo "$age_yrs > 5.0" | bc -l) )); then
        status="AGED"; ((aged_count++))
    else
        ((ok_count++))
    fi

    # 5. Print row
    printf "%-15s %-6s %-20s %-10s %-8s %-15s %-15s\n" \
        "$loc_label" "$slot" "$sn" "$status" "$age_yrs" "$non_med" "$un_corr"
done

echo "----------------------------------------------------------------------------------------------------"
echo "SUMMARY FOR $(hostname):"
echo "  CRITICAL: $crit_count | WARNING: $warn_count | AGED: $aged_count | HEALTHY: $ok_count"
echo ""
echo "THRESHOLDS & ACTIONS:"
echo "  CRITICAL : Medium_errs > 0 OR Non-Med_errs > 5000. Action: Replace/Drain immediately."
echo "  WARNING  : Non-Med_errs > 100. Action: Monitor for 24h; check cables/backplane if increasing."
echo "  AGED     : Age_Yrs > 5.0. Action: Drive is past warranty; prioritize replacement during maintenance."
echo "===================================================================================================="
