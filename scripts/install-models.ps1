# Phase 6: Model Directory Structure
# Creates the full model folder hierarchy matching PFX's D:\ComfyUI\ComfyUI\models layout.
# Models themselves are NOT downloaded here — the library is 644GB and PFX will decide
# which models to include. This script only creates the directories so ComfyUI starts cleanly.
#
# Source: Comfy_models.txt (directory listing from PFX's D:\ComfyUI\ComfyUI\models)

function Initialize-ModelDirectories {
    $comfyDir  = $env:COMFYUI_DIR ?? "C:\ComfyUI"
    $modelsDir = "$comfyDir\models"

    Print-Message "blue" "Creating model directory structure at $modelsDir..."

    # Top-level model directories (from Comfy_models.txt)
    $dirs = @(
        "annotator\depth-anything\Depth-Anything-V2-Large",
        "annotator\depth-anything\Depth-Anything-V2-Small",
        "annotator\hr16",
        "annotator\LiheYoung",
        "annotator\lllyasviel",
        "annotator\TheMistoAI",
        "audio_encoders",
        "BiRefNet",
        "blip",
        "checkpoints",
        "clip",
        "clip_vision",
        "configs",
        "controlnet",
        "corridorkey",
        "depthanything",
        "detection",
        "diffusers",
        "diffusion_models",
        "embeddings",
        "facerestore_models",
        "gligen",
        "grounding-dino",
        "hypernetworks",
        "insightface",
        "ipadapter",
        "latent_upscale_models",
        "liveportrait",
        "LLM",
        "loras",
        "model_patches",
        "musetalk",
        "photomaker",
        "rembg",
        "sam3",
        "sams",
        "SEEDVR2",
        "style_models",
        "SVFR",
        "text_encoders",
        "transformers",
        "ultralytics",
        "unet",
        "upscale_models",
        "vae",
        "vae_approx",
        "vitmatte",
        "xlabs"
    )

    foreach ($d in $dirs) {
        New-Item -ItemType Directory -Path "$modelsDir\$d" -Force | Out-Null
    }

    Print-Message "green" "Model directories created ($($dirs.Count) paths)"
    Print-Message "yellow" "NOTE: Models must be copied/downloaded separately."
    Print-Message "yellow" "      PFX model library is ~644GB — coordinate with PFX which models to include."
}
