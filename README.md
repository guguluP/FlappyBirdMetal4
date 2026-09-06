# Flappy Bird 3D — Metal 4 (Swift)

A Flappy Bird–style game for **iPhone** and **Mac**, rendered with Apple’s **Metal 4** graphics architecture, **true 3D characters & objects**, and written in **Swift**.

**Location:** `~/Desktop/FlappyBirdMetal4`

## Requirements

| Item | Version |
|------|---------|
| macOS | **26+** (Tahoe) with Apple silicon (Metal 4) |
| Xcode | **26/27+** with Metal toolchain |
| iOS / iPhone | **26+** (iPhone & iPad; portrait game) |
| GPU | Metal 4 capable (Apple silicon) |
| Apple Intelligence coach | Optional — Apple Intelligence–eligible devices with AI enabled (e.g. iPhone 15 Pro+, M-series Mac). Others get offline tips. |

## Platforms

| Platform | Status |
|----------|--------|
| **iPhone** | Full game + haptics + portrait HUD |
| **iPad** | Supported (iPhone/iPad device family) |
| **Mac** | Full Metal 4 path, click / Space |

## Apple Intelligence

Uses the on-device **Foundation Models** framework (`SystemLanguageModel`) when available:

- **Ready screen** — short tip to start
- **Game over** — personalized one-liner from score / coins / best

If the device is not eligible, Apple Intelligence is off, or the model is still downloading, the app falls back to built-in coach tips automatically.

## What’s in the 3D build

- **Lit 3D meshes** with normals, Phong specular, rim lighting, and depth buffering  
- **3D bird character**: body, head, beak, eyes, crest, animated wings, tail  
- **Cylindrical pipes** with extruded lips  
- **Spinning gold ring collectibles** in pipe gaps (+2 score)  
- **Parallax 3D hills**, thick ground slab, volumetric-style sky clouds  
- **Feather / sparkle particles** on flap, crash, and coin pickup  
- **Perspective camera** for depth pop while keeping classic side-scroll gameplay  
- **Apple Intelligence coach** (when supported)

## Open & run

1. Open `FlappyBirdMetal4.xcodeproj` in Xcode.  
2. Select the **FlappyBirdMetal4** scheme.  
3. Choose a destination:
   - **My Mac** for desktop  
   - An **iPhone** or simulator for mobile  
4. Press **Run** (⌘R).

If code signing fails, set your **Team** under *Signing & Capabilities*.

### CLI (macOS)

```bash
cd ~/Desktop/FlappyBirdMetal4
xcodebuild -scheme FlappyBirdMetal4 -destination 'platform=macOS' -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/FlappyBirdMetal4-*/Build/Products/Debug/FlappyBirdMetal4.app
```

## Controls

| Platform | Action |
|----------|--------|
| iPhone   | Tap to flap / restart |
| Mac      | Click or **Space** to flap / restart |

## Scoring

| Event | Points |
|-------|--------|
| Pass a pipe | +1 |
| Collect a gold ring | +2 |

High score is stored in `UserDefaults`.

## Metal 4 architecture used

| API | Role in this game |
|-----|-------------------|
| `MTL4Compiler` | Compiles MSL from source into libraries and render pipelines |
| `MTL4CommandAllocator` | Explicit command-buffer memory |
| `MTL4CommandBuffer` | Begin/end command buffer with allocator |
| `MTL4RenderCommandEncoder` | Draw sky + lit 3D world |
| `MTL4ArgumentTable` | Bind buffer GPU addresses to shader slots |
| `MTL4CommandQueue` | `waitForDrawable` → `commit` → `signalDrawable` → `present` |
| `MTLResidencySet` | Make buffers/textures resident for Metal 4 execution |
| Depth buffer | Correct occlusion for 3D meshes |

## Project layout

```
FlappyBirdMetal4/
├── FlappyBirdMetal4.xcodeproj
├── README.md
└── FlappyBirdMetal4/
    ├── FlappyBirdApp.swift      # Multiplatform SwiftUI entry (iPhone + Mac)
    ├── ContentView.swift        # HUD (score, coins, best, AI coach)
    ├── Game/GameState.swift     # Physics, coins, particles
    ├── Intelligence/
    │   └── AppleIntelligenceCoach.swift  # Foundation Models + offline tips
    ├── Metal/
    │   ├── Metal4Renderer.swift # Metal 4 + 3D mesh builder
    │   ├── MetalGameView.swift  # MTKView bridge (iOS + macOS)
    │   └── Shaders.metal        # Lit 3D + sky MSL
    └── Assets.xcassets
```

## Notes

- Deployment targets are **iOS 26** and **macOS 26** (Metal 4 availability).  
- **Mac** and **physical iPhone** use the full Metal 4 command path.  
- **iOS Simulator** currently ships stub Metal 4 headers, so the project falls back to classic Metal there for development only.  
- All art is procedural 3D geometry (no external model files).  
