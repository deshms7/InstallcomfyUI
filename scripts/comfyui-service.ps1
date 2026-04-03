# Phase 7: ComfyUI Windows Service
# Registers ComfyUI as a Windows service via NSSM so it starts at boot and restarts on failure.
# Runs: python main.py --listen 0.0.0.0 --port <COMFYUI_PORT>
# This mirrors the systemd unit on Linux.

$ComfyDir    = $env:COMFYUI_DIR    ?? "C:\ComfyUI"
$ComfyPort   = $env:COMFYUI_PORT   ?? "8188"
$ServiceName = "comfyui"

function Setup-ComfyUIService {
    $python = $env:COMFYUI_PYTHON ?? "$ComfyDir\.venv\Scripts\python.exe"

    Print-Message "blue" "Setting up ComfyUI Windows service..."

    _Install-NSSM
    _Register-Service -Python $python
    _Start-Service

    Print-Message "green" "ComfyUI service running"
}

function _Install-NSSM {
    if (Test-CommandExists "nssm") {
        Print-Message "blue" "NSSM already installed"
        return
    }
    Print-Message "blue" "Installing NSSM..."
    choco install nssm -y --no-progress | Out-Null
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
    Print-Message "green" "NSSM installed"
}

function _Register-Service {
    param([string]$Python)

    # Remove existing service if present
    $existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existing) {
        Print-Message "blue" "Removing existing $ServiceName service..."
        nssm stop $ServiceName 2>$null
        nssm remove $ServiceName confirm 2>$null
    }

    Print-Message "blue" "Registering service: $ServiceName"

    # Arguments passed to python main.py
    $mainPy   = "$ComfyDir\main.py"
    $args     = "$mainPy --listen 0.0.0.0 --port $ComfyPort"
    $logDir   = "$ComfyDir\logs"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null

    nssm install $ServiceName $Python $args
    nssm set $ServiceName DisplayName   "ComfyUI"
    nssm set $ServiceName Description   "ComfyUI AI image generation — managed by Illuma"
    nssm set $ServiceName AppDirectory  $ComfyDir
    nssm set $ServiceName Start         SERVICE_AUTO_START

    # Restart on failure — mirrors systemd Restart=always RestartSec=10
    nssm set $ServiceName AppExit        Default    Restart
    nssm set $ServiceName AppRestartDelay 10000

    # Log stdout/stderr to files
    nssm set $ServiceName AppStdout     "$logDir\comfyui.log"
    nssm set $ServiceName AppStderr     "$logDir\comfyui-error.log"
    nssm set $ServiceName AppRotateFiles 1
    nssm set $ServiceName AppRotateBytes 10485760

    Print-Message "green" "Service registered"
}

function _Start-Service {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Print-Message "blue" "Restarting $ServiceName..."
        Restart-Service $ServiceName
    } else {
        Start-Service $ServiceName
    }
    Print-Message "green" "Service started"
}
