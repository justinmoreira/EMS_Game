#!/usr/bin/env bash

# Create your user (replace 'testuser' with your preference) 
useradd -m -s /bin/bash testuser 
passwd testuser 

# Grant sudo access (crucial for toolchain installation tests) 
usermod -aG sudo testuser 

# Set this user as the default login for this instance 
echo -e "[user]\ndefault=testuser" > /etc/wsl.conf 

# Exit to apply changes 
exit 


# Back in powershell, reload the instance to apply changes
# wsl --terminate Ubuntu-Clean
# wsl -d Ubuntu-Clean