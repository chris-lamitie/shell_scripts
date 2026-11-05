#!/usr/bin/env bash
# =============================================================================
#  hft_check.sh  —  HFT / Low-Latency Linux Tuning Audit (RHEL)
#  Checks every setting discussed in the HFT conversation.
#  Run as root for full access to all subsystems.
#  Usage:  sudo ./hft_check.sh [--no-color] [--report /path/to/report.txt]
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# CLI args
# ---------------------------------------------------------------------------
USE_COLOR=true
REPORT_FILE=""
for arg in "$@"; do
    case "$arg" in
        --no-color)      USE_COLOR=false ;;
        --report)        shift; REPORT_FILE="$1" ;;
        --report=*)      REPORT_FILE="${arg#*=}" ;;
    esac
done

# ---------------------------------------------------------------------------
# Colour / output helpers
# ---------------------------------------------------------------------------
if $USE_COLOR && [ -t 1 ]; then
    RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
    RED=''; YELLOW=''; GREEN=''; CYAN=''; BOLD=''; RESET=''
fi

PASS=0; WARN=0; FAIL=0
OUTPUT_LINES=()

_print() { echo -e "$*"; OUTPUT_LINES+=("$(echo -e "$*" | sed 's/\x1b\[[0-9;]*m//g')"); }

section()  { _print "\n${BOLD}${CYAN}══════════════════════════════════════════════════════${RESET}";
             _print "${BOLD}${CYAN}  $*${RESET}";
             _print "${BOLD}${CYAN}══════════════════════════════════════════════════════${RESET}"; }

ok()       { _print "  ${GREEN}[PASS]${RESET} $*"; PASS=$((PASS+1));  }
warn()     { _print "  ${YELLOW}[WARN]${RESET} $*"; WARN=$((WARN+1)); }
fail()     { _print "  ${RED}[FAIL]${RESET} $*"; FAIL=$((FAIL+1));   }
info()     { _print "  ${BOLD}[INFO]${RESET} $*"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        _print "${YELLOW}WARNING: Not running as root — some checks will be skipped or incomplete.${RESET}"
    fi
}

# ---------------------------------------------------------------------------
# Helper: read a sysctl value safely
# ---------------------------------------------------------------------------
sysctl_val() { sysctl -n "$1" 2>/dev/null || echo "UNAVAILABLE"; }

# ---------------------------------------------------------------------------
# Helper: check if a kernel cmdline param is set
# ---------------------------------------------------------------------------
cmdline_has() {
    grep -qw "$1" /proc/cmdline 2>/dev/null
}
cmdline_val() {
    grep -oP "(?<=${1}=)[^ ]+" /proc/cmdline 2>/dev/null || echo ""
}

# =============================================================================
# START
# =============================================================================
_print "${BOLD}"
_print "╔══════════════════════════════════════════════════════╗"
_print "║         HFT Low-Latency Linux Tuning Audit           ║"
_print "║                    RHEL Edition                      ║"
_print "╚══════════════════════════════════════════════════════╝${RESET}"
_print "  Host   : $(hostname -f 2>/dev/null || hostname)"
_print "  Kernel : $(uname -r)"
_print "  Date   : $(date)"
_print "  User   : $(whoami)"

check_root

# =============================================================================
# 1. NETWORK CARD / KERNEL BYPASS
# =============================================================================
section "1. NETWORK CARD & KERNEL BYPASS (Solarflare / Onload)"

# Check for Solarflare NICs
sf_nics=$(lspci 2>/dev/null | grep -iE "solarflare|xilinx" || true)
if [ -n "$sf_nics" ]; then
    ok "Solarflare/Xilinx NIC detected:"
    echo "$sf_nics" | while read -r line; do info "  $line"; done
else
    warn "No Solarflare/Xilinx NIC detected (onload requires SFC hardware)"
fi

# Check onload kernel module
if lsmod 2>/dev/null | grep -q "^onload"; then
    ok "onload kernel module is loaded"
elif modinfo onload &>/dev/null; then
    warn "onload module available but NOT loaded"
else
    fail "onload module not found — kernel bypass not active"
fi

# Check onload version / env
if command -v onload &>/dev/null; then
    ol_ver=$(onload --version 2>/dev/null | head -1 || echo "unknown")
    ok "onload binary present: $ol_ver"
else
    warn "onload binary not in PATH"
fi

# Check sfptpd (PTP time sync daemon)
if systemctl is-active --quiet sfptpd 2>/dev/null; then
    ok "sfptpd (PTP time daemon) is running"
elif systemctl list-unit-files sfptpd.service &>/dev/null 2>&1 | grep -q sfptpd; then
    fail "sfptpd is installed but NOT running — time precision degraded"
else
    warn "sfptpd not found — consider deploying for hardware-level time sync"
fi

# Check for other high-perf NICs (Mellanox/NVIDIA ConnectX)
mlx_nics=$(lspci 2>/dev/null | grep -iE "mellanox|connectx" || true)
if [ -n "$mlx_nics" ]; then
    ok "Mellanox/NVIDIA ConnectX NIC detected:"
    echo "$mlx_nics" | while read -r line; do info "  $line"; done
    if lsmod 2>/dev/null | grep -qE "^mlx5_core|^mlx4_core"; then
        ok "Mellanox driver loaded"
    else
        warn "Mellanox NIC found but driver not loaded"
    fi
fi

# =============================================================================
# 2. NUMA TOPOLOGY
# =============================================================================
section "2. NUMA TOPOLOGY & PCI LANE ALIGNMENT"

if command -v numactl &>/dev/null; then
    info "NUMA hardware layout:"
    numactl --hardware 2>/dev/null | while read -r line; do info "  $line"; done
else
    warn "numactl not installed — install with: dnf install numactl"
fi

# Check each NIC's NUMA node
info "NIC NUMA node assignments:"
for iface in /sys/class/net/*/; do
    iface_name=$(basename "$iface")
    [[ "$iface_name" == "lo" ]] && continue
    numa_node_file="$iface/device/numa_node"
    if [ -f "$numa_node_file" ]; then
        numa_node=$(cat "$numa_node_file")
        if [ "$numa_node" -ge 0 ] 2>/dev/null; then
            info "  $iface_name → NUMA node $numa_node"
        else
            warn "  $iface_name → NUMA node unset or remote (-1)"
        fi
    fi
done

# Check NUMA balancing
nb=$(sysctl_val kernel.numa_balancing)
if [ "$nb" = "0" ]; then
    ok "kernel.numa_balancing = 0 (disabled)"
else
    fail "kernel.numa_balancing = $nb (should be 0 — causes random page migration latency)"
fi

# =============================================================================
# 3. CPU CORE ISOLATION
# =============================================================================
section "3. CPU CORE ISOLATION"

# isolcpus
isolcpus_val=$(cmdline_val "isolcpus")
if [ -n "$isolcpus_val" ]; then
    ok "isolcpus=$isolcpus_val"
else
    fail "isolcpus not set on kernel cmdline — trading cores share scheduler with OS tasks"
fi

# nohz_full
nohz_val=$(cmdline_val "nohz_full")
if [ -n "$nohz_val" ]; then
    ok "nohz_full=$nohz_val (tickless cores)"
else
    fail "nohz_full not set — timer ticks can fire on trading cores (~250µs jitter)"
fi

# rcu_nocbs
rcu_val=$(cmdline_val "rcu_nocbs")
if [ -n "$rcu_val" ]; then
    ok "rcu_nocbs=$rcu_val (RCU callbacks offloaded)"
else
    fail "rcu_nocbs not set — RCU can inject unpredictable latency on isolated cores"
fi

# Check consistency of isolcpus / nohz_full / rcu_nocbs
if [ -n "$isolcpus_val" ] && [ -n "$nohz_val" ] && [ -n "$rcu_val" ]; then
    if [ "$isolcpus_val" = "$nohz_val" ] && [ "$nohz_val" = "$rcu_val" ]; then
        ok "isolcpus / nohz_full / rcu_nocbs all target same CPU set: $isolcpus_val"
    else
        warn "isolcpus ($isolcpus_val), nohz_full ($nohz_val), rcu_nocbs ($rcu_val) — sets differ, verify intent"
    fi
fi

# irqbalance
if systemctl is-active --quiet irqbalance 2>/dev/null; then
    fail "irqbalance is running — it will move IRQs onto trading cores"
else
    ok "irqbalance is NOT running"
fi

# Check NIC IRQ affinity (report only — manual verification needed)
info "NIC IRQ affinity (verify these are NOT on trading cores):"
for iface in /sys/class/net/*/; do
    iface_name=$(basename "$iface")
    [[ "$iface_name" == "lo" ]] && continue
    [ -f "$iface/device/vendor" ] || continue
    # find IRQs belonging to this NIC via /proc/interrupts
    irq_lines=$(grep -i "$iface_name" /proc/interrupts 2>/dev/null || true)
    if [ -n "$irq_lines" ]; then
        echo "$irq_lines" | while IFS= read -r line; do
            irq_num=$(echo "$line" | awk '{print $1}' | tr -d ':')
            affinity_file="/proc/irq/${irq_num}/smp_affinity_list"
            if [ -f "$affinity_file" ]; then
                aff=$(cat "$affinity_file")
                info "  IRQ $irq_num ($iface_name) → CPUs $aff"
            fi
        done
    fi
done

# =============================================================================
# 4. CPU FREQUENCY & C-STATES
# =============================================================================
section "4. CPU FREQUENCY SCALING & C-STATES"

# CPU governor
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
    if [ "$gov" = "performance" ]; then
        ok "CPU frequency governor = performance"
    else
        fail "CPU frequency governor = $gov (should be 'performance')"
    fi
else
    warn "Cannot read CPU governor — cpufreq driver may not be loaded"
fi

# intel_pstate vs acpi-cpufreq
if [ -d /sys/devices/system/cpu/intel_pstate ]; then
    pstate_status=$(cat /sys/devices/system/cpu/intel_pstate/status 2>/dev/null || echo "unknown")
    if [ "$pstate_status" = "off" ] || cmdline_has "intel_pstate=disable"; then
        ok "intel_pstate disabled — using acpi-cpufreq for predictable frequency control"
    else
        warn "intel_pstate active (status=$pstate_status) — consider disabling for deterministic freq control"
    fi
fi

# C-states via kernel cmdline
max_cstate_val=$(cmdline_val "intel_idle.max_cstate")
if [ "$max_cstate_val" = "0" ]; then
    ok "intel_idle.max_cstate=0 (deep C-states disabled)"
elif [ -n "$max_cstate_val" ]; then
    warn "intel_idle.max_cstate=$max_cstate_val (0 is recommended for HFT)"
else
    fail "intel_idle.max_cstate not set — CPU may enter deep sleep states (100s of ns wakeup latency)"
fi

proc_max_cstate=$(cmdline_val "processor.max_cstate")
if [ "$proc_max_cstate" = "1" ]; then
    ok "processor.max_cstate=1"
elif [ -n "$proc_max_cstate" ]; then
    warn "processor.max_cstate=$proc_max_cstate (1 is recommended)"
else
    warn "processor.max_cstate not explicitly set on kernel cmdline"
fi

# Check actual C-state residency (if cpupower available)
if command -v cpupower &>/dev/null; then
    info "Current C-state idle driver:"
    cpupower idle-info 2>/dev/null | grep -E "CPUidle driver|Available|Active" | \
        while read -r line; do info "  $line"; done
fi

# Hyper-Threading
ht_siblings=$(cat /sys/devices/system/cpu/cpu0/topology/thread_siblings_list 2>/dev/null || echo "")
if [ -n "$ht_siblings" ] && echo "$ht_siblings" | grep -q ','; then
    fail "Hyper-Threading appears ENABLED (siblings: $ht_siblings) — disable in BIOS for HFT"
else
    ok "Hyper-Threading appears DISABLED (single thread per core)"
fi

# Total CPUs online
cpu_count=$(nproc --all 2>/dev/null || grep -c processor /proc/cpuinfo)
cpu_online=$(nproc 2>/dev/null || echo "?")
info "CPUs: $cpu_online online / $cpu_count total"

# =============================================================================
# 5. MEMORY SETTINGS
# =============================================================================
section "5. MEMORY: HUGEPAGES, NUMA, THP, SWAP"

# Hugepages
hp_total=$(sysctl_val vm.nr_hugepages)
hp_free=$(cat /sys/kernel/mm/hugepages/hugepages-2048kB/free_hugepages 2>/dev/null || echo "?")
hp_size=$(cat /sys/kernel/mm/hugepages/hugepages-2048kB/hugepages-2048kB 2>/dev/null || echo "2048kB")
if [ "$hp_total" -gt 0 ] 2>/dev/null; then
    ok "Hugepages (2MB): $hp_total total, $hp_free free"
else
    warn "vm.nr_hugepages = 0 — hugepages not allocated (recommended for HFT heap/ring buffers)"
fi

# 1GB hugepages
hp_1g=$(cat /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages 2>/dev/null || echo "0")
if [ "$hp_1g" -gt 0 ] 2>/dev/null; then
    ok "1GB hugepages: $hp_1g allocated"
else
    info "1GB hugepages: none (optional but useful for large buffers)"
fi

# THP setting
thp_enabled=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || echo "unavailable")
thp_defrag=$(cat /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || echo "unavailable")
if echo "$thp_enabled" | grep -q '\[never\]'; then
    ok "Transparent Hugepages (THP) = never"
elif echo "$thp_enabled" | grep -q '\[madvise\]'; then
    ok "THP = madvise (acceptable — explicit control)"
else
    fail "THP = $(echo "$thp_enabled" | grep -oP '\[\w+\]') — THP compaction can cause ms-level stalls"
fi

if echo "$thp_defrag" | grep -q '\[never\]'; then
    ok "THP defrag = never"
else
    warn "THP defrag = $(echo "$thp_defrag" | grep -oP '\[\w+\]') — should be 'never' to prevent compaction stalls"
fi

# Swap
swap_total=$(free | awk '/Swap:/ {print $2}')
swap_used=$(free | awk '/Swap:/ {print $3}')
if [ "$swap_total" -eq 0 ] 2>/dev/null; then
    ok "Swap is fully disabled (swapoff -a)"
else
    fail "Swap is enabled: ${swap_total}kB total, ${swap_used}kB used — swap events on hot path are catastrophic"
fi

# vm.swappiness
swappiness=$(sysctl_val vm.swappiness)
if [ "$swappiness" -eq 0 ] 2>/dev/null; then
    ok "vm.swappiness = 0"
else
    warn "vm.swappiness = $swappiness (should be 0)"
fi

# NUMA balancing (also checked above, summarized here)
nb2=$(sysctl_val kernel.numa_balancing)
[ "$nb2" = "0" ] && ok "kernel.numa_balancing = 0 (confirmed)" || \
    fail "kernel.numa_balancing = $nb2 (disable it)"

# Dirty page writeback
dirty_ratio=$(sysctl_val vm.dirty_ratio)
dirty_bg=$(sysctl_val vm.dirty_background_ratio)
info "vm.dirty_ratio = $dirty_ratio (recommended ≤ 2)"
info "vm.dirty_background_ratio = $dirty_bg (recommended ≤ 2)"
if [ "$dirty_ratio" -le 2 ] 2>/dev/null; then
    ok "vm.dirty_ratio = $dirty_ratio"
else
    warn "vm.dirty_ratio = $dirty_ratio — writeback can steal CPU; set to 1-2"
fi
if [ "$dirty_bg" -le 2 ] 2>/dev/null; then
    ok "vm.dirty_background_ratio = $dirty_bg"
else
    warn "vm.dirty_background_ratio = $dirty_bg — background writeback too permissive"
fi

# =============================================================================
# 6. NETWORK SOCKET BUFFERS
# =============================================================================
section "6. NETWORK SOCKET BUFFERS & TUNING"

# rmem / wmem
for param in net.core.rmem_max net.core.wmem_max net.core.rmem_default net.core.wmem_default; do
    val=$(sysctl_val "$param")
    if [ "$val" = "UNAVAILABLE" ]; then
        warn "$param — unavailable"
    elif [ "$val" -ge 33554432 ] 2>/dev/null; then
        ok "$param = $val (≥ 32MB)"
    elif [ "$val" -ge 8388608 ] 2>/dev/null; then
        warn "$param = $val (< 32MB — consider increasing to 33554432+)"
    else
        fail "$param = $val (too small for HFT — recommend 33554432+)"
    fi
done

# TCP rmem / wmem
for param in net.ipv4.tcp_rmem net.ipv4.tcp_wmem; do
    val=$(sysctl_val "$param")
    info "$param = $val"
done

# Busy polling
busy_poll=$(sysctl_val net.core.busy_poll)
busy_read=$(sysctl_val net.core.busy_read)
if [ "$busy_poll" -gt 0 ] 2>/dev/null; then
    ok "net.core.busy_poll = $busy_poll µs"
else
    warn "net.core.busy_poll = 0 (consider setting to 50 for kernel socket polling)"
fi
if [ "$busy_read" -gt 0 ] 2>/dev/null; then
    ok "net.core.busy_read = $busy_read µs"
else
    warn "net.core.busy_read = 0"
fi

# NIC interrupt coalescing
info "NIC interrupt coalescing (rx-usecs=0 recommended for minimum latency):"
for iface in /sys/class/net/*/; do
    iface_name=$(basename "$iface")
    [[ "$iface_name" == "lo" ]] && continue
    [ -f "$iface/device/vendor" ] || continue
    if command -v ethtool &>/dev/null; then
        coal=$(ethtool -c "$iface_name" 2>/dev/null || true)
        if [ -n "$coal" ]; then
            rx_usecs=$(echo "$coal" | awk '/^rx-usecs:/ {print $2}')
            tx_usecs=$(echo "$coal" | awk '/^tx-usecs:/ {print $2}')
            adaptive=$(echo "$coal" | awk '/^Adaptive RX:/ {print $3}')
            if [ "$rx_usecs" = "0" ] && [ "${adaptive,,}" = "off" ]; then
                ok "$iface_name: rx-usecs=0, adaptive=off"
            else
                warn "$iface_name: rx-usecs=${rx_usecs:-?}, tx-usecs=${tx_usecs:-?}, adaptive-rx=${adaptive:-?} (set rx-usecs=0, disable adaptive)"
            fi
        fi
    fi
done

# NIC hardware timestamping
info "NIC hardware timestamping support:"
for iface in /sys/class/net/*/; do
    iface_name=$(basename "$iface")
    [[ "$iface_name" == "lo" ]] && continue
    [ -f "$iface/device/vendor" ] || continue
    if command -v ethtool &>/dev/null; then
        ts=$(ethtool -T "$iface_name" 2>/dev/null || true)
        if echo "$ts" | grep -q "hardware-receive"; then
            ok "$iface_name: hardware RX timestamps available"
        elif [ -n "$ts" ]; then
            warn "$iface_name: hardware RX timestamps NOT available — software timestamps only"
        fi
    fi
done

# =============================================================================
# 7. KERNEL CMDLINE — SPECTRE/MELTDOWN & MISC
# =============================================================================
section "7. KERNEL CMDLINE — SPECTRE/MELTDOWN MITIGATIONS"

if cmdline_has "mitigations=off"; then
    ok "mitigations=off (Spectre/Meltdown patches disabled — expected on isolated HFT servers)"
else
    warn "mitigations=off NOT set — CPU vulnerability mitigations active (measurable overhead at sub-µs scale)"
    info "  Note: Only disable on isolated, physically secured servers"
fi

# Specific mitigation flags
for flag in nospectre_v1 nospectre_v2 nospec_store_bypass_disable no_stf_barrier; do
    cmdline_has "$flag" && info "  Mitigation flag: $flag is set" || true
done

info "Full kernel cmdline:"
info "  $(cat /proc/cmdline)"

# =============================================================================
# 8. KERNEL VERSION & PREEMPTION
# =============================================================================
section "8. KERNEL: VERSION, PREEMPTION & RT"

kernel_ver=$(uname -r)
info "Kernel: $kernel_ver"

# Check for RT kernel
if echo "$kernel_ver" | grep -qiE "rt|realtime"; then
    ok "PREEMPT_RT (real-time) kernel detected"
else
    warn "Standard kernel — not PREEMPT_RT. RT kernel gives more deterministic latency"
fi

# Check preemption model from kernel config (if available)
kernel_config="/boot/config-$(uname -r)"
if [ -f "$kernel_config" ]; then
    preempt=$(grep "^CONFIG_PREEMPT" "$kernel_config" | head -5)
    info "Kernel preemption config:"
    echo "$preempt" | while read -r line; do info "  $line"; done
    if grep -q "CONFIG_PREEMPT_RT=y" "$kernel_config"; then
        ok "CONFIG_PREEMPT_RT=y (full RT preemption)"
    elif grep -q "CONFIG_PREEMPT=y" "$kernel_config"; then
        warn "CONFIG_PREEMPT=y (voluntary preemption — better than server default, not as good as RT)"
    elif grep -q "CONFIG_PREEMPT_VOLUNTARY=y" "$kernel_config"; then
        warn "CONFIG_PREEMPT_VOLUNTARY=y (minimal preemption)"
    fi
fi

# =============================================================================
# 9. BIOS / POWER SETTINGS (what we can observe from userspace)
# =============================================================================
section "9. BIOS & POWER SETTINGS (userspace-visible)"

# ACPI ASPM
info "PCIe ASPM (Active State Power Management):"
if command -v lspci &>/dev/null; then
    aspm_enabled=$(lspci -vv 2>/dev/null | grep -c "ASPM.*Enabled" || echo "0")
    aspm_disabled=$(lspci -vv 2>/dev/null | grep -c "ASPM.*Disabled" || echo "0")
    if [ "$aspm_enabled" -gt 0 ] 2>/dev/null; then
        fail "ASPM enabled on $aspm_enabled device(s) — adds PCIe transaction latency. Disable in BIOS"
    else
        ok "ASPM appears disabled on all detected PCIe devices"
    fi
    # Check kernel ASPM policy
    aspm_policy=$(cat /sys/module/pcie_aspm/parameters/policy 2>/dev/null || echo "unavailable")
    info "  Kernel ASPM policy: $aspm_policy"
fi

# Check if pcie_aspm=off on cmdline
if cmdline_has "pcie_aspm=off"; then
    ok "pcie_aspm=off on kernel cmdline"
else
    warn "pcie_aspm=off not on kernel cmdline (also disable in BIOS)"
fi

# BIOS performance profile (detectable via cpupower or dmidecode)
if command -v dmidecode &>/dev/null && [ "$EUID" -eq 0 ]; then
    bios_ver=$(dmidecode -t bios 2>/dev/null | grep -E "Version|Release" | head -2 | \
               awk '{print $NF}' | tr '\n' ' ')
    info "BIOS version: $bios_ver"
fi

# Turbo boost
if [ -f /sys/devices/system/cpu/intel_turbo_boost/state ]; then
    tb=$(cat /sys/devices/system/cpu/intel_turbo_boost/state)
    [ "$tb" = "1" ] && ok "Intel Turbo Boost enabled" || warn "Intel Turbo Boost disabled (usually want this on)"
fi

# Check if CPU is running at max frequency (indicator of performance mode)
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq ] && \
   [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
    max_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq)
    cur_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
    pct=$(( cur_freq * 100 / max_freq ))
    info "CPU0 frequency: ${cur_freq}kHz / ${max_freq}kHz (${pct}%)"
    if [ "$pct" -ge 95 ]; then
        ok "CPU0 running at ≥95% of max frequency"
    else
        warn "CPU0 at only ${pct}% of max — BIOS power-saving may be active"
    fi
fi

# =============================================================================
# 10. SCHEDULER & PROCESS PRIORITY
# =============================================================================
section "10. SCHEDULER: SCHED_FIFO & PROCESS PRIORITIES"

# Check if any processes are using SCHED_FIFO / SCHED_RR
fifo_procs=$(ps -eo pid,cls,rtprio,comm 2>/dev/null | awk '$2=="FF" || $2=="RR" {print}' || true)
if [ -n "$fifo_procs" ]; then
    ok "SCHED_FIFO/SCHED_RR processes found:"
    echo "$fifo_procs" | while read -r line; do info "  $line"; done
else
    warn "No SCHED_FIFO/SCHED_RR processes detected — trading threads should use sched_setscheduler(SCHED_FIFO, 99)"
fi

# Check RT throttling (can cause latency spikes if FIFO tasks hit the limit)
rt_runtime=$(sysctl_val kernel.sched_rt_runtime_us)
rt_period=$(sysctl_val kernel.sched_rt_period_us)
if [ "$rt_runtime" = "-1" ]; then
    ok "kernel.sched_rt_runtime_us = -1 (RT tasks have unlimited CPU time)"
else
    warn "kernel.sched_rt_runtime_us = $rt_runtime / $rt_period µs — RT tasks can be throttled. Set to -1 for HFT"
fi

# =============================================================================
# 11. MEMORY LOCKING & PAGE FAULTS
# =============================================================================
section "11. MEMORY LOCKING (mlockall)"

# Check ulimit for memlock
memlock_limit=$(ulimit -l 2>/dev/null || echo "unknown")
info "Current shell memlock limit: ${memlock_limit} kB"
if [ "$memlock_limit" = "unlimited" ]; then
    ok "memlock ulimit = unlimited"
elif [ "$memlock_limit" = "unknown" ]; then
    warn "Cannot determine memlock limit"
else
    warn "memlock ulimit = ${memlock_limit}kB — should be 'unlimited' for mlockall(MCL_CURRENT|MCL_FUTURE)"
fi

# Check /etc/security/limits.conf for memlock settings
if grep -rqE "memlock.*unlimited" /etc/security/limits.conf /etc/security/limits.d/ 2>/dev/null; then
    ok "memlock = unlimited found in /etc/security/limits.conf or limits.d/"
else
    warn "No 'memlock unlimited' found in /etc/security/limits.conf — add: '* - memlock unlimited'"
fi

# =============================================================================
# 12. I/O & DISK (logging path)
# =============================================================================
section "12. I/O & DISK (logging path)"

# Check for tmpfs mounts (for RAM-based logging)
tmpfs_mounts=$(mount | grep tmpfs | grep -v "^tmpfs on /dev\|^tmpfs on /run\|^tmpfs on /sys" || true)
if [ -n "$tmpfs_mounts" ]; then
    ok "tmpfs mounts found (suitable for low-latency logging):"
    echo "$tmpfs_mounts" | while read -r line; do info "  $line"; done
else
    warn "No application tmpfs mounts — consider tmpfs for on-path log writes"
fi

# Check disk schedulers for any persistent storage
info "Block device I/O schedulers:"
for sched_file in /sys/block/*/queue/scheduler; do
    dev=$(echo "$sched_file" | cut -d/ -f4)
    scheduler=$(cat "$sched_file" 2>/dev/null || echo "unknown")
    active=$(echo "$scheduler" | grep -oP '\[\w+\]' | tr -d '[]')
    if [[ "$active" =~ ^(none|noop|mq-deadline)$ ]]; then
        ok "  $dev: scheduler = $active"
    else
        warn "  $dev: scheduler = $active (consider 'none' or 'noop' for NVMe, 'mq-deadline' for HDDs)"
    fi
done

# =============================================================================
# 13. COMPILER / CACHE-LINE CHECKS (system-level proxies)
# =============================================================================
section "13. CACHE & ARCHITECTURE INFO"

# Cache line size
cl_size=$(cat /sys/devices/system/cpu/cpu0/cache/index0/coherency_line_size 2>/dev/null || \
          getconf LEVEL1_DCACHE_LINESIZE 2>/dev/null || echo "unknown")
info "L1D cache line size: ${cl_size} bytes"
[ "$cl_size" = "64" ] && ok "Cache line = 64 bytes (expected for x86_64)" || \
    warn "Cache line = $cl_size bytes (unexpected — verify false-sharing padding)"

# Cache sizes
for idx in 0 1 2 3; do
    cache_dir="/sys/devices/system/cpu/cpu0/cache/index${idx}"
    [ -d "$cache_dir" ] || continue
    cache_type=$(cat "$cache_dir/type" 2>/dev/null || echo "?")
    cache_level=$(cat "$cache_dir/level" 2>/dev/null || echo "?")
    cache_size=$(cat "$cache_dir/size" 2>/dev/null || echo "?")
    info "  Cache L${cache_level} ${cache_type}: ${cache_size}"
done

# NUMA distance matrix
if command -v numactl &>/dev/null; then
    info "NUMA distance matrix:"
    numactl --hardware 2>/dev/null | grep -A20 "node distances" | \
        while read -r line; do info "  $line"; done
fi

# =============================================================================
# 14. MISCELLANEOUS KERNEL SETTINGS
# =============================================================================
section "14. MISCELLANEOUS KERNEL SETTINGS"

# NMI watchdog
nmi=$(sysctl_val kernel.nmi_watchdog)
if [ "$nmi" = "0" ]; then
    ok "kernel.nmi_watchdog = 0 (disabled — avoids PMU interference)"
else
    warn "kernel.nmi_watchdog = $nmi (consider disabling: can interrupt isolated cores)"
fi

# Kernel watchdog / softlockup
softlockup=$(sysctl_val kernel.soft_watchdog)
if [ "$softlockup" = "0" ] 2>/dev/null; then
    ok "kernel.soft_watchdog = 0"
else
    info "kernel.soft_watchdog = ${softlockup} (consider disabling on isolated cores)"
fi

# Perf events (can cause NMI interrupts)
perf_enabled=$(sysctl_val kernel.perf_event_paranoid)
info "kernel.perf_event_paranoid = $perf_enabled"

# Watchdog cpumask — should exclude isolated cores
watchdog_mask_file="/proc/sys/kernel/watchdog_cpumask"
if [ -f "$watchdog_mask_file" ]; then
    wdog_mask=$(cat "$watchdog_mask_file")
    info "kernel.watchdog_cpumask = $wdog_mask (should exclude trading cores)"
fi

# Transparent network stack settings
for param in net.ipv4.tcp_timestamps net.ipv4.tcp_sack net.ipv4.tcp_low_latency; do
    val=$(sysctl_val "$param" 2>/dev/null || echo "N/A")
    info "$param = $val"
done

tcp_ll=$(sysctl_val net.ipv4.tcp_low_latency 2>/dev/null || echo "N/A")
if [ "$tcp_ll" = "1" ]; then
    ok "net.ipv4.tcp_low_latency = 1"
elif [ "$tcp_ll" = "N/A" ]; then
    info "net.ipv4.tcp_low_latency not available on this kernel (removed in 4.14+)"
else
    warn "net.ipv4.tcp_low_latency = $tcp_ll"
fi

# =============================================================================
# SUMMARY
# =============================================================================
total=$((PASS + WARN + FAIL))

_print ""
_print "${BOLD}${CYAN}══════════════════════════════════════════════════════${RESET}"
_print "${BOLD}  AUDIT SUMMARY${RESET}"
_print "${BOLD}${CYAN}══════════════════════════════════════════════════════${RESET}"
_print "  Total checks : $total"
_print "  ${GREEN}PASS${RESET}         : $PASS"
_print "  ${YELLOW}WARN${RESET}         : $WARN"
_print "  ${RED}FAIL${RESET}         : $FAIL"
_print ""

if [ "$FAIL" -eq 0 ] && [ "$WARN" -le 3 ]; then
    _print "  ${GREEN}${BOLD}System appears well-tuned for HFT workloads.${RESET}"
elif [ "$FAIL" -le 3 ]; then
    _print "  ${YELLOW}${BOLD}Minor issues found — review FAILs and WARNs above.${RESET}"
else
    _print "  ${RED}${BOLD}Significant tuning gaps detected — review FAILs above.${RESET}"
fi
_print ""
_print "  Top priorities (if any FAILs above):"
_print "    1. intel_idle.max_cstate=0 + nohz_full + rcu_nocbs on same CPU set"
_print "    2. Swap disabled (swapoff -a)"
_print "    3. NUMA-local memory binding (numactl --membind)"
_print "    4. irqbalance disabled, NIC IRQs pinned away from trading cores"
_print "    5. SCHED_FIFO(99) on hot threads + sched_rt_runtime_us=-1"
_print "${BOLD}${CYAN}══════════════════════════════════════════════════════${RESET}"

# ---------------------------------------------------------------------------
# Write report file if requested
# ---------------------------------------------------------------------------
if [ -n "$REPORT_FILE" ]; then
    {
        echo "HFT Tuning Audit Report"
        echo "Host   : $(hostname -f 2>/dev/null || hostname)"
        echo "Kernel : $(uname -r)"
        echo "Date   : $(date)"
        echo "========================================================"
        for line in "${OUTPUT_LINES[@]}"; do echo "$line"; done
    } > "$REPORT_FILE"
    echo ""
    echo "Report written to: $REPORT_FILE"
fi
