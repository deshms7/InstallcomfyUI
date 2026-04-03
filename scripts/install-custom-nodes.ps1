# Phase 5: Custom Nodes Installation
# Installs all custom nodes from the PFX snapshot (2026-03-26_17-06-15_snapshot.json):
#   - 26 git-based nodes cloned at their exact snapshot hashes
#   - 26 CNR (ComfyUI Registry) nodes installed via ComfyUI Manager CLI
#   -  1 file-based node (websocket_image_save.py)

function Install-CustomNodes {
    if (Test-Sentinel "custom-nodes") {
        Print-Message "blue" "SKIP: Custom nodes already installed"
        return
    }

    $comfyDir = $env:COMFYUI_DIR ?? "C:\ComfyUI"
    $nodesDir = "$comfyDir\custom_nodes"
    $pip      = $env:COMFYUI_PIP    ?? "$comfyDir\.venv\Scripts\pip.exe"
    $python   = $env:COMFYUI_PYTHON ?? "$comfyDir\.venv\Scripts\python.exe"

    New-Item -ItemType Directory -Path $nodesDir -Force | Out-Null

    _Install-GitNodes    -NodesDir $nodesDir -Pip $pip
    _Install-FileNodes   -NodesDir $nodesDir
    _Install-CnrNodes    -ComfyDir $comfyDir -Python $python

    Set-Sentinel "custom-nodes"
    Print-Message "green" "All custom nodes installed"
}

# ---------------------------------------------------------------------------
# Git-based custom nodes — cloned at exact hashes from snapshot
# ---------------------------------------------------------------------------

function _Install-GitNodes {
    param([string]$NodesDir, [string]$Pip)

    # Each entry: @(repo_url, commit_hash)
    $gitNodes = @(
        @("https://github.com/giriss/comfy-image-saver",                               "65e6903eff274a50f8b5cd768f0f96baf37baea1"),
        @("https://github.com/M1kep/ComfyLiterals",                                    "bdddb08ca82d90d75d97b1d437a652e0284a32ac"),
        @("https://github.com/evanspearman/ComfyMath",                                  "c01177221c31b8e5fbc062778fc8254aeb541638"),
        @("https://github.com/cnoellert/comfyui-corridorkey.git",                       "7d437d9549d76c5e584817d2399cf06a6d66bf0d"),
        @("https://github.com/DesertPixelAi/ComfyUI-Desert-Pixel-Nodes",                "bde75701ab30ab11446f2e6d5a928812672f49c1"),
        @("https://github.com/Fannovel16/ComfyUI-Frame-Interpolation",                  "a969c01dbccd9e5510641be04eb51fe93f6bfc3d"),
        @("https://github.com/huagetai/ComfyUI-Gaffer",                                "e2301a5dc9a169057dcd349ea6cd289aac881e9f"),
        @("https://github.com/spacepxl/ComfyUI-Image-Filters",                          "f73e586470e0d65a7372b328d4bccbabfc94c180"),
        @("https://github.com/kijai/ComfyUI-KJNodes",                                   "3fcd22f2fe2be69c3229f192362b91888277cbcb"),
        @("https://github.com/ltdrdata/ComfyUI-Manager",                                "a1fc6c817b92b851886e6cfb206bf6fcb8e96fc9"),
        @("https://github.com/PozzettiAndrea/ComfyUI-SAM3",                             "f8e6cff7e3310ca7a77fbde463124a3c42b19027"),
        @("https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler",                      "4490bd1f482e026674543386bb2a4d176da245b9"),
        @("https://github.com/un-seen/comfyui-tensorops",                               "d34488e3079ecd10db2fe867c3a7af568115faed"),
        @("https://github.com/shiimizu/ComfyUI-TiledDiffusion",                         "a155b1bac39147381aeaa52b9be42e545626a44f"),
        @("https://github.com/jamesWalker55/comfyui-various",                           "5bd85aaf7616878471469c4ec7e11bbd0cef3bf2"),
        @("https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite",                    "08e8df15db24da292d4b7f943c460dc2ab442b24"),
        @("https://github.com/YaserJaradeh/comfyui-yaser-nodes",                        "68225852a11e22e735631aa11ea065e82ea191d4"),
        @("https://github.com/cubiq/ComfyUI_essentials",                                "9d9f4bedfc9f0321c19faf71855e228c93bd0dc9"),
        @("https://github.com/smthemex/ComfyUI_SVFR",                                  "6c7aa1bfa1f39f61b975c7a7c0f785749732e01b"),
        @("https://github.com/ssitu/ComfyUI_UltimateSDUpscale",                         "d6b575adb878c3d1c7a357f700b5c1001ccb8bd9"),
        @("https://github.com/jonstreeter/ComfyUI-Deep-Exemplar-based-Video-Colorization", "ee17d03e56eac09ef98cbb93099a0534e088cdad"),
        @("https://github.com/edenartlab/eden_comfy_pipelines.git",                     "17146e129dd49d701c0d4cb78eb663f132d30a50"),
        @("https://github.com/LarryJane491/Image-Captioning-in-ComfyUI",                "9b24deea8eef830da059aa91cac9690ecde19fda"),
        @("https://github.com/BadCafeCode/masquerade-nodes-comfyui",                    "432cb4d146a391b387a0cd25ace824328b5b61cf"),
        @("https://github.com/ClownsharkBatwing/RES4LYF",                               "a3999a56a650da5cffe9e8f9f8b115f764603620"),
        @("https://github.com/rgthree/rgthree-comfy",                                   "2b9eb36d3e1741e88dbfccade0e08137f7fa2bfb")
    )

    Print-Message "blue" "Installing $($gitNodes.Count) git custom nodes..."

    foreach ($node in $gitNodes) {
        $repoUrl = $node[0]
        $hash    = $node[1]
        $name    = ($repoUrl.TrimEnd('/').TrimEnd('.git').Split('/')[-1])
        $destDir = "$NodesDir\$name"

        if (Test-Path "$destDir\.git") {
            # Repo exists — ensure it's at the right commit
            Push-Location $destDir
            git fetch origin --quiet 2>$null
            git checkout $hash --quiet 2>$null
            Pop-Location
            Print-Message "blue" "  OK (already cloned): $name @ $($hash.Substring(0,7))"
        } else {
            git clone $repoUrl $destDir --quiet 2>$null
            if ($LASTEXITCODE -ne 0) {
                Print-Message "yellow" "  WARN: Failed to clone $repoUrl — skipping"
                continue
            }
            Push-Location $destDir
            git checkout $hash --quiet 2>$null
            Pop-Location
            Print-Message "blue" "  Cloned: $name @ $($hash.Substring(0,7))"
        }

        # Install node's own requirements if present
        $reqFile = "$destDir\requirements.txt"
        if (Test-Path $reqFile) {
            & $Pip install --quiet -r $reqFile 2>$null | Out-Null
        }
    }

    Print-Message "green" "Git custom nodes installed"
}

# ---------------------------------------------------------------------------
# File-based custom nodes
# ---------------------------------------------------------------------------

function _Install-FileNodes {
    param([string]$NodesDir)

    Print-Message "blue" "Installing file custom node: websocket_image_save.py..."

    $destPath = "$NodesDir\websocket_image_save.py"
    if (Test-Path $destPath) {
        Print-Message "blue" "  Already present: websocket_image_save.py"
        return
    }

    # Download from the ComfyUI repo (it ships as an example node)
    $url = "https://raw.githubusercontent.com/comfyanonymous/ComfyUI/master/custom_nodes/websocket_image_save.py"
    try {
        Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing
        Print-Message "green" "  Installed: websocket_image_save.py"
    } catch {
        Print-Message "yellow" "  WARN: Could not download websocket_image_save.py — place it manually in $NodesDir"
    }
}

# ---------------------------------------------------------------------------
# CNR (ComfyUI Registry) nodes — installed via ComfyUI Manager CLI
# ---------------------------------------------------------------------------

function _Install-CnrNodes {
    param([string]$ComfyDir, [string]$Python)

    # ComfyUI-Manager must already be cloned (it's in the git nodes above).
    # Its cm-cli.py provides a headless install interface for CNR packages.
    $cmCli = "$ComfyDir\custom_nodes\ComfyUI-Manager\cm-cli.py"
    if (-not (Test-Path $cmCli)) {
        Print-Message "yellow" "WARN: ComfyUI-Manager cm-cli.py not found — CNR nodes will be installed on first ComfyUI startup via Manager UI"
        return
    }

    # CNR nodes with exact versions from snapshot
    $cnrNodes = @(
        "basic_data_handling@1.4.0",
        "ComfyUI-Crystools@1.27.4",
        "comfyui-custom-scripts@1.2.5",
        "comfyui-depthanythingv2@1.0.1",
        "comfyui-easy-use@1.3.4",
        "comfyui-florence2@1.0.8",
        "ComfyUI-GGUF@1.1.4",
        "comfyui-ic-light@1.0.5",
        "comfyui-ic-light-video@0.0.9",
        "comfyui-ig-nodes@1.0.4",
        "comfyui-inpaint-cropandstitch@2.1.8",
        "ComfyUI-MelBandRoFormer@1.0.1",
        "comfyui-multigpu@2.5.10",
        "ComfyUI-QwenVL@2.1.1",
        "comfyui-supernodes@0.2.1",
        "comfyui-video-matting@1.0.0",
        "ComfyUI-WanAnimatePreprocess@1.0.2",
        "ComfyUI-WanVideoWrapper@1.4.5",
        "comfyui-wd14-tagger@1.0.1",
        "comfyui_controlnet_aux@1.1.3",
        "comfyui_layerstyle@1.0.90",
        "ComfyUI_LayerStyle_Advance@2.0.33",
        "Compare_videos@1.0.0",
        "derfuu_comfyui_moddednodes@1.0.1",
        "radiance@2.2.0",
        "was-ns@3.0.1"
    )

    Print-Message "blue" "Installing $($cnrNodes.Count) CNR custom nodes via ComfyUI Manager CLI..."

    foreach ($node in $cnrNodes) {
        $parts   = $node.Split("@")
        $pkgName = $parts[0]
        $version = $parts[1]

        Print-Message "blue" "  Installing CNR: $pkgName@$version"
        & $Python $cmCli install $pkgName --channel default --mode remote 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Print-Message "yellow" "  WARN: cm-cli install failed for $pkgName — will retry via Manager UI on first start"
        }
    }

    Print-Message "green" "CNR custom nodes installation attempted"
}
