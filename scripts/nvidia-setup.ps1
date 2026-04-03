# Phase 3: NVIDIA Driver Validation
# Confirms drivers and CUDA are present. No container toolkit needed —
# ComfyUI accesses the GPU directly via PyTorch + CUDA on native Windows.

function Test-NvidiaDriver {
    Print-Message "blue" "Validating NVIDIA driver and CUDA..."

    if (-not (Test-CommandExists "nvidia-smi")) {
        Die "nvidia-smi not found. Install NVIDIA drivers from https://www.nvidia.com/drivers before running."
    }

    $smiOut = nvidia-smi --query-gpu=name,driver_version,compute_cap --format=csv,noheader 2>$null
    if (-not $smiOut) { Die "nvidia-smi failed — check driver installation." }
    Print-Message "green" "NVIDIA driver OK: $smiOut"

    # Detect Blackwell GPUs (sm_120 = RTX 5000/5090 series).
    # PFX snapshot already uses torch 2.7.1+cu128 which supports sm_120 natively,
    # so no post-install upgrade is needed — we just flag it for awareness.
    $computeCap = nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>$null |
        Select-Object -First 1
    $computeCap = $computeCap.Trim().Replace(".", "")
    if ($computeCap -eq "120") {
        Print-Message "yellow" "Blackwell GPU detected (sm_120). torch 2.7.1+cu128 will be installed — no extra steps needed."
        $env:ILLUMA_BLACKWELL_GPU = "1"
    } else {
        Print-Message "green" "GPU compute capability: sm_$computeCap"
    }

    Print-Message "green" "NVIDIA validation passed"
}
