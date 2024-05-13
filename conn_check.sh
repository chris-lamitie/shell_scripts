#!/bin/bash

# output colors
c_red=$(tput setab 1)
c_grn=$(tput setaf 2)
c_end=$(tput sgr0)

declare -a input=("$@")

check () {
    local hosts=("$@")
    col_width=$(wc -L <<< $(for i in ${hosts[@]}; do printf "${i}\n"; done))
    printf "%-*s %s %-21s %s %s\n" "${col_width}" 'target' '|' 'ping' '|' 'nc to port 22'
    table_width=$(tput cols)
    printf '=%.0s' $(seq "${table_width}")
    printf '\n'
    for i in "${hosts[@]}"
    do
        nc_status=$(nc -vz -w2 "${i}" 22 2>&1 | awk -F':' 'BEGIN{IGNORECASE=1} /connect|timeout|could not resolve/ {print substr($2,2)}')
        ping_status=$(ping -q -w 2 -c 1 "${i}" 2>&1 | awk -F', ' '/packet loss/ {print ($--NF)}')
        if echo "${ping_status}" | grep -iqw '0% packet loss'; then
            ping_st="${c_grn}[OK]${c_end}"
        else
            ping_st="${c_red}[ X]${c_end}"
        fi
        if echo "${nc_status}" | grep -iqw 'connected to'; then
            nc_st="${c_grn}[OK]${c_end}"
        else
            nc_st="${c_red}[ X]${c_end}"
        fi
        # the star in `%-*s` is a placeholder for column width defined later by `col_width` variable
        printf "%-*s %s %s %+16s %s %s %s\n" "${col_width}" "${i}" '|' "${ping_st}" "${ping_status}" '|' "${nc_st}" "${nc_status}"
    done
}

if [[ -f "${input}" ]]; then
    readarray -t arr < "${input}"
    check "${arr[@]}"
elif [[ ! -z "${input}" ]]; then
    check "${input[@]}"
else
    echo "Usage: $0 IP [IP...]|HOSTNAME|FILE"
    exit 0
fi
