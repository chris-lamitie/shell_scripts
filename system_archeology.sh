#!/usr/bin/env bash
#
# system_archeology.sh
#
# Take a snapshot of a Linux system's configuration and performance tuning.
#
# Collects how a system is set up (kernel boot options, sysctl values, CPU,
# NUMA, memory, disk, network and IRQ settings, tuned profiles, key /etc
# files, crontabs and installed packages) into one directory. Use it to
# record an older or undocumented server before rebuilding or migrating it,
# or to compare the tuning of two hosts.
#
# How it works:
#   - Writes everything to /root/<host>_system_archeology_<YYYYmmdd>/, with
#     a subdirectory per area: boot, sysctl, cpu, numa, memory, io, network,
#     irq, tuned, etc, var/spool, packages.
#   - Command output goes into .txt files. The first line of each file is
#     the command that produced it.
#   - Config files and /sys settings are copied as-is (cp -a).
#   - It only reads from the system. Nothing is changed.
#   - Failures don't stop the run. A missing tool, file or failed command
#     prints a "[!]" warning and the script continues.
#
# Compatibility:
#   Runs on any Linux system, but some parts assume an RPM-based distro
#   (RHEL, CentOS, Rocky, Alma, Fedora): rpm -qa, /etc/yum*, grubby and
#   /boot/grub2/grub.cfg. On other distros those parts only print
#   warnings or "No such file" errors.
#
# SECURITY WARNING:
#   The output includes /etc/shadow (password hashes), sudoers, Kerberos and
#   Samba config, and possibly other credentials. Treat the output directory
#   as sensitive: keep it root-only and delete or encrypt it after use.
#
# Notes:
#   - Run as root. Many files and settings are only readable by root.
#   - Running it again the same day adds to the existing directory and
#     overwrites files already there.
#   - Optional tools (used if installed): grubby, cpupower, numactl,
#     numastat, ethtool, tuned-adm.
#
# Usage:
#   sudo ./system_archeology.sh
#   tar czf /root/$(hostname -s)_archeology.tgz -C /root <output dir>   # to copy off-host
#

set -uo pipefail

#TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TIMESTAMP=$(date +"%Y%m%d")
HOSTNAME=$(hostname -s)
OUTDIR="/root/${HOSTNAME}_system_archeology_${TIMESTAMP}"
mkdir -p "${OUTDIR}"

########################################
# Helpers
########################################
log() {
  echo "[*] $1"
}

warn() {
  echo "[!] $1" >&2
}

cmd_exists() {
  command -v "$1" >/dev/null 2>&1
}

save() {
  local cmd="$1"
  local file="$2"
  echo "### COMMAND: $cmd" > "${file}"
  if ! bash -c "$cmd" >> "${file}" 2>&1; then
    warn "Command failed: $cmd"
  fi
}

copy_if_exists() {
  local src="$1"
  local dst="$2"
  if [[ -e "$src" ]]; then
    cp -a "$src" "$dst"
  else
    warn "Missing: $src"
  fi
}

########################################
# Basic system identity
########################################
log "Saving basic system information"
save "hostnamectl" "${OUTDIR}/hostnamectl.txt"
save "uname -a" "${OUTDIR}/uname.txt"
save "cat /etc/os-release" "${OUTDIR}/os-release.txt"
save "uptime" "${OUTDIR}/uptime.txt"

########################################
# Bootloader & kernel
########################################
log "Collecting bootloader and kernel settings"
mkdir -p "${OUTDIR}/boot"
save "cat /proc/cmdline" "${OUTDIR}/boot/proc_cmdline.txt"
copy_if_exists "/etc/default/grub" "${OUTDIR}/boot"
copy_if_exists "/boot/grub2/grub.cfg" "${OUTDIR}/boot"

if cmd_exists grubby; then
  save "grubby --info=ALL" "${OUTDIR}/boot/grubby.txt"
else
  warn "grubby not installed"
fi

########################################
# Sysctl & kernel tuning
########################################
log "Collecting sysctl and kernel tunables"
mkdir -p "${OUTDIR}/sysctl"
save "sysctl -a" "${OUTDIR}/sysctl/sysctl_all.txt"
cp -a /etc/sysctl* ${OUTDIR}/sysctl

########################################
# CPU & scheduler
########################################
log "Collecting CPU and scheduler tuning"
mkdir -p "${OUTDIR}/cpu"
save "lscpu" "${OUTDIR}/cpu/lscpu.txt"

if cmd_exists cpupower; then
  save "cpupower frequency-info" "${OUTDIR}/cpu/cpupower.txt"
else
  warn "cpupower not installed"
fi

save "grep . /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null" \
     "${OUTDIR}/cpu/governors.txt"
save "cat /sys/devices/system/cpu/isolated 2>/dev/null" \
     "${OUTDIR}/cpu/isolated_cpus.txt"
save "ps -eo pid,comm,psr,cls,pri,rtprio" \
     "${OUTDIR}/cpu/process_cpu_affinity.txt"

########################################
# NUMA
########################################
log "Collecting NUMA configuration"
mkdir -p "${OUTDIR}/numa"

if cmd_exists numactl; then
  save "numactl --hardware" "${OUTDIR}/numa/hardware.txt"
else
  warn "numactl not installed"
fi

if cmd_exists numastat; then
  save "numastat" "${OUTDIR}/numa/numastat.txt"
else
  warn "numastat not installed"
fi

########################################
# Memory info & tuning
########################################
log "Collecting memory info & tuning"
mkdir -p "${OUTDIR}/memory"
save "free -h" "${OUTDIR}/memory/free.txt"
save "cat /proc/meminfo" "${OUTDIR}/memory/meminfo.txt"
save "cat /proc/buddyinfo" "${OUTDIR}/memory/buddyinfo.txt"

copy_if_exists "/sys/kernel/mm/transparent_hugepage" "${OUTDIR}/memory/transparent_hugepage"

########################################
# Disk & I/O
########################################
log "Collecting disk and I/O info & tuning"
mkdir -p "${OUTDIR}/io"
save "lsblk -o NAME,ROTA,SCHED,RA,DISC-GRAN,DISC-MAX" "${OUTDIR}/io/lsblk.txt"

for dev in /sys/block/*; do
  d=$(basename "$dev")
  mkdir -p "${OUTDIR}/io/${d}"
  copy_if_exists "$dev/queue" "${OUTDIR}/io/${d}"
done

########################################
# Network info & tuning
########################################
log "Collecting network info & tuning"
mkdir -p "${OUTDIR}/network"
save "ip addr show" "${OUTDIR}/network/ip_addr.txt"
save "ip route show" "${OUTDIR}/network/ip_route.txt"
save "sysctl -a | grep '^net\.'" "${OUTDIR}/network/sysctl_net.txt"

for iface in $(ls /sys/class/net | grep -v lo); do
  mkdir -p "${OUTDIR}/network/${iface}"

  if cmd_exists ethtool; then
    save "ethtool -k ${iface}" "${OUTDIR}/network/${iface}/offloads.txt"
    save "ethtool -g ${iface}" "${OUTDIR}/network/${iface}/rings.txt"
    save "ethtool -c ${iface}" "${OUTDIR}/network/${iface}/coalesce.txt"
  else
    warn "ethtool not installed"
  fi
done

########################################
# IRQs & interrupts
########################################
log "Collecting IRQ and interrupt configuration"
mkdir -p "${OUTDIR}/irq"
save "cat /proc/interrupts" "${OUTDIR}/irq/interrupts.txt"
save "systemctl status irqbalance" "${OUTDIR}/irq/irqbalance_status.txt"

########################################
# tuned profiles
########################################
log "Collecting tuned configuration"
mkdir -p "${OUTDIR}/tuned"

if cmd_exists tuned-adm; then
  save "tuned-adm active" "${OUTDIR}/tuned/active.txt"
  save "tuned-adm list" "${OUTDIR}/tuned/list.txt"
else
  warn "tuned-adm not installed"
fi

copy_if_exists "/etc/tuned" "${OUTDIR}/tuned"

########################################
# etc artifact collection
########################################
log "Collecting /etc artifacts"
mkdir -p "${OUTDIR}/etc"
cp -a /etc/aliases* ${OUTDIR}/etc/
cp -a /etc/audit* ${OUTDIR}/etc/
cp -a /etc/auto* ${OUTDIR}/etc/
cp -a /etc/chron* ${OUTDIR}/etc/
cp -a /etc/cron* ${OUTDIR}/etc/
cp -a /etc/exports* ${OUTDIR}/etc/
cp -a /etc/firewalld* ${OUTDIR}/etc/
cp -a /etc/fstab* ${OUTDIR}/etc/
cp -a /etc/group ${OUTDIR}/etc/
cp -a /etc/hba* ${OUTDIR}/etc/
cp -a /etc/host* ${OUTDIR}/etc/
cp -a /etc/kdump* ${OUTDIR}/etc/
cp -a /etc/krb5* ${OUTDIR}/etc/
cp -a /etc/logrotate* ${OUTDIR}/etc/
cp -a /etc/my* ${OUTDIR}/etc/
cp -a /etc/NetworkManager* ${OUTDIR}/etc/
cp -a /etc/nfs* ${OUTDIR}/etc/
cp -a /etc/odbc* ${OUTDIR}/etc/
cp -a /etc/passwd ${OUTDIR}/etc/
cp -a /etc/postfix* ${OUTDIR}/etc/
cp -a /etc/profile* ${OUTDIR}/etc/
cp -a /etc/resolv.conf* ${OUTDIR}/etc/
cp -a /etc/rsyncd* ${OUTDIR}/etc/
cp -a /etc/rsyslog* ${OUTDIR}/etc/
cp -a /etc/samba* ${OUTDIR}/etc/
cp -a /etc/selinux/config ${OUTDIR}/etc/selinux_config
cp -a /etc/sestatus* ${OUTDIR}/etc/
cp -a /etc/sfptpd* ${OUTDIR}/etc/
cp -a /etc/shadow ${OUTDIR}/etc/
cp -a /etc/sudo* ${OUTDIR}/etc/
cp -a /etc/systemd* ${OUTDIR}/etc/
cp -a /etc/udev* ${OUTDIR}/etc/
cp -a /etc/yum* ${OUTDIR}/etc/

#######################################
# /var/spool/cron
#######################################
log "Collecting crontabs from /var/spool/cron"
mkdir -p "${OUTDIR}/var/spool"
copy_if_exists "/var/spool/cron" "${OUTDIR}/var/spool"

########################################
# Packages
########################################
log "Collecting rpm package info"
mkdir -p "${OUTDIR}/packages"
save "rpm -qa | grep -Ei 'solar|sfc|sfu|onload|mlx|mellanox|intel|ixgbe|i40e'" \
     "${OUTDIR}/packages/networking_rpm_packages.txt"
save "rpm -qa" "${OUTDIR}/packages/all_rpm_packages.txt"

########################################
log "System archeology complete"
echo "Artifacts saved to: ${OUTDIR}"

