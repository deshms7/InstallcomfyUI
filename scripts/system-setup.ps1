# Phase 2: System Baseline
# Installs Chocolatey, Python 3.13, Git, and Visual C++ Redistributable.
# No WSL2/Hyper-V needed — ComfyUI runs natively on Windows.

function Invoke-SystemSetup {
    if (Test-Sentinel "system-baseline") {
        Print-Message "blue" "SKIP: System baseline already configured"
        return
    }

    Print-Message "blue" "Configuring system baseline..."

    _Install-Chocolatey
    _Install-BasePackages
    _Install-Python313
    _Install-Git

    Set-Sentinel "system-baseline"
    Print-Message "green" "System baseline complete"
}

function _Install-Chocolatey {
    if (Test-CommandExists "choco") {
        Print-Message "blue" "Chocolatey already installed: $(choco --version)"
        return
    }

    Print-Message "blue" "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    _Refresh-Path
    Print-Message "green" "Chocolatey installed: $(choco --version)"
}

function _Install-BasePackages {
    Print-Message "blue" "Installing base tools (curl, jq, wget, 7zip)..."
    foreach ($pkg in @("curl", "jq", "wget", "7zip")) {
        choco install $pkg -y --no-progress 2>$null | Out-Null
    }
    _Refresh-Path
    Print-Message "green" "Base tools installed"
}

function _Install-Python313 {
    # Check if python 3.13 is already present
    $pyVer = python --version 2>$null
    if ($pyVer -match "3\.13") {
        Print-Message "blue" "Python 3.13 already installed: $pyVer"
        return
    }

    Print-Message "blue" "Installing Python 3.13..."
    # --params adds Python to PATH and associates .py files
    choco install python313 -y --no-progress `
        --params "'/AddToPath:1 /InstallAllUsers:1'" 2>$null | Out-Null
    _Refresh-Path

    $pyVer = python --version 2>$null
    if ($pyVer -notmatch "3\.13") {
        Die "Python 3.13 install failed or not on PATH. Found: $pyVer"
    }
    Print-Message "green" "Python installed: $pyVer"
}

function _Install-Git {
    if (Test-CommandExists "git") {
        Print-Message "blue" "Git already installed: $(git --version)"
        return
    }

    Print-Message "blue" "Installing Git..."
    choco install git -y --no-progress | Out-Null
    _Refresh-Path
    Print-Message "green" "Git installed: $(git --version)"
}

function _Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}
