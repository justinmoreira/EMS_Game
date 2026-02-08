#!/usr/bin/env bash

# Create your user (replace 'dev' with your preference) 
useradd -m -s /bin/bash dev 

# Prompt for password and read from the actual terminal, not stdin
read -p "Enter password for dev user: " -s password < /dev/tty
echo ""
echo "dev:$password" | chpasswd

# Grant sudo access (crucial for toolchain installation tests) 
usermod -aG sudo dev 

# Set this user as the default login for this instance 
echo -e "[user]\ndefault=dev" > /etc/wsl.conf 
echo -e "\n[boot]\nsystemd=true" | sudo tee -a /etc/wsl.conf >/dev/null

echo ""
echo "Back in powershell, reload the instance to apply changes"
echo "wsl --terminate ems-wsl"
echo "wsl -d ems-wsl"

# Exit to apply changes 
exit 
