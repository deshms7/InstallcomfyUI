# ComfyUI on Windows - Main Installation Script
# Native Windows ComfyUI install (no Docker) matching PFX snapshot environment.
#
# Usage (run in elevated PowerShell):
#   .\install.ps1
#   $env:COMFYUI_DIR="D:\ComfyUI"; .\install.ps1
#   $env:COMFYUI_PORT="8188"; .\install.ps1
#   $env:REEMO_AGENT_TOKEN="studio_fa413ff7044b"; .\install.ps1

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

. "$ScriptDir\scripts\common.ps1"
. "$ScriptDir\scripts\system-setup.ps1"
. "$ScriptDir\scripts\nvidia-setup.ps1"
. "$ScriptDir\scripts\comfyui-install.ps1"
. "$ScriptDir\scripts\install-custom-nodes.ps1"
. "$ScriptDir\scripts\install-models.ps1"
. "$ScriptDir\scripts\comfyui-service.ps1"
. "$ScriptDir\scripts\validate.ps1"
. "$ScriptDir\scripts\workflow-test.ps1"
. "$ScriptDir\scripts\remote-access.ps1"
. "$ScriptDir\scripts\add-packages.ps1"

function Main {
    Write-Host "====== ComfyUI Windows Setup (Native) ======"

    $currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "This script must be run as Administrator."
        exit 1
    }

    $osVersion = [System.Environment]::OSVersion.Version
    $caption   = (Get-WmiObject Win32_OperatingSystem).Caption
    if ($osVersion.Major -lt 10) {
        Write-Warning "Designed for Windows 10/11 (detected: $caption)"
        $r = Read-Host "Continue anyway? [y/N]"
        if ($r -notmatch '^[Yy]$') { exit 1 }
    }

    Write-Host ""
    Write-Host "=== Pre-flight Checks ==="
    Test-SystemRequirements -MinCores 4 -MinRamGB 32

    $gpuInfo = Get-WmiObject Win32_VideoController | Where-Object { $_.Name -match "NVIDIA" }
    if (-not $gpuInfo) { Die "No NVIDIA GPU detected" }
    Print-Message "green" "GPU: $($gpuInfo[0].Name)"

    Write-Host ""
    Write-Host "=== Installation Plan ==="
    Write-Host "  ComfyUI dir:  $($env:COMFYUI_DIR ?? 'C:\ComfyUI')"
    Write-Host "  Port:         $($env:COMFYUI_PORT ?? '8188')"
    Write-Host "  Python:       3.13"
    Write-Host "  PyTorch:      2.7.1+cu128"
    Write-Host ""
    Write-Host "  1. Pre-flight checks (OS, CPU, RAM, GPU)"
    Write-Host "  2. System baseline (Python 3.13, Git, Visual C++, Chocolatey)"
    Write-Host "  3. NVIDIA driver validation"
    Write-Host "  4. ComfyUI clone + Python environment + PyTorch cu128"
    Write-Host "  5. Custom nodes (26 git + 26 CNR + 1 file from snapshot)"
    Write-Host "  6. Model directory structure"
    Write-Host "  7. ComfyUI Windows service (NSSM)"
    Write-Host "  8. Validation (process, port, GPU)"
    Write-Host "  9. Workflow test (txt2img smoke test)"
    Write-Host " 10. Remote access (Reemo agent, firewall)"
    Write-Host " 11. Final packages (desktop guide)"
    Write-Host ""
    $r = Read-Host "Continue? [y/N]"
    if ($r -notmatch '^[Yy]$') { exit 1 }

    Setup-Logging

    Print-Message "blue" "=== Phase 2: System Baseline ==="
    Invoke-SystemSetup

    Print-Message "blue" "=== Phase 3: NVIDIA Driver Validation ==="
    Test-NvidiaDriver

    Print-Message "blue" "=== Phase 4: ComfyUI Install + PyTorch ==="
    Install-ComfyUI

    Print-Message "blue" "=== Phase 5: Custom Nodes ==="
    Install-CustomNodes

    Print-Message "blue" "=== Phase 6: Model Directory Structure ==="
    Initialize-ModelDirectories

    Print-Message "blue" "=== Phase 7: ComfyUI Windows Service ==="
    Setup-ComfyUIService

    Print-Message "blue" "=== Phase 8: Validation ==="
    Test-ComfyUI

    Print-Message "blue" "=== Phase 9: Workflow Test ==="
    Invoke-WorkflowTest

    Print-Message "blue" "=== Phase 10: Remote Access ==="
    Install-RemoteAccess

    Print-Message "blue" "=== Phase 11: Final Packages ==="
    Add-Packages

    Print-Message "green" "Installation complete!"
}

Main
