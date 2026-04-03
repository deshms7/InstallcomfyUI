# Phase 11: Final Packages
# Places the IllumaComfyUI.html desktop guide.
# No additional software requested by PFX ("No other software for now").

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent

function Add-Packages {
    Print-Message "blue" "Placing desktop guide..."

    $guideSrc  = "$ScriptDir\IllumaComfyUI.html"
    $desktopPath = [Environment]::GetFolderPath("CommonDesktopDirectory")
    $guideDst  = "$desktopPath\IllumaComfyUI.html"

    if (Test-Path $guideSrc) {
        Copy-Item $guideSrc $guideDst -Force
        Print-Message "green" "Desktop guide placed: $guideDst"
    } else {
        Print-Message "yellow" "IllumaComfyUI.html not found at $guideSrc — skipping"
    }
}
