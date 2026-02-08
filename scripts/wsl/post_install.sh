#!/usr/bin/env bash

# Create your user (replace 'dev' with your preference) 
useradd -m -s /bin/bash dev 

# Prompt for password and read from the actual terminal, not stdin
read -p "Create password for dev user: " -s password < /dev/tty
echo ""
echo "dev:$password" | chpasswd

# Grant sudo access (crucial for toolchain installation tests) 
usermod -aG sudo dev 

# Set this user as the default login for this instance 
echo -e "[user]\ndefault=dev" > /etc/wsl.conf 
echo -e "\n[boot]\nsystemd=true" >> /etc/wsl.conf

# Configure automount for better Windows filesystem permissions
echo -e "\n[automount]\nenabled=true\noptions=metadata,uid=1000,gid=1000,umask=22" >> /etc/wsl.conf

# Exit to apply changes 
exit 
