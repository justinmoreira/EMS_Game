# 1. Set Variables
$newDistroName = "ems-wsl"
$installDir = "C:\WSL\ems-wsl" 
$tarballUrl = "https://cloud-images.ubuntu.com/wsl/releases/noble/current/ubuntu-noble-wsl-amd64-24.04lts.rootfs.tar.gz"
$tarballPath = "$env:TEMP\ubuntu-2404-rootfs.tar.gz"
# TODO: Update when merged to main
$postInstallUrl = "https://raw.githubusercontent.com/justinmoreira/EMS_Game/dev_setup/scripts/wsl/post_install.sh"
$projectInstallUrl = "https://raw.githubusercontent.com/justinmoreira/EMS_Game/dev_setup/scripts/install.sh"
$godotVersion = "4.6-stable"
$godotDownloadUrl = "https://github.com/godotengine/godot/releases/download/${godotVersion}/Godot_v${godotVersion}_win64.exe.zip"

# 1.5. Search for existing Godot installation
Write-Host "`n==> Checking for Godot..."
$godotExePath = $null

# First check PATH using Get-Command
$godotCmd = Get-Command "Godot*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($godotCmd) {
    $godotExePath = $godotCmd.Source
    Write-Host "Found Godot in PATH: $godotExePath"
} else {
    # Fall back to searching common directories
    $searchPaths = @(
        "$env:ProgramFiles\Godot",
        "${env:ProgramFiles(x86)}\Godot",
        "$env:LOCALAPPDATA\Godot",
        "$env:APPDATA\Godot"
    )

    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            $found = Get-ChildItem -Path $path -Filter "Godot*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $godotExePath = $found.FullName
                Write-Host "Found Godot at: $godotExePath"
                break
            }
        }
    }
}

# If not found, ask user for manual path or install
if (-not $godotExePath) {
    Write-Host "Godot not found in standard locations."
    $userChoice = Read-Host "Do you have Godot installed elsewhere? [y/N] (default: no, install)"
    
    if ($userChoice -eq "Y" -or $userChoice -eq "y") {
        $customPath = Read-Host "Enter the full path to your Godot installation directory"
        if (Test-Path $customPath) {
            $found = Get-ChildItem -Path $customPath -Filter "Godot*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $godotExePath = $found.FullName
                Write-Host "Found Godot at: $godotExePath"
            } else {
                Write-Host "No Godot executable found in $customPath. Will install instead."
            }
        } else {
            Write-Host "Path not found: $customPath. Will install instead."
        }
    }
}

# If still not found, install Godot
if (-not $godotExePath) {
    Write-Host "Installing Godot..."
    $defaultGodotDir = "$env:LOCALAPPDATA\Godot"
    $baseDir = Read-Host "Install Godot to (press Enter for default: $defaultGodotDir)"
    if ([string]::IsNullOrWhiteSpace($baseDir)) {
        $godotInstallDir = $defaultGodotDir
    } else {
        # Append \Godot if not already there
        if ($baseDir -notlike "*\Godot") {
            $godotInstallDir = Join-Path $baseDir "Godot"
        } else {
            $godotInstallDir = $baseDir
        }
    }
    
    Write-Host "Downloading Godot ${godotVersion} for Windows to $godotInstallDir..."
    $godotZipPath = "$env:TEMP\godot.zip"
    Invoke-WebRequest -Uri $godotDownloadUrl -OutFile $godotZipPath -UseBasicParsing
    
    Write-Host "Installing to $godotInstallDir..."
    New-Item -ItemType Directory -Force -Path $godotInstallDir | Out-Null
    Expand-Archive -Path $godotZipPath -DestinationPath $godotInstallDir -Force
    Remove-Item $godotZipPath
    
    $godotExePath = "$godotInstallDir\Godot_v${godotVersion}_win64.exe"
    
    # Add Godot directory to PATH
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$godotInstallDir*") {
        Write-Host "Adding $godotInstallDir to PATH..."
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$godotInstallDir", "User")
        $env:Path += ";$godotInstallDir"
    }
    
    # Create Start Menu shortcut
    $startMenuPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    $shortcutPath = "$startMenuPath\Godot ${godotVersion}.lnk"
    $WScriptShell = New-Object -ComObject WScript.Shell
    $shortcut = $WScriptShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $godotExePath
    $shortcut.WorkingDirectory = $godotInstallDir
    $shortcut.Save()
    
    Write-Host "Godot installed successfully!"
    Write-Host "Start Menu shortcut created"
}

# Convert Windows path to WSL path format
$wslGodotPath = wsl wslpath -u "'$godotExePath'"

Write-Host "WSL Path: $wslGodotPath"

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
wsl -d $newDistroName bash -c "curl -sSL $postInstallUrl | sudo bash"

# 6. Restart to apply changes
Write-Host "`nRestarting WSL instance to apply changes..."
wsl --terminate $newDistroName
Start-Sleep -Seconds 2

# 7. Install Project
Write-Host "`nInstalling EMS Game project..."
wsl -d $newDistroName bash -c "curl -sSL $projectInstallUrl | bash"

# 8. Configure GODOT_WIN path in project
Write-Host "`nConfiguring Godot path for WSL..."
$winUsername = $env:USERNAME
wsl -d $newDistroName bash -c @"
PROJECT_DIR=`"`/mnt/c/Users/$winUsername/EMS_Game`"
if [ -f `"`$PROJECT_DIR/.env`" ]; then
    if ! grep -q 'GODOT_WIN' `"`$PROJECT_DIR/.env`"; then
        echo 'GODOT_WIN=`"$wslGodotPath`"' >> `"`$PROJECT_DIR/.env`"
    fi
else
    echo 'GODOT_WIN=`"$wslGodotPath`"' > `"`$PROJECT_DIR/.env`"
fi
"@

Write-Host "`n===================================="
Write-Host "Installation Complete!"
Write-Host "===================================="
Write-Host "Godot installed at: $godotExePath"
Write-Host "WSL path configured: $wslGodotPath"
Write-Host "Project location: C:\Users\$winUsername\EMS_Game"
Write-Host "`nTo get started:"
Write-Host "  wsl -d $newDistroName"
Write-Host "  cd /mnt/c/Users/$winUsername/EMS_Game"
