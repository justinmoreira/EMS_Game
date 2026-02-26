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
# Use simple drvfs without metadata for better compatibility
cat >> /etc/wsl.conf << 'EOF'

[automount]
enabled=true
options="metadata,uid=1000,gid=1000,umask=000,fmask=000"

[interop]
enabled=true
appendWindowsPath=true
EOF

# Install binfmt-support for better Windows executable interop
apt-get update -qq
apt-get install -y binfmt-support

# Configure WSL interop for Windows executables
mkdir -p /usr/lib/binfmt.d
if ! grep -q "WSLInterop" /usr/lib/binfmt.d/WSLInterop.conf 2>/dev/null; then
  sh -c 'echo :WSLInterop:M::MZ::/init:PF > /usr/lib/binfmt.d/WSLInterop.conf'
fi

# Exit to apply changes
exit
