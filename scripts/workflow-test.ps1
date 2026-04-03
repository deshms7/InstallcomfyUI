# Phase 9: End-to-End Workflow Test
# Submits a minimal txt2img job via the ComfyUI API and verifies GPU inference works.
# No docker exec — all API calls go directly to localhost.

$ComfyPort = $env:COMFYUI_PORT ?? "8188"

function Invoke-WorkflowTest {
    if (Test-Sentinel "workflow-test") {
        Print-Message "blue" "SKIP: Workflow test already passed"
        return
    }

    Print-Message "blue" "Running end-to-end workflow test..."

    _Download-TestModel
    _Submit-TestWorkflow

    Set-Sentinel "workflow-test"
    Print-Message "green" "Workflow test passed — GPU inference is working"
}

function _Download-TestModel {
    $comfyDir  = $env:COMFYUI_DIR ?? "C:\ComfyUI"
    $modelDir  = "$comfyDir\models\checkpoints"
    $modelFile = "$modelDir\v1-5-pruned-emaonly.safetensors"

    New-Item -ItemType Directory -Path $modelDir -Force | Out-Null

    if (Test-Path $modelFile) {
        Print-Message "blue" "Test model already present: $modelFile"
        return
    }

    Print-Message "blue" "Downloading SD1.5 test model (~4GB)..."
    $modelUrl = "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors"
    Invoke-WebRequest -Uri $modelUrl -OutFile $modelFile -UseBasicParsing
    if (-not (Test-Path $modelFile)) { Die "Model download failed" }
    Print-Message "green" "Test model downloaded"
}

function _Submit-TestWorkflow {
    # Minimal 1-step 64x64 workflow — just proves inference works, not quality
    $workflow = @{
        prompt = @{
            "1" = @{ class_type = "CheckpointLoaderSimple"; inputs = @{ ckpt_name = "v1-5-pruned-emaonly.safetensors" } }
            "2" = @{ class_type = "CLIPTextEncode"; inputs = @{ text = "a red apple"; clip = @("1", 1) } }
            "3" = @{ class_type = "CLIPTextEncode"; inputs = @{ text = ""; clip = @("1", 1) } }
            "4" = @{ class_type = "EmptyLatentImage"; inputs = @{ width = 64; height = 64; batch_size = 1 } }
            "5" = @{ class_type = "KSampler"; inputs = @{ seed = 42; steps = 1; cfg = 1.0; sampler_name = "euler"; scheduler = "normal"; denoise = 1.0; model = @("1", 0); positive = @("2", 0); negative = @("3", 0); latent_image = @("4", 0) } }
            "6" = @{ class_type = "VAEDecode"; inputs = @{ samples = @("5", 0); vae = @("1", 2) } }
            "7" = @{ class_type = "SaveImage"; inputs = @{ filename_prefix = "workflow-test"; images = @("6", 0) } }
        }
    } | ConvertTo-Json -Depth 10

    $apiUrl = "http://localhost:$ComfyPort"

    $submitResult = Invoke-RestMethod -Uri "$apiUrl/prompt" `
        -Method Post -Body $workflow -ContentType "application/json"

    if (-not $submitResult.prompt_id) {
        Die "Workflow submission failed: $submitResult"
    }

    $promptId = $submitResult.prompt_id
    Print-Message "blue" "Workflow submitted, prompt_id: $promptId"
    Print-Message "blue" "Waiting for inference to complete (up to 10 min)..."

    for ($i = 1; $i -le 60; $i++) {
        Start-Sleep -Seconds 10
        try {
            $history = Invoke-RestMethod -Uri "$apiUrl/history/$promptId"
            if ($history.$promptId.status.completed -eq $true) {
                Print-Message "green" "Inference completed successfully"
                return
            }
        } catch {}
        Print-Message "blue" "  Attempt $i/60 — still running..."
    }

    Die "Workflow did not complete within 10 minutes"
}
