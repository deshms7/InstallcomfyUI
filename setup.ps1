# ComfyUI Windows Setup — Single-file installer
# Matches PFX snapshot: ComfyUI 040460495, torch 2.7.1+cu128, Python 3.13
#
# Usage (elevated PowerShell):
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\setup.ps1
#
# Optional overrides:
#   $env:COMFYUI_DIR="D:\ComfyUI"; .\setup.ps1
#   $env:REEMO_AGENT_TOKEN="studio_fa413ff7044b"; .\setup.ps1

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# CONFIGURATION
# ============================================================
$COMFYUI_DIR     = $env:COMFYUI_DIR     ?? "C:\ComfyUI"
$COMFYUI_PORT    = $env:COMFYUI_PORT    ?? "8188"
$COMFYUI_COMMIT  = "040460495c5713b852e4aac29a909aa63b309da7"
$COMFYUI_REPO    = "https://github.com/comfyanonymous/ComfyUI.git"
$VENV_DIR        = "$COMFYUI_DIR\.venv"
$SENTINEL_DIR    = "C:\ProgramData\illuma"
$SERVICE_NAME    = "comfyui"
$REEMO_TOKEN     = $env:REEMO_AGENT_TOKEN ?? "studio_fa413ff7044b"

# ============================================================
# COMMON UTILITIES
# ============================================================
function Print-Message([string]$Color, [string]$Message) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    switch ($Color) {
        "red"    { Write-Host "[$ts] [ERROR]   $Message" -ForegroundColor Red }
        "green"  { Write-Host "[$ts] [SUCCESS] $Message" -ForegroundColor Green }
        "yellow" { Write-Host "[$ts] [WARN]    $Message" -ForegroundColor Yellow }
        "blue"   { Write-Host "[$ts] [INFO]    $Message" -ForegroundColor Cyan }
        default  { Write-Host "[$ts] $Message" }
    }
}

function Setup-Logging {
    $logDir = "C:\ProgramData\illuma\logs"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $logFile = "$logDir\comfyui-setup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    Start-Transcript -Path $logFile -Append | Out-Null
    Print-Message "blue" "Log: $logFile"
}

function Die([string]$Message) {
    Print-Message "red" $Message
    exit 1
}

function Test-Sentinel([string]$Name) {
    return Test-Path "$SENTINEL_DIR\.$Name-done"
}

function Set-Sentinel([string]$Name) {
    New-Item -ItemType Directory -Path $SENTINEL_DIR -Force | Out-Null
    New-Item -ItemType File -Path "$SENTINEL_DIR\.$Name-done" -Force | Out-Null
}

function Test-CommandExists([string]$Cmd) {
    return [bool](Get-Command $Cmd -ErrorAction SilentlyContinue)
}

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
}

# ============================================================
# PHASE 1 — PRE-FLIGHT
# ============================================================
function Invoke-PreFlight {
    Print-Message "blue" "=== Phase 1: Pre-flight Checks ==="

    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Die "Must run as Administrator. Right-click PowerShell → Run as administrator."
    }

    $cores = (Get-WmiObject Win32_ComputerSystem).NumberOfLogicalProcessors
    $ramGB = [math]::Floor((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $disk  = Get-PSDrive -Name C
    $diskGB = [math]::Floor($disk.Free / 1GB)

    Print-Message "blue" "CPU cores: $cores | RAM: ${ramGB}GB | Free disk: ${diskGB}GB"
    if ($ramGB -lt 16) { Print-Message "yellow" "Low RAM: ${ramGB}GB (32GB+ recommended)" }
    if ($diskGB -lt 100) { Die "Not enough disk space: ${diskGB}GB free (100GB+ required)" }

    $gpu = Get-WmiObject Win32_VideoController | Where-Object { $_.Name -match "NVIDIA" } | Select-Object -First 1
    if (-not $gpu) { Die "No NVIDIA GPU detected" }
    Print-Message "green" "GPU: $($gpu.Name)"

    Print-Message "green" "Pre-flight passed"
}

# ============================================================
# PHASE 2 — SYSTEM BASELINE
# ============================================================
function Invoke-SystemSetup {
    Print-Message "blue" "=== Phase 2: System Baseline ==="

    if (Test-Sentinel "system-baseline") {
        Print-Message "blue" "SKIP: System baseline already done"
        return
    }

    # Chocolatey
    if (-not (Test-CommandExists "choco")) {
        Print-Message "blue" "Installing Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Refresh-Path
        Print-Message "green" "Chocolatey installed"
    } else {
        Print-Message "blue" "Chocolatey already present"
    }

    # Base tools
    foreach ($pkg in @("git", "7zip", "wget", "curl")) {
        if (-not (Test-CommandExists $pkg)) {
            choco install $pkg -y --no-progress 2>$null | Out-Null
        }
    }
    Refresh-Path

    # Python 3.13
    $pyVer = python --version 2>$null
    if ($pyVer -notmatch "3\.13") {
        Print-Message "blue" "Installing Python 3.13..."
        choco install python313 -y --no-progress --params "'/AddToPath:1 /InstallAllUsers:1'" 2>$null | Out-Null
        Refresh-Path
        $pyVer = python --version 2>$null
        if ($pyVer -notmatch "3\.13") { Die "Python 3.13 install failed. Found: $pyVer" }
    }
    Print-Message "green" "Python: $pyVer"

    # NSSM (service manager)
    if (-not (Test-CommandExists "nssm")) {
        choco install nssm -y --no-progress | Out-Null
        Refresh-Path
    }
    Print-Message "green" "NSSM ready"

    Set-Sentinel "system-baseline"
    Print-Message "green" "System baseline complete"
}

# ============================================================
# PHASE 3 — NVIDIA VALIDATION
# ============================================================
function Invoke-NvidiaCheck {
    Print-Message "blue" "=== Phase 3: NVIDIA Validation ==="

    if (-not (Test-CommandExists "nvidia-smi")) {
        Die "nvidia-smi not found. Install NVIDIA drivers first."
    }

    $info = nvidia-smi --query-gpu=name,driver_version,compute_cap --format=csv,noheader 2>$null
    if (-not $info) { Die "nvidia-smi failed — check driver." }
    Print-Message "green" "Driver OK: $info"

    $cap = (nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>$null | Select-Object -First 1).Trim().Replace(".","")
    if ($cap -eq "120") {
        Print-Message "yellow" "Blackwell GPU (sm_120) detected — torch 2.7.1+cu128 handles this natively"
        $env:ILLUMA_BLACKWELL = "1"
    }
    Print-Message "green" "NVIDIA check passed"
}

# ============================================================
# PHASE 4 — COMFYUI INSTALL + PYTORCH
# ============================================================
function Invoke-ComfyUIInstall {
    Print-Message "blue" "=== Phase 4: ComfyUI + PyTorch ==="

    if (Test-Sentinel "comfyui-install") {
        Print-Message "blue" "SKIP: ComfyUI already installed"
        return
    }

    $pip    = "$VENV_DIR\Scripts\pip.exe"
    $python = "$VENV_DIR\Scripts\python.exe"

    # Clone / checkout
    if (Test-Path "$COMFYUI_DIR\.git") {
        Print-Message "blue" "Repo exists — checking out snapshot commit..."
        Push-Location $COMFYUI_DIR
        git fetch origin --quiet 2>$null
        git checkout $COMFYUI_COMMIT --quiet
        Pop-Location
    } else {
        New-Item -ItemType Directory -Path (Split-Path $COMFYUI_DIR) -Force | Out-Null
        Print-Message "blue" "Cloning ComfyUI..."
        git clone $COMFYUI_REPO $COMFYUI_DIR
        if ($LASTEXITCODE -ne 0) { Die "git clone failed" }
        Push-Location $COMFYUI_DIR
        git checkout $COMFYUI_COMMIT --quiet
        Pop-Location
    }
    Print-Message "green" "ComfyUI at commit $($COMFYUI_COMMIT.Substring(0,7))"

    # Python venv
    if (-not (Test-Path "$VENV_DIR\Scripts\python.exe")) {
        Print-Message "blue" "Creating Python 3.13 venv..."
        python -m venv $VENV_DIR
        if ($LASTEXITCODE -ne 0) { Die "venv creation failed" }
        & $python -m pip install --upgrade pip --quiet
    }

    # PyTorch cu128 — exact version from PFX snapshot
    $tv = & $python -c "import torch; print(torch.__version__)" 2>$null
    if ($tv -notmatch "2\.7\.1\+cu128") {
        Print-Message "blue" "Installing torch 2.7.1+cu128..."
        & $pip install --quiet `
            "torch==2.7.1+cu128" "torchvision==0.22.1+cu128" "torchaudio==2.7.1+cu128" `
            --index-url https://download.pytorch.org/whl/cu128
        if ($LASTEXITCODE -ne 0) { Die "PyTorch install failed" }

        # Windows-specific packages from snapshot
        & $pip install --quiet "triton-windows==3.3.1.post21" 2>$null | Out-Null
        & $pip install --quiet "sageattention" --extra-index-url https://download.pytorch.org/whl/cu128 2>$null | Out-Null
    }

    $tv = & $python -c "import torch; print(torch.__version__)" 2>$null
    $cuda = & $python -c "import torch; print(torch.cuda.is_available())" 2>$null
    Print-Message "green" "torch $tv — CUDA: $cuda"

    # ComfyUI requirements
    Print-Message "blue" "Installing ComfyUI requirements.txt..."
    & $pip install --quiet -r "$COMFYUI_DIR\requirements.txt"
    if ($LASTEXITCODE -ne 0) { Die "ComfyUI requirements install failed" }

    # Persist paths for later phases
    $env:COMFYUI_PYTHON = "$VENV_DIR\Scripts\python.exe"
    $env:COMFYUI_PIP    = "$VENV_DIR\Scripts\pip.exe"

    Set-Sentinel "comfyui-install"
    Print-Message "green" "ComfyUI install complete"
}

# ============================================================
# PHASE 5 — CUSTOM NODES
# ============================================================
function Invoke-CustomNodes {
    Print-Message "blue" "=== Phase 5: Custom Nodes ==="

    if (Test-Sentinel "custom-nodes") {
        Print-Message "blue" "SKIP: Custom nodes already installed"
        return
    }

    $nodesDir = "$COMFYUI_DIR\custom_nodes"
    $pip      = "$VENV_DIR\Scripts\pip.exe"
    $python   = "$VENV_DIR\Scripts\python.exe"

    New-Item -ItemType Directory -Path $nodesDir -Force | Out-Null

    # --- Git nodes (from PFX snapshot, exact hashes) ---
    $gitNodes = @(
        @("https://github.com/giriss/comfy-image-saver",                                  "65e6903eff274a50f8b5cd768f0f96baf37baea1"),
        @("https://github.com/M1kep/ComfyLiterals",                                       "bdddb08ca82d90d75d97b1d437a652e0284a32ac"),
        @("https://github.com/evanspearman/ComfyMath",                                    "c01177221c31b8e5fbc062778fc8254aeb541638"),
        @("https://github.com/cnoellert/comfyui-corridorkey.git",                         "7d437d9549d76c5e584817d2399cf06a6d66bf0d"),
        @("https://github.com/DesertPixelAi/ComfyUI-Desert-Pixel-Nodes",                  "bde75701ab30ab11446f2e6d5a928812672f49c1"),
        @("https://github.com/Fannovel16/ComfyUI-Frame-Interpolation",                    "a969c01dbccd9e5510641be04eb51fe93f6bfc3d"),
        @("https://github.com/huagetai/ComfyUI-Gaffer",                                   "e2301a5dc9a169057dcd349ea6cd289aac881e9f"),
        @("https://github.com/spacepxl/ComfyUI-Image-Filters",                            "f73e586470e0d65a7372b328d4bccbabfc94c180"),
        @("https://github.com/kijai/ComfyUI-KJNodes",                                     "3fcd22f2fe2be69c3229f192362b91888277cbcb"),
        @("https://github.com/ltdrdata/ComfyUI-Manager",                                  "a1fc6c817b92b851886e6cfb206bf6fcb8e96fc9"),
        @("https://github.com/PozzettiAndrea/ComfyUI-SAM3",                               "f8e6cff7e3310ca7a77fbde463124a3c42b19027"),
        @("https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler",                        "4490bd1f482e026674543386bb2a4d176da245b9"),
        @("https://github.com/un-seen/comfyui-tensorops",                                 "d34488e3079ecd10db2fe867c3a7af568115faed"),
        @("https://github.com/shiimizu/ComfyUI-TiledDiffusion",                           "a155b1bac39147381aeaa52b9be42e545626a44f"),
        @("https://github.com/jamesWalker55/comfyui-various",                             "5bd85aaf7616878471469c4ec7e11bbd0cef3bf2"),
        @("https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite",                      "08e8df15db24da292d4b7f943c460dc2ab442b24"),
        @("https://github.com/YaserJaradeh/comfyui-yaser-nodes",                          "68225852a11e22e735631aa11ea065e82ea191d4"),
        @("https://github.com/cubiq/ComfyUI_essentials",                                  "9d9f4bedfc9f0321c19faf71855e228c93bd0dc9"),
        @("https://github.com/smthemex/ComfyUI_SVFR",                                    "6c7aa1bfa1f39f61b975c7a7c0f785749732e01b"),
        @("https://github.com/ssitu/ComfyUI_UltimateSDUpscale",                           "d6b575adb878c3d1c7a357f700b5c1001ccb8bd9"),
        @("https://github.com/jonstreeter/ComfyUI-Deep-Exemplar-based-Video-Colorization","ee17d03e56eac09ef98cbb93099a0534e088cdad"),
        @("https://github.com/edenartlab/eden_comfy_pipelines.git",                       "17146e129dd49d701c0d4cb78eb663f132d30a50"),
        @("https://github.com/LarryJane491/Image-Captioning-in-ComfyUI",                  "9b24deea8eef830da059aa91cac9690ecde19fda"),
        @("https://github.com/BadCafeCode/masquerade-nodes-comfyui",                      "432cb4d146a391b387a0cd25ace824328b5b61cf"),
        @("https://github.com/ClownsharkBatwing/RES4LYF",                                 "a3999a56a650da5cffe9e8f9f8b115f764603620"),
        @("https://github.com/rgthree/rgthree-comfy",                                     "2b9eb36d3e1741e88dbfccade0e08137f7fa2bfb")
    )

    Print-Message "blue" "Installing $($gitNodes.Count) git custom nodes..."
    foreach ($node in $gitNodes) {
        $url  = $node[0]; $hash = $node[1]
        $name = $url.TrimEnd('/').TrimEnd('.git').Split('/')[-1]
        $dest = "$nodesDir\$name"

        if (Test-Path "$dest\.git") {
            Push-Location $dest
            git fetch origin --quiet 2>$null
            git checkout $hash --quiet 2>$null
            Pop-Location
        } else {
            git clone $url $dest --quiet 2>$null
            if ($LASTEXITCODE -ne 0) {
                Print-Message "yellow" "  WARN: clone failed for $name — skipping"
                continue
            }
            Push-Location $dest
            git checkout $hash --quiet 2>$null
            Pop-Location
        }

        if (Test-Path "$dest\requirements.txt") {
            & $pip install --quiet -r "$dest\requirements.txt" 2>$null | Out-Null
        }
        Print-Message "blue" "  $name @ $($hash.Substring(0,7))"
    }
    Print-Message "green" "Git nodes done"

    # --- websocket_image_save.py (file node from snapshot) ---
    $wsFile = "$nodesDir\websocket_image_save.py"
    if (-not (Test-Path $wsFile)) {
        try {
            Invoke-WebRequest -Uri "https://raw.githubusercontent.com/comfyanonymous/ComfyUI/master/custom_nodes/websocket_image_save.py" `
                -OutFile $wsFile -UseBasicParsing
            Print-Message "blue" "  websocket_image_save.py installed"
        } catch {
            Print-Message "yellow" "  WARN: could not download websocket_image_save.py"
        }
    }

    # --- CNR nodes via ComfyUI-Manager CLI ---
    $cmCli = "$nodesDir\ComfyUI-Manager\cm-cli.py"
    if (Test-Path $cmCli) {
        $cnrNodes = @(
            "basic_data_handling",  "ComfyUI-Crystools",         "comfyui-custom-scripts",
            "comfyui-depthanythingv2", "comfyui-easy-use",       "comfyui-florence2",
            "ComfyUI-GGUF",         "comfyui-ic-light",          "comfyui-ic-light-video",
            "comfyui-ig-nodes",     "comfyui-inpaint-cropandstitch", "ComfyUI-MelBandRoFormer",
            "comfyui-multigpu",     "ComfyUI-QwenVL",            "comfyui-supernodes",
            "comfyui-video-matting","ComfyUI-WanAnimatePreprocess","ComfyUI-WanVideoWrapper",
            "comfyui-wd14-tagger",  "comfyui_controlnet_aux",    "comfyui_layerstyle",
            "ComfyUI_LayerStyle_Advance", "Compare_videos",       "derfuu_comfyui_moddednodes",
            "radiance",             "was-ns"
        )
        Print-Message "blue" "Installing $($cnrNodes.Count) CNR nodes via ComfyUI Manager CLI..."
        foreach ($pkg in $cnrNodes) {
            & $python $cmCli install $pkg --channel default --mode remote 2>$null | Out-Null
            Print-Message "blue" "  CNR: $pkg"
        }
        Print-Message "green" "CNR nodes done"
    } else {
        Print-Message "yellow" "ComfyUI-Manager cm-cli.py not found — CNR nodes will install on first ComfyUI launch via Manager UI"
    }

    Set-Sentinel "custom-nodes"
    Print-Message "green" "Custom nodes complete"
}

# ============================================================
# PHASE 6 — MODEL DIRECTORIES
# ============================================================
function Invoke-ModelDirectories {
    Print-Message "blue" "=== Phase 6: Model Directory Structure ==="

    $modelsDir = "$COMFYUI_DIR\models"
    $dirs = @(
        "annotator\depth-anything\Depth-Anything-V2-Large",
        "annotator\depth-anything\Depth-Anything-V2-Small",
        "annotator\hr16", "annotator\LiheYoung",
        "annotator\lllyasviel", "annotator\TheMistoAI",
        "audio_encoders", "BiRefNet", "blip",
        "checkpoints", "clip", "clip_vision", "configs",
        "controlnet", "corridorkey", "depthanything",
        "detection", "diffusers", "diffusion_models",
        "embeddings", "facerestore_models", "gligen",
        "grounding-dino", "hypernetworks", "insightface",
        "ipadapter", "latent_upscale_models", "liveportrait",
        "LLM", "loras", "model_patches", "musetalk",
        "photomaker", "rembg", "sam3", "sams", "SEEDVR2",
        "style_models", "SVFR", "text_encoders", "transformers",
        "ultralytics", "unet", "upscale_models",
        "vae", "vae_approx", "vitmatte", "xlabs"
    )

    foreach ($d in $dirs) {
        New-Item -ItemType Directory -Path "$modelsDir\$d" -Force | Out-Null
    }

    Print-Message "green" "Model directories created ($($dirs.Count) paths)"
    Print-Message "yellow" "Models must be copied/downloaded separately (PFX library ~644GB)"
}

# ============================================================
# PHASE 7 — WINDOWS SERVICE (NSSM)
# ============================================================
function Invoke-ServiceSetup {
    Print-Message "blue" "=== Phase 7: ComfyUI Windows Service ==="

    $python = "$VENV_DIR\Scripts\python.exe"
    $logDir = "$COMFYUI_DIR\logs"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null

    # Remove existing service
    $svc = Get-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue
    if ($svc) {
        nssm stop $SERVICE_NAME 2>$null | Out-Null
        nssm remove $SERVICE_NAME confirm 2>$null | Out-Null
    }

    $mainPy = "$COMFYUI_DIR\main.py"
    $args   = "$mainPy --listen 0.0.0.0 --port $COMFYUI_PORT"

    nssm install   $SERVICE_NAME $python $args
    nssm set       $SERVICE_NAME DisplayName  "ComfyUI"
    nssm set       $SERVICE_NAME Description  "ComfyUI AI image generation — Illuma"
    nssm set       $SERVICE_NAME AppDirectory $COMFYUI_DIR
    nssm set       $SERVICE_NAME Start        SERVICE_AUTO_START
    nssm set       $SERVICE_NAME AppExit      Default    Restart
    nssm set       $SERVICE_NAME AppRestartDelay 10000
    nssm set       $SERVICE_NAME AppStdout    "$logDir\comfyui.log"
    nssm set       $SERVICE_NAME AppStderr    "$logDir\comfyui-error.log"
    nssm set       $SERVICE_NAME AppRotateFiles 1
    nssm set       $SERVICE_NAME AppRotateBytes 10485760

    Start-Service $SERVICE_NAME
    Print-Message "green" "Service $SERVICE_NAME registered and started"
}

# ============================================================
# PHASE 8 — VALIDATION
# ============================================================
function Invoke-Validation {
    Print-Message "blue" "=== Phase 8: Validation ==="

    $maxAttempts = 30
    $sleepSec    = 10

    # Wait for service
    Print-Message "blue" "Waiting for service to start..."
    for ($i = 1; $i -le $maxAttempts; $i++) {
        $svc = Get-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq "Running") { break }
        if ($i -eq $maxAttempts) { Die "Service did not start. Check: Get-Content $COMFYUI_DIR\logs\comfyui-error.log -Tail 50" }
        Print-Message "blue" "  Attempt $i/$maxAttempts — waiting ${sleepSec}s..."
        Start-Sleep -Seconds $sleepSec
    }
    Print-Message "green" "Service running"

    # Wait for HTTP
    Print-Message "blue" "Waiting for ComfyUI on port $COMFYUI_PORT..."
    for ($i = 1; $i -le $maxAttempts; $i++) {
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:$COMFYUI_PORT" -UseBasicParsing -TimeoutSec 5 2>$null
            if ($r.StatusCode -lt 500) { break }
        } catch {}
        if ($i -eq $maxAttempts) { Die "ComfyUI not responding on port $COMFYUI_PORT" }
        Print-Message "blue" "  Attempt $i/$maxAttempts — waiting ${sleepSec}s..."
        Start-Sleep -Seconds $sleepSec
    }

    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback" } | Select-Object -First 1).IPAddress
    Print-Message "green" "ComfyUI is ready at http://${ip}:${COMFYUI_PORT}"
    Print-Message "blue" "  Logs:    Get-Content $COMFYUI_DIR\logs\comfyui.log -Tail 50"
    Print-Message "blue" "  Restart: Restart-Service $SERVICE_NAME"
}

# ============================================================
# PHASE 9 — REMOTE ACCESS (REEMO)
# ============================================================
function Invoke-RemoteAccess {
    Print-Message "blue" "=== Phase 9: Reemo Remote Access ==="

    if (Test-Sentinel "remote-access") {
        Print-Message "blue" "SKIP: Reemo already installed"
        return
    }

    # Firewall rules
    $rules = @(
        @{ Name="ComfyUI";       Port=$COMFYUI_PORT; Proto="TCP" },
        @{ Name="Reemo STUN UDP"; Port=3478;         Proto="UDP" },
        @{ Name="Reemo STUN TCP"; Port=3478;         Proto="TCP" },
        @{ Name="Reemo TURN TLS"; Port=5349;         Proto="TCP" }
    )
    foreach ($r in $rules) {
        Remove-NetFirewallRule -DisplayName "Illuma - $($r.Name)" -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName "Illuma - $($r.Name)" `
            -Direction Inbound -Action Allow -Protocol $r.Proto -LocalPort $r.Port | Out-Null
        Print-Message "blue" "  Firewall: $($r.Proto) $($r.Port) allowed"
    }

    # Reemo installer
    $reemoSvc = Get-Service -Name "reemod" -ErrorAction SilentlyContinue
    if ($reemoSvc) {
        Print-Message "blue" "Reemo already installed"
    } else {
        $installer = "$env:TEMP\reemo-setup.exe"
        Print-Message "blue" "Downloading Reemo installer..."
        # TODO: confirm Windows installer URL at reemo.io/download
        Invoke-WebRequest -Uri "https://download.reemo.io/windows/setup.exe" `
            -OutFile $installer -UseBasicParsing
        $keyPreview = $REEMO_TOKEN.Substring(0, [Math]::Min(12, $REEMO_TOKEN.Length))
        Print-Message "blue" "Registering Reemo (key: ${keyPreview}...)"
        Start-Process -FilePath $installer -ArgumentList "--key $REEMO_TOKEN --silent" -Wait
        Remove-Item $installer -Force -ErrorAction SilentlyContinue
        Print-Message "green" "Reemo installed"
    }

    Set-Sentinel "remote-access"
    Print-Message "green" "Remote access setup complete"
}

# ============================================================
# MAIN
# ============================================================
function Main {
    Write-Host ""
    Write-Host "================================================"
    Write-Host "  ComfyUI Windows Setup — Illuma"
    Write-Host "  ComfyUI: $($COMFYUI_COMMIT.Substring(0,7))  |  torch 2.7.1+cu128  |  Python 3.13"
    Write-Host "================================================"
    Write-Host ""
    Write-Host "  Install dir : $COMFYUI_DIR"
    Write-Host "  Port        : $COMFYUI_PORT"
    Write-Host "  GPU target  : RTX 5090 / A6000 (cu128)"
    Write-Host ""

    $r = Read-Host "Continue? [y/N]"
    if ($r -notmatch '^[Yy]$') { exit 0 }

    Setup-Logging

    Invoke-PreFlight
    Invoke-SystemSetup
    Invoke-NvidiaCheck
    Invoke-ComfyUIInstall
    Invoke-CustomNodes
    Invoke-ModelDirectories
    Invoke-ServiceSetup
    Invoke-Validation
    Invoke-RemoteAccess

    Write-Host ""
    Print-Message "green" "================================================"
    Print-Message "green" "  ComfyUI setup complete!"
    Print-Message "green" "  URL: http://localhost:$COMFYUI_PORT"
    Print-Message "green" "================================================"
    Write-Host ""
    Print-Message "blue" "Next step: copy models into $COMFYUI_DIR\models\"
}

Main
