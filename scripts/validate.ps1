# Phase 8: Validation
# Polls until ComfyUI process is running and the web UI responds on the configured port.

$PollMaxAttempts = [int]($env:POLL_MAX_ATTEMPTS ?? 30)
$PollSleepSec    = [int]($env:POLL_SLEEP_SEC    ?? 10)
$ComfyPort       = $env:COMFYUI_PORT ?? "8188"
$ServiceName     = "comfyui"

function Test-ComfyUI {
    Print-Message "blue" "Validating ComfyUI..."

    _Wait-ServiceRunning
    _Wait-PortReady

    $hostIP = (Get-NetIPAddress -AddressFamily IPv4 |
               Where-Object { $_.InterfaceAlias -notmatch "Loopback" } |
               Select-Object -First 1).IPAddress

    Print-Message "green" "Validation passed!"
    Write-Host ""
    Print-Message "blue" "=== ComfyUI is ready ==="
    Print-Message "blue" "  URL:  http://localhost:${ComfyPort}  (or http://${hostIP}:${ComfyPort})"
    Write-Host ""
    Print-Message "blue" "Useful commands:"
    Print-Message "blue" "  Service status:  Get-Service $ServiceName"
    Print-Message "blue" "  Service logs:    Get-Content C:\ComfyUI\logs\comfyui.log -Tail 50"
    Print-Message "blue" "  Restart:         Restart-Service $ServiceName"
    Print-Message "blue" "  GPU check:       nvidia-smi"
}

function _Wait-ServiceRunning {
    Print-Message "blue" "Waiting for $ServiceName service to start..."

    for ($i = 1; $i -le $PollMaxAttempts; $i++) {
        $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq "Running") {
            Print-Message "green" "Service is running"
            return
        }
        Print-Message "blue" "  Attempt $i/$PollMaxAttempts — service not yet running, waiting ${PollSleepSec}s..."
        Start-Sleep -Seconds $PollSleepSec
    }

    Die "Service $ServiceName did not start. Check logs: Get-Content C:\ComfyUI\logs\comfyui-error.log -Tail 50"
}

function _Wait-PortReady {
    Print-Message "blue" "Waiting for ComfyUI on port $ComfyPort..."

    for ($i = 1; $i -le $PollMaxAttempts; $i++) {
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:$ComfyPort" -UseBasicParsing -TimeoutSec 5 2>$null
            if ($r.StatusCode -lt 500) {
                Print-Message "green" "ComfyUI responding on port $ComfyPort"
                return
            }
        } catch {}
        Print-Message "blue" "  Attempt $i/$PollMaxAttempts — port not ready, waiting ${PollSleepSec}s..."
        Start-Sleep -Seconds $PollSleepSec
    }

    Die "ComfyUI did not respond on port $ComfyPort after $($PollMaxAttempts * $PollSleepSec)s"
}
