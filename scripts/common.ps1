# Common Functions - Shared utilities for ComfyUI Windows setup

# Default sentinel directory (mirrors /var/lib/illuma on Linux)
$SentinelDir = $env:SENTINEL_DIR ?? "C:\ProgramData\illuma"

function Print-Message {
    param(
        [string]$Color,
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    switch ($Color) {
        "red"    { Write-Host "[$timestamp] [ERROR]   $Message" -ForegroundColor Red }
        "green"  { Write-Host "[$timestamp] [SUCCESS] $Message" -ForegroundColor Green }
        "yellow" { Write-Host "[$timestamp] [WARN]    $Message" -ForegroundColor Yellow }
        "blue"   { Write-Host "[$timestamp] [INFO]    $Message" -ForegroundColor Cyan }
        default  { Write-Host "[$timestamp] $Message" }
    }
}

function Setup-Logging {
    $logDir = "C:\ProgramData\illuma\logs"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $script:LogFile = "$logDir\comfyui-setup-$timestamp.log"

    Print-Message "blue" "Log file: $script:LogFile"

    # Start transcript — captures all output to file while keeping console output
    Start-Transcript -Path $script:LogFile -Append | Out-Null
}

function Test-DiskSpace {
    param([int]$RequiredGB = 30)

    $drive = (Get-Location).Drive.Name + ":"
    $disk = Get-PSDrive -Name (Get-Location).Drive.Name
    $availableGB = [math]::Floor($disk.Free / 1GB)

    if ($availableGB -lt $RequiredGB) {
        Print-Message "red" "Insufficient disk space — Required: ${RequiredGB}GB, Available: ${availableGB}GB"
        return $false
    }

    Print-Message "green" "Disk space: ${availableGB}GB available"
    return $true
}

function Test-SystemRequirements {
    param(
        [int]$MinCores = 4,
        [int]$MinRamGB = 8
    )

    Print-Message "blue" "Checking system requirements..."

    # CPU cores
    $cpuCores = (Get-WmiObject Win32_ComputerSystem).NumberOfLogicalProcessors
    if ($cpuCores -lt $MinCores) {
        Print-Message "yellow" "Warning: $cpuCores CPU cores found ($MinCores+ recommended)"
    } else {
        Print-Message "green" "CPU cores: $cpuCores"
    }

    # RAM
    $totalRamGB = [math]::Floor((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    if ($totalRamGB -lt $MinRamGB) {
        Die "Insufficient RAM — ${totalRamGB}GB found, ${MinRamGB}GB required"
    }
    Print-Message "green" "RAM: ${totalRamGB}GB"

    Test-DiskSpace | Out-Null
}

function Get-SentinelPath {
    param([string]$Name)
    return "$SentinelDir\.$Name-done"
}

function Test-Sentinel {
    param([string]$Name)
    return Test-Path (Get-SentinelPath $Name)
}

function Set-Sentinel {
    param([string]$Name)
    New-Item -ItemType Directory -Path $SentinelDir -Force | Out-Null
    New-Item -ItemType File -Path (Get-SentinelPath $Name) -Force | Out-Null
}

function Die {
    param([string]$Message)
    Print-Message "red" $Message
    exit 1
}

function Test-CommandExists {
    param([string]$Command)
    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}
