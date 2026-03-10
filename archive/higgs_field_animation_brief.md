# Kuro "Ink Formation" Animation — Higgs Field Platform Brief

## What is Higgs Field?
Higgs Field is a browser-based motion design platform for creating particle systems, generative animations, and real-time visual effects using nodes/modular workflow.

---

## Animation Concept: "Curated from Chaos"

**The Story:**
2,000 particles float in a dark void (representing the endless sea of anime content). A gravitational field shaped like the Kuro "K" activates, pulling particles into brushstroke paths. They coalesce into ink texture, washi paper fades in, and a red seal stamps the final frame.

**Duration:** 3.0 seconds  
**Resolution:** 1080×1080px (Instagram Square) + 1080×1920px (Reels/Stories)  
**Frame Rate:** 60fps  

---

## Higgs Field Node Setup

### 1. PARTICLE SYSTEM NODE
```
Particle Emitter
├── Type: Burst (frame 0)
├── Count: 2000
├── Shape: Sphere (radius 0.5)
└── Velocity: Random Direction × 2.0
```

### 2. PHYSICS PHASES (Animation Module)

**Phase 1: Chaos (0.0s - 1.0s)**
```
Force Field: Turbulence
├── Noise Scale: 3.0
├── Strength: 0.8
├── Frequency: 0.5
└── Damping: 0.95 (particles slow over time)
```

**Phase 2: Attraction (1.0s - 2.0s)**
```
Force Field: Path Attractor (K Shape)
├── Path: SVG Import (K_stroke_paths.svg)
├── Attraction Radius: 0.3
├── Strength: Animate 0.0 → 0.5 (ease-in)
├── Path Follow: 0.9 (stick to stroke)
└── Vortex: 0.2 (swirl as they approach)
```

**Phase 3: Lock (2.0s - 2.5s)**
```
Behavior: Snap to Grid
├── Grid: Particle positions from K texture
├── Snap Speed: 0.1s
├── Jitter: 0.02 (organic imperfection)
└── Scale Variation: 0.8-1.2 (brush texture)
```

### 3. RENDER PIPELINE

**Particle Appearance**
```
Particle Shape: Soft Circle
├── Size: 8px base, 12px near strokes
├── Opacity: 0.9
├── Blend Mode: Normal (0-1.5s), Additive (1.5-2.0s)
└── Color: #1a1a1f (deep ink black)
```

**Trail Effect (1.0s - 2.0s only)**
```
Trail Module
├── Length: 0.2s
├── Fade: Exponential
├── Color: #2a2520 (warm black)
└── Width: Taper 100% → 0%
```

**Glow/Bloom**
```
Post-Process: Bloom
├── Threshold: 0.7
├── Intensity: 0.5 (animate 0→1 during formation)
├── Radius: 20px
└── Color: #d4af37 (subtle gold warmth)
```

### 4. BACKGROUND LAYERS

**Layer 1: Void (0.0s - 2.0s)**
```
Solid: #0a0a0e
Noise: Grain (subtle, 5% opacity)
```

**Layer 2: Washi Paper (fade in 2.0s - 2.3s)**
```
Solid: #f5f0e8
Texture: Paper Fiber (tileable, 20% opacity)
Blend: Multiply over particles at 2.0s
```

**Layer 3: Vignette (always on)**
```
Radial Gradient: Center transparent, edges #0a0a0e at 30%
```

### 5. SEAL ANIMATION (2.5s - 3.0s)

**Asset:** Red circle (hanko seal)  
**Animation:**
```
Seal Drop
├── Start: Scale 3.0, Position (0.65, 0.65), Opacity 0
├── Mid: Scale 0.9 (2.8s) - "impact"
├── End: Scale 1.0, Bounce easing
├── Rotation: -5° (slight imperfection)
└── Color: #c84b3f
```

**Impact Effect**
```
Shockwave Ring
├── Center: Seal position
├── Radius: Animate 0 → 100px
├── Thickness: 3px → 0px
├── Opacity: 0.8 → 0
└── Duration: 0.15s
```

---

## Keyframe Summary

| Time | Event | Higgs Field Action |
|------|-------|-------------------|
| 0.00s | Burst | Emitter triggers, particles spawn |
| 0.25s | Chaos peak | Turbulence at max |
| 1.00s | Field activates | Path Attractor strength 0→0.5 |
| 1.50s | Formation visible | Trails active, glow starts |
| 2.00s | Coalesce | Snap to grid, paper fades in |
| 2.30s | Texture solid | Bloom intensity peaks |
| 2.50s | Seal trigger | Seal asset drops |
| 2.80s | Impact | Shockwave, bounce easing |
| 3.00s | Hold | Final frame, breathing loop point |

---

## Assets to Import into Higgs Field

1. **K_stroke_paths.svg** — Three bezier curves (vertical, upper diagonal, lower diagonal)
2. **washi_paper_texture.png** — Tileable paper fiber texture
3. **seal_hanko.png** — Red circle with slight edge roughness

---

## Export Settings

```
Format: MP4 (H.264) + GIF (for social)
Resolution: 1080×1080 (square), 1080×1920 (vertical)
FPS: 60
Bitrate: 10Mbps
Color Space: sRGB
Loop: Seamless (hold last frame 0.5s)
```

---

## Creative Notes

- **Particle color** should feel like liquid ink, not digital dots
- **Turbulence** in Phase 1 should feel organic, not mechanical
- **Path following** should have momentum — particles overshoot slightly then settle
- **Seal stamp** is the punctuation mark — it should feel satisfying/heavy
- **Final hold** should "breathe" — subtle 2% scale pulse on the K

---

## Reference Links for Higgs Field

- Platform: higgsfield.ai
- Style: Cinematic particle systems, editorial motion
- Similar work: Ink in water macros, sumi-nagashi films, node-based generative art
