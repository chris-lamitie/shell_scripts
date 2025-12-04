#!/bin/bash

set -euo pipefail

echo -e "Welcome to the Rocky Linux 9  WSL setup script.\n"

OS_PRETTY_NAME=$(awk -F'[="]' '/PRETTY_NAME/ {print $3}' /etc/os-release)

# The pattern to match: "Rocky Linux 9." followed by anything else
REQUIRED_PATTERN="Rocky Linux 9.*"

# 2. Check if the extracted name does NOT match the required pattern
if [[ "$OS_PRETTY_NAME" != $REQUIRED_PATTERN ]]; then
    echo "   -> ERROR: Unsupported OS distribution or version." >&2
    echo "   -> This script requires '$REQUIRED_PATTERN', but found '$OS_PRETTY_NAME'." >&2
    exit 1
fi

# --- Repository Setup (Runs regardless of SSH skip) ---
echo -e "\nFirst we will set up additional repos."
echo -e "Installing the EPEL repo.\n"
sudo dnf install epel-release -y
echo -e "Enabling Rocky CRB repo.\n"
sudo dnf config-manager --set-enabled crb

echo -e "\nSetting up PostgreSQL repos."
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# From: https://learn.microsoft.com/en-us/sql/connect/odbc/linux-mac/installing-the-microsoft-odbc-driver-for-sql-server?view=sql-server-ver17&tabs=redhat18-install%2Credhat17-install%2Cdebian8-install%2Credhat7-13-install%2Crhel7-offline
echo -e "\nSetting up Microsoft repos."
curl -sSL -O https://packages.microsoft.com/keys/microsoft.asc
curl -sSL -O https://packages.microsoft.com/config/rhel/$(grep VERSION_ID /etc/os-release | cut -d '"' -f 2 | cut -d '.' -f 1)/packages-microsoft-prod.rpm
sudo rpm --import microsoft.asc
sudo dnf install packages-microsoft-prod.rpm
rm packages-microsoft-prod.rpm
rm microsoft.asc

echo -e "\nCleaning DNF cache."
sudo dnf clean all
echo -e "\nMaking fresh DNF cache."
sudo dnf makecache -y

echo -e "\nInstalling packages"

echo -e "Do you want to install GUI packages? ('yes' or 'no'):"
read GUI_PROMPT
if [ "$GUI_PROMPT" = "no" ]; then
    echo "Skipping install of GUI as requested."
else
    echo -e "\nInstalling GUI packages"
    sudo dnf group install -y "Server with GUI"
fi

echo -e "\nInstalling other packages."
sudo dnf install -y bind-utils java-1.8.0-openjdk man-pages net-tools nmap-ncat rsync tar tmux tree unzip capnproto cmake gcc-c++ gcc-toolset-13 git jq libpcap libpcap-devel libpq5-devel libstdc++-static mono-core ninja-build postgresql16 postgresql16-devel python3.12 python3.12-devel python3.12-pip python3.12-test python3-pip python3-test zlib zlib-devel htop

echo -e "\nInstalling MSSQL17 packages."
sudo ACCEPT_EULA=Y dnf install -y msodbcsql17
sudo ACCEPT_EULA=Y dnf install -y mssql-tools
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
source ~/.bashrc
# optional: for unixODBC development headers
sudo dnf install -y unixODBC-devel

echo -e "\nSetting up MDA access."
sudo dnf install -y nfs-utils autofs

# Define the target paths for clarity
MDA_MOUNT_PATH="/mnt/autofs/nfs01.example.com/MDA"
SHARED_PATH="/shared"
TARGET_NFS="$SHARED_PATH/MDA_NFS01"
SOURCE_LINK="$MDA_MOUNT_PATH"

# Create the MDA mount point
echo -e "\nMaking MDA mount file system."
# The 'mkdir -p' command is inherently idempotent: it only creates directories if they don't exist.
# However, for a cleaner script output, we can check first.
if [ ! -d "$MDA_MOUNT_PATH" ]; then
    sudo mkdir -p "$MDA_MOUNT_PATH"
    echo "   -> Directory created: $MDA_MOUNT_PATH"
else
    echo "   -> Directory already exists: $MDA_MOUNT_PATH"
fi

# Create the /shared directory
echo -e "\nMaking /shared file system"
if [ ! -d "$SHARED_PATH" ]; then
    sudo mkdir "$SHARED_PATH"
    echo "   -> Directory created: $SHARED_PATH"
else
    echo "   -> Directory already exists: $SHARED_PATH"
fi

# ICreate the first symlink (/shared/MDA_NFS01)
if [ ! -L "$TARGET_NFS" ]; then
    sudo ln -s "$SOURCE_LINK" "$TARGET_NFS"
    echo "   -> Symlink created: $TARGET_NFS -> $SOURCE_LINK"
else
    echo "   -> Symlink already exists: $TARGET_NFS"
fi

AUTO_MASTER="/etc/auto.master"
BACKUP_FILE="$AUTO_MASTER.bak.$(date "+%Y%m%d")"

# Backup existing auto.master file if not already backed up today
echo -e "\nChecking for daily backup of $AUTO_MASTER..."
if [ ! -f "$BACKUP_FILE" ]; then
    sudo cp "$AUTO_MASTER" "$BACKUP_FILE"
    echo "   -> Backup created: $BACKUP_FILE"
else
    echo "   -> Backup already exists. Skipping backup."
fi

# Sed commands to comment out specific lines in auto.master
echo -e "\nCommenting out default autofs mounts in $AUTO_MASTER."
# Comment out /misc line
sudo sed -i '/^[[:space:]]*\/misc[[:space:]]\+\/etc\/auto\.misc/ { /^[[:space:]]*#/! s/^/#/ }' "$AUTO_MASTER"
# Comment out /net line
sudo sed -i '/^[[:space:]]*\/net[[:space:]]\+-hosts/ { /^[[:space:]]*#/! s/^/#/ }' "$AUTO_MASTER"
# Comment out +auto.master line (NIS/YP support)
sudo sed -i '/^[[:space:]]*+auto\.master/ { /^[[:space:]]*#/! s/^/#/ }' "$AUTO_MASTER"
echo "   -> Autofs defaults have been idempotently commented out."

# Define target file paths for clarity
AUTO_MASTER_D_FILE="/etc/auto.master.d/nfs01-MDA.autofs"
AUTO_MAP_FILE="/etc/auto.nfs01-MDA-ro"

# Create the Master.d configuration file
echo -e "\nChecking for $AUTO_MASTER_D_FILE..."

if [ ! -f "$AUTO_MASTER_D_FILE" ]; then
    echo "Creating autofs master configuration file: $AUTO_MASTER_D_FILE"
    sudo cat <<EOF | sudo tee "$AUTO_MASTER_D_FILE"
/-      /etc/auto.nfs01-MDA-ro       --timeout=60
EOF
    echo "   -> Successfully created $AUTO_MASTER_D_FILE."
else
    echo "   -> Configuration file already exists: $AUTO_MASTER_D_FILE. Skipping creation."
fi

# Create the Mount Map file
echo -e "\nChecking for $AUTO_MAP_FILE..."

if [ ! -f "$AUTO_MAP_FILE" ]; then
    echo "Creating autofs mount map file: $AUTO_MAP_FILE"
    sudo cat <<EOF | sudo tee "$AUTO_MAP_FILE"
/mnt/autofs/nfs01.example.com/MDA      -fstype=nfs4,ro,soft    cha-slp-knfs01:/data/exports/MDA
EOF
    echo "   -> Successfully created $AUTO_MAP_FILE."
else
    echo "   -> Mount map file already exists: $AUTO_MAP_FILE. Skipping creation."
fi

echo -e "\nRestarting autofs service to apply changes..."
sudo systemctl restart autofs

echo -e "\nEnsuring autofs service is enabled."
sudo systemctl enable autofs

echo -e "Now we will pull configuration files from another server."

# Now we will pull files from another server using SSH and SCP.
# Prompt the user for the remote hostname or IP address
echo -e "Please enter the remote hostname or IP address in the following format <username>@<hostname> OR type 'skip' to bypass SSH setup:"
read HOST

# Check for 'skip' input
if [ "$HOST" = "skip" ]; then
    echo "Skipping SSH and SCP commands as requested."
else

    # Check if the input is empty (only if not skipping)
    if [ -z "$HOST" ]; then
        echo "Error: Hostname cannot be empty. Exiting."
        exit 1
    fi

    # Local Setup for .ssh Directory
    SSH_DIR="$HOME/.ssh"
    echo -e "\nChecking local directory $SSH_DIR..."

    # Create the .ssh directory if it doesn't exist
    if [ ! -d "$SSH_DIR" ]; then
        echo "Creating directory $SSH_DIR"
        mkdir "$SSH_DIR"
    fi

    # Set the correct permissions for ~/.ssh/ dir
    echo "Setting permissions on $SSH_DIR to 700"
    chmod 700 "$SSH_DIR"

    # Execute the Secure Copy Commands
    echo -e "\nAttempting to securely copy .ssh, .ctdb, and ODBC config from $HOST..."
    echo "You will be prompted for your password for the remote host if not using keys."

    # SCP for SSH Keys
    echo -e "\nChecking for SSH key file ~/.ssh/id_ed25519 on $HOST..."
    if ssh "$HOST" 'test -f ~/.ssh/id_ed25519'; then
        scp -r "$HOST":~/.ssh/*id_* "$SSH_DIR"
    else
        echo -e "   -> Remote SSH key files not found or inaccessible. Skipping copy."
    fi

    # ODBC Configuration Setup
    ODBC_INI_SRC="$HOME/odbc.ini"
    ODBCINST_INI_SRC="$HOME/odbcinst.ini"
    ODBC_INI_DEST="/etc/odbc.ini"
    ODBCINST_INI_DEST="/etc/odbcinst.ini"

    echo -e "\n--- ODBC Configuration Setup ---"

    # Check if ODBC files are already in /etc and owned by root (Idempotent check)
    echo "Checking for and copying ODBC files from $HOST..."
    
    # Check for and copy odbc.ini
    if ssh "$HOST" 'test -f /etc/odbc.ini'; then
        scp "$HOST":/etc/odbc.ini "$ODBC_INI_SRC"
        INI_COPIED=1
    else
        echo "   -> Remote file /etc/odbc.ini not found or inaccessible. Skipping copy."
        INI_COPIED=0
    fi
    
    # Check for and copy odbcinst.ini
    if ssh "$HOST" 'test -f /etc/odbcinst.ini'; then
         scp "$HOST":/etc/odbcinst.ini "$ODBCINST_INI_SRC"
        INST_COPIED=1
    else
        echo "   -> Remote file /etc/odbcinst.ini not found or inaccessible. Skipping copy."
        INST_COPIED=0
    fi

     # Move and set ownership only if BOTH files were successfully copied
    if [ "$INI_COPIED" -eq 1 ] && [ "$INST_COPIED" -eq 1 ]; then
        echo "Moving ODBC files to $ODBC_INI_DEST..."
        sudo mv "$ODBC_INI_SRC" "$ODBC_INI_DEST"
        sudo mv "$ODBCINST_INI_SRC" "$ODBCINST_INI_DEST"

        echo "Setting ownership of ODBC files to root:root..."
        sudo chown root:root "$ODBC_INI_DEST"
        sudo chown root:root "$ODBCINST_INI_DEST"
        echo "   -> ODBC files are in /etc with correct ownership."
    else
        echo "   -> Skipping final move/chown: Not all required ODBC files were copied successfully."
        # Cleanup any partially copied files (Idempotent cleanup)
        [ -f "$ODBC_INI_SRC" ] && rm "$ODBC_INI_SRC"
        [ -f "$ODBCINST_INI_SRC" ] && rm "$ODBCINST_INI_SRC"
    fi

    # Crypto Policies Update
    echo -e "\nCrypto Policies Update"

    CURRENT_POLICY=$(sudo update-crypto-policies --show)
    TARGET_POLICY="DEFAULT:SHA1"

    if [ "$CURRENT_POLICY" != "$TARGET_POLICY" ]; then
        echo "Current policy is '$CURRENT_POLICY'. Setting to '$TARGET_POLICY'..."
        sudo update-crypto-policies --set "$TARGET_POLICY"
        echo "   -> Crypto policy updated."
    else
        echo "Crypto policy is already set to '$TARGET_POLICY'. Skipping update."
    fi

    # Completion and Verification
    # The last command in the block was the crypto policy update.
    if [ $? -eq 0 ]; then
        echo -e "\n   -> Success: SSH/SCP/Config setup completed successfully."
    else
        echo -e "\n   -> Error: The SSH/SCP block failed. Check the hostname and network connection."
    fi
fi

echo -e "\nPerform Rocky Upgrade."
sudo dnf upgrade -y
echo -e "\nSetup complete. Please poweroff then start your WSL instance to apply all changes. (Kernel updates, crypto policies, etc.)\n"
echo -e "You can poweroff WSL by running 'sudo poweroff' from your Command Prompt, wait 60 seconds, then reopen your WSL terminal.\n"
