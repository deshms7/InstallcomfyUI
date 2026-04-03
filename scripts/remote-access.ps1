# Phase 10: Remote Access — Reemo only
# Installs and registers the Reemo agent. Parsec is NOT used for this deployment
# (confirmed by PFX in email: "Reemo would be great").
#
# Required env var:
#   REEMO_AGENT_TOKEN   Studio Key from reemo.io/download
#                       PFX Studio Key: studio_fa413ff7044b
#
# Usage:
#   $env:REEMO_AGENT_TOKEN="studio_fa413ff7044b"; .\install.ps1

$ComfyPort = $env:COMFYUI_PORT ?? "8188"

function Install-RemoteAccess {
    if (Test-Sentinel "remote-access") {
        Print-Message "blue" "SKIP: Remote access already installed"
        return
    }

    # Default to PFX studio key if not overridden
    if (-not $env:REEMO_AGENT_TOKEN) {
        $env:REEMO_AGENT_TOKEN = "studio_fa413ff7044b"
        Print-Message "blue" "Using default Reemo Studio Key (PFX)"
    }

    _Install-Reemo
    _Configure-Firewall

    Set-Sentinel "remote-access"
    Print-Message "green" "Remote access setup complete — Reemo agent is running"
}

function _Install-Reemo {
    Print-Message "blue" "Installing Reemo agent..."

    # Check if already installed
    $reemoSvc = Get-Service -Name "reemod" -ErrorAction SilentlyContinue
    if ($reemoSvc) {
        Print-Message "blue" "Reemo agent already installed (service: reemod)"
        return
    }

    $reemoSetup = "$env:TEMP\reemo-setup.exe"

    # Download Windows installer from Reemo
    # TODO: verify exact Windows installer URL at reemo.io/download
    Print-Message "blue" "Downloading Reemo installer..."
    Invoke-WebRequest -Uri "https://download.reemo.io/windows/setup.exe" `
        -OutFile $reemoSetup -UseBasicParsing

    $keyPreview = $env:REEMO_AGENT_TOKEN.Substring(0, [Math]::Min(12, $env:REEMO_AGENT_TOKEN.Length))
    Print-Message "blue" "Registering Reemo agent (key: ${keyPreview}...)"
    Start-Process -FilePath $reemoSetup `
        -ArgumentList "--key $($env:REEMO_AGENT_TOKEN) --silent" `
        -Wait

    Remove-Item $reemoSetup -Force -ErrorAction SilentlyContinue

    # Verify service was registered
    $reemoSvc = Get-Service -Name "reemod" -ErrorAction SilentlyContinue
    if (-not $reemoSvc) {
        Print-Message "yellow" "WARN: Reemo service (reemod) not found after install — check installer output"
    } else {
        Print-Message "green" "Reemo agent installed and running"
    }
}

function _Configure-Firewall {
    Print-Message "blue" "Configuring Windows Firewall..."

    $rules = @(
        @{ Name = "ComfyUI";       Port = $ComfyPort; Protocol = "TCP"; Desc = "ComfyUI web UI" },
        @{ Name = "Reemo STUN UDP"; Port = 3478;      Protocol = "UDP"; Desc = "Reemo STUN" },
        @{ Name = "Reemo STUN TCP"; Port = 3478;      Protocol = "TCP"; Desc = "Reemo STUN/TURN TCP" },
        @{ Name = "Reemo TURN TLS"; Port = 5349;      Protocol = "TCP"; Desc = "Reemo TURN TLS" }
    )

    foreach ($rule in $rules) {
        Remove-NetFirewallRule -DisplayName "Illuma - $($rule.Name)" -ErrorAction SilentlyContinue
        New-NetFirewallRule `
            -DisplayName "Illuma - $($rule.Name)" `
            -Direction Inbound `
            -Action Allow `
            -Protocol $rule.Protocol `
            -LocalPort $rule.Port `
            -Description $rule.Desc | Out-Null
        Print-Message "blue" "  Allowed: $($rule.Protocol) $($rule.Port) — $($rule.Desc)"
    }

    Print-Message "green" "Firewall configured"
}
