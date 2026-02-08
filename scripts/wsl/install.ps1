# 1. Set Variables
$newDistroName = "ems-wsl"
$installDir = "C:\WSL\ems-wsl" 
$tarballUrl = "https://cloud-images.ubuntu.com/wsl/releases/noble/current/ubuntu-noble-wsl-amd64-24.04lts.rootfs.tar.gz"
$tarballPath = "$env:TEMP\ubuntu-2404-rootfs.tar.gz"
# TODO: Update when merged to main
$postInstallUrl = "https://raw.githubusercontent.com/justinmoreira/EMS_Game/dev_setup/scripts/wsl/post_install.sh"
$projectInstallUrl = "https://raw.githubusercontent.com/justinmoreira/EMS_Game/dev_setup/scripts/install.sh"

# 2. Download the RootFS (approx 70-100MB)
Write-Host "Downloading Ubuntu 24.04 RootFS..."
Invoke-WebRequest -Uri $tarballUrl -OutFile $tarballPath -UseBasicParsing

# 3. Create Directory and Import
Write-Host "Importing into $installDir..."
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
wsl --import $newDistroName $installDir $tarballPath

# 4. Clean up
Remove-Item $tarballPath

# 5. Run post-install configuration
Write-Host "`nRunning post-install setup..."
wsl -d $newDistroName bash -c "curl -sSL $postInstallUrl | bash"

# 6. Restart to apply changes
Write-Host "`nRestarting WSL instance to apply changes..."
wsl --terminate $newDistroName
Start-Sleep -Seconds 2

# 7. Install Project
Write-Host "Done! Launching $newDistroName..."
wsl -d $newDistroName bash -c "curl -sSL $projectInstallUrl | bash"
