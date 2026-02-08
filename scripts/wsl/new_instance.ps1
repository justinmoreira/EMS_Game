# 1. Set Variables
$newDistroName = "Ubuntu-Clean"

$installDir = "C:\WSL\Ubuntu-Clean"

$tarballUrl = "https://cloud-images.ubuntu.com/wsl/noble/current/ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz"

$tarballPath = "$env:TEMP\ubuntu-2404-rootfs.tar.gz"

# 2. Download the RootFS (approx 70-100MB)
Write-Host "Downloading Ubuntu 24.04 RootFS..."
Invoke-WebRequest -Uri $tarballUrl -OutFile $tarballPath -UseBasicParsing

# 3. Create Directory and Import
Write-Host "Importing into $installDir..."

New-Item -ItemType Directory -Force -Path $installDir | Out-Null

wsl --import $newDistroName $installDir $tarballPath

# 4. Clean up
Remove-Item $tarballPath

# 5. Launch
Write-Host "Done! Launching..."

wsl -d $newDistroName
