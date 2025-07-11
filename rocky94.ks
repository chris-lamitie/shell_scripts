# Kickstart file for Rocky Linux 9.4 UEFI PXE installation
%pre
echo "Detecting the lowest PCI ID disk for OS installation..."

# Use 'find' to get the PCI paths, remove blank lines, extra spaces, and sort them
ROOT_DISK=$(find /dev/disk/by-path/ -type l | grep -v "part" | grep -v "ata" | sed 's/.*\///' | sort -V | head -n 1)

# Ensure we have a valid disk
if [ -z "$ROOT_DISK" ]; then
    echo "ERROR: No suitable OS disk found!" >&2
    exit 1
fi

# Output the chosen disk
echo "Selected OS Disk: /dev/disk/by-path/$ROOT_DISK"

# Write partitioning scheme
cat <<EOF > /tmp/partitioning.ks
ignoredisk --only-use=/dev/disk/by-path/$ROOT_DISK
clearpart --drives=/dev/disk/by-path/$ROOT_DISK --all --initlabel

part /boot --fstype=xfs --size=3072 --ondisk=/dev/disk/by-path/$ROOT_DISK
part /boot/efi --fstype=efi --size=1024 --ondisk=/dev/disk/by-path/$ROOT_DISK
part pv.0 --fstype=lvmpv --ondisk=/dev/disk/by-path/$ROOT_DISK --grow
volgroup osvg --pesize=4096 pv.0
logvol / --vgname=osvg --name=root --fstype=xfs --size=5120
logvol /home --vgname=osvg --name=home --fstype=xfs --size=3072
logvol /var/log --vgname=osvg --name=var_log --fstype=xfs --size=3072
logvol /var --vgname=osvg --name=var --fstype=xfs --size=3072
logvol /opt --vgname=osvg --name=opt --fstype=xfs --size=3072
#logvol swap --vgname=osvg --name=swap --fstype=swap --size=3072
EOF

%end

# Include the dynamically generated partitioning scheme
%include /tmp/partitioning.ks

text

# Install from URL
url --url="http://isos.example.com/rocky/9.4/isos/minimal.iso/minimal/"

# System language
lang en_US

# Keyboard layout
keyboard us

# Root password
rootpw --iscrypted --allow-ssh $6$.foobar.

# Timezone
timezone America/Chicago --utc

authselect --kickstart --profile=minimal --passalgo=sha512 --useshadow
skipx
firstboot --disable

# Disable SELinux
selinux --disabled

# Disable firewall
firewall --disabled

# Reboot after installation
reboot

# Packages
%packages
@^minimal-environment
-ivtv-firmware
-iwl*-firmware
-alsa-*firmware
%end

# User creation
user --name=ansible-user --password="$6$.foobar."

# Post-installation script
%post
echo "Creating custom udev rules to assign PCI SCSI devices to /dev/sd*..."

# Find all PCI-based SCSI devices, sort them by PCI order
DISKS=($(find /dev/disk/by-path/ -type l | grep -v "part" | grep -v "ata" | sed 's/.*\///' | sort -V))

# Ensure we found disks
if [ ${#DISKS[@]} -eq 0 ]; then
    echo "ERROR: No PCI SCSI disks found!" >&2
    exit 1
fi

# Clear any existing custom udev rules
rm -f /etc/udev/rules.d/99-persistent-disk.rules

# Assign /dev/sd* names based on PCI order
SD_LETTER=a
for DISK in "${DISKS[@]}"; do
    DISK_PATH="/dev/disk/by-path/$DISK"
    echo "Assigning $DISK_PATH to /dev/sd$SD_LETTER"
    echo "KERNEL==\"sd*\", SUBSYSTEM==\"block\", ENV{ID_PATH}==\"$DISK_PATH\", NAME=\"sd$SD_LETTER\"" >> /etc/udev/rules.d/99-persistent-disk.rules
    SD_LETTER=$(echo "$SD_LETTER" | tr "a-y" "b-z")  # Move to the next letter
done

# Reload udev rules
udevadm control --reload-rules
udevadm trigger

echo "Finished assigning all PCI SCSI devices in an order of path."

# Create the sudoers file for ansible-user
cat << EOF > /etc/sudoers.d/ansible-user
ansible-user ALL=(ALL:ALL) NOPASSWD: ALL
EOF

# add ansible-user authorized keys
mkdir -p /home/ansible-user/.ssh
chmod 700 /home/ansible-user/.ssh
echo "ssh-ed25519 AAAACfoobar" > /home/ansible-user/.ssh/authorized_keys
chmod 600 /home/ansible-user/.ssh/authorized_keys
chown -R ansible-user.ansible-user /home/ansible-user/.ssh

%end
