# Phase 4: ComfyUI Clone + Python Environment + PyTorch
# Clones ComfyUI at the exact commit from the PFX snapshot, creates a Python 3.13
# virtual environment, and installs torch 2.7.1+cu128 matching the snapshot.
#
# Snapshot reference: 2026-03-26_17-06-15_snapshot.json
#   comfyui commit:   040460495c5713b852e4aac29a909aa63b309da7
#   torch:            2.7.1+cu128
#   torchvision:      0.22.1+cu128
#   torchaudio:       2.7.1+cu128

$ComfyDir      = $env:COMFYUI_DIR ?? "C:\ComfyUI"
$ComfyCommit   = "040460495c5713b852e4aac29a909aa63b309da7"
$ComfyRepoURL  = "https://github.com/comfyanonymous/ComfyUI.git"
$VenvDir       = "$ComfyDir\.venv"

# Expose pip/python paths for other scripts
$script:PipExe    = "$VenvDir\Scripts\pip.exe"
$script:PythonExe = "$VenvDir\Scripts\python.exe"

function Install-ComfyUI {
    if (Test-Sentinel "comfyui-install") {
        Print-Message "blue" "SKIP: ComfyUI already installed at $ComfyDir"
        # Still expose the paths even when skipping
        $script:PipExe    = "$VenvDir\Scripts\pip.exe"
        $script:PythonExe = "$VenvDir\Scripts\python.exe"
        $env:COMFYUI_DIR  = $ComfyDir
        return
    }

    Print-Message "blue" "Installing ComfyUI at $ComfyDir..."

    _Clone-ComfyUI
    _Create-Venv
    _Install-PyTorch
    _Install-ComfyUIRequirements

    $env:COMFYUI_DIR = $ComfyDir
    Set-Sentinel "comfyui-install"
    Print-Message "green" "ComfyUI installed"
}

function _Clone-ComfyUI {
    if (Test-Path "$ComfyDir\.git") {
        Print-Message "blue" "ComfyUI repo already cloned — checking out snapshot commit..."
        Push-Location $ComfyDir
        git fetch origin 2>$null
        git checkout $ComfyCommit
        if ($LASTEXITCODE -ne 0) { Die "Failed to checkout ComfyUI commit $ComfyCommit" }
        Pop-Location
        return
    }

    New-Item -ItemType Directory -Path (Split-Path $ComfyDir) -Force | Out-Null
    Print-Message "blue" "Cloning ComfyUI..."
    git clone $ComfyRepoURL $ComfyDir
    if ($LASTEXITCODE -ne 0) { Die "Failed to clone ComfyUI" }

    Push-Location $ComfyDir
    git checkout $ComfyCommit
    if ($LASTEXITCODE -ne 0) { Die "Failed to checkout commit $ComfyCommit" }
    Pop-Location

    Print-Message "green" "ComfyUI cloned at commit $ComfyCommit"
}

function _Create-Venv {
    if (Test-Path "$VenvDir\Scripts\python.exe") {
        Print-Message "blue" "Python venv already exists at $VenvDir"
        return
    }

    Print-Message "blue" "Creating Python 3.13 virtual environment..."
    python -m venv $VenvDir
    if ($LASTEXITCODE -ne 0) { Die "Failed to create Python venv" }

    # Upgrade pip inside venv
    & "$VenvDir\Scripts\python.exe" -m pip install --upgrade pip --quiet
    Print-Message "green" "Virtual environment created: $VenvDir"
}

function _Install-PyTorch {
    # Check if torch is already installed at the correct version
    $torchVer = & $script:PythonExe -c "import torch; print(torch.__version__)" 2>$null
    if ($torchVer -match "2\.7\.1\+cu128") {
        Print-Message "blue" "torch 2.7.1+cu128 already installed"
        return
    }

    Print-Message "blue" "Installing torch 2.7.1+cu128 (matching PFX snapshot)..."
    & $script:PipExe install --quiet `
        "torch==2.7.1+cu128" `
        "torchvision==0.22.1+cu128" `
        "torchaudio==2.7.1+cu128" `
        --index-url https://download.pytorch.org/whl/cu128

    if ($LASTEXITCODE -ne 0) { Die "Failed to install PyTorch cu128" }

    # Install triton-windows (Windows-specific, from snapshot)
    Print-Message "blue" "Installing triton-windows 3.3.1..."
    & $script:PipExe install --quiet "triton-windows==3.3.1.post21" 2>$null | Out-Null

    # Install sageattention (Windows-specific wheel from snapshot)
    Print-Message "blue" "Installing sageattention (cu128/torch2.7 Windows wheel)..."
    & $script:PipExe install --quiet `
        "sageattention" `
        --extra-index-url https://download.pytorch.org/whl/cu128 2>$null | Out-Null

    # Verify
    $torchVer = & $script:PythonExe -c "import torch; print(torch.__version__)" 2>$null
    $cudaAvail = & $script:PythonExe -c "import torch; print(torch.cuda.is_available())" 2>$null
    Print-Message "green" "torch $torchVer installed — CUDA available: $cudaAvail"
}

function _Install-ComfyUIRequirements {
    Print-Message "blue" "Installing ComfyUI requirements.txt..."
    & $script:PipExe install --quiet -r "$ComfyDir\requirements.txt"
    if ($LASTEXITCODE -ne 0) { Die "Failed to install ComfyUI requirements" }
    Print-Message "green" "ComfyUI requirements installed"
}

# Expose venv paths as module-level variables for other scripts to use
$env:COMFYUI_DIR    = $ComfyDir
$env:COMFYUI_PYTHON = "$VenvDir\Scripts\python.exe"
$env:COMFYUI_PIP    = "$VenvDir\Scripts\pip.exe"
