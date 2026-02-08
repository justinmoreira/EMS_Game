#!/usr/bin/env bash

# Create your user (replace 'dev' with your preference) 
useradd -m -s /bin/bash dev 
passwd dev 

# Grant sudo access (crucial for toolchain installation tests) 
usermod -aG sudo dev 

# Set this user as the default login for this instance 
echo -e "[user]\ndefault=dev" > /etc/wsl.conf 

echo "Back in powershell, reload the instance to apply changes"
echo "wsl --terminate ems-wsl"
echo "wsl -d ems-wsl"

# Exit to apply changes 
exit 
