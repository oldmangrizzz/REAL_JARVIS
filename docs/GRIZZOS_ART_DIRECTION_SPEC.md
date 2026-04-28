# GrizzOS Art Direction & Visual Fidelity Specification
## Tactical Wilderness FOB Aesthetic

### 1. Vision Statement
The GrizzOS environment must be a 1:1 realization of the "Tactical Wilderness Command Center" concept art. It is a gritty, high-tactility Forward Operating Base (FOB) that blends ancient craftsmanship with military-grade tech.

**HARD RULE:** No generic, clean, or "neon-strip" cyberpunk aesthetics. Every surface must have history, weight, and texture.

### 2. URP Lighting & Lightmapping
#### 2.1 Static Lighting (Baked)
*   **Primary Source:** Suspended cage lights (Edison bulbs).
    *   **Color:** Warm Amber (2200K / Hex #FFB042).
    *   **Intensity:** 1.5 - 2.0 Lux.
    *   **Attenuation:** Inverse Squared.
*   **Shadows:** High-fidelity soft shadows for the Yggdrasil table and server racks.
*   **Strategy:** Use **Progressive CPU/GPU Lightmapper** for all static meshes (Floor, Beams, Table, Racks).

#### 2.2 Dynamic Lighting (Real-time)
*   **The Breach:** High-intensity emerald-green point lights (#00FF41) with volumetric scattering.
*   **Operator HUD:** Low-intensity green spill light casting onto the Operator's virtual arms.
*   **External Environment:** Cool, low-intensity blue-grey directional light (PNW Forest vibe) entering from the hangar doors.

### 3. Post-Processing Volume Profile
*   **Bloom:**
    *   **Threshold:** 0.95.
    *   **Intensity:** 1.4.
    *   **Scatter:** 0.7.
    *   **Purpose:** Enforce the "glow" of green-phosphor terminal text and data clouds.
*   **Color Grading:**
    *   **Tone Mapping:** Filmic (ACES).
    *   **Temperature:** -10 (Cool).
    *   **Contrast:** +15 (High contrast for tactical legibility).
    *   **Saturation:** -5 (Slightly desaturated for gritty feel).
*   **Volumetric Fog:**
    *   **Density:** 0.05.
    *   **Height Fog:** High density near the floor and hangar opening to simulate mountain mist.
*   **Vignette:** 0.35 (Classic operator terminal perspective).

### 4. Material Specification (PBR)
#### 4.1 The Yggdrasil War Table
*   **Base:** Dark Carved Oak.
*   **Normal Map:** High-fidelity carvings derived from the concept art.
*   **Smoothness:** 0.15 (Matte) with 0.6 (Gloss) inside the carvings to catch light.
*   **Detail:** Subtle dust/ash layers in the recesses.

#### 4.2 Industrial Steel (Beams & Racks)
*   **Base:** Rusted/Cold Rolled Steel.
*   **Metallic:** 0.9.
*   **Smoothness:** 0.4.
*   **Noise:** Edge-wear and rust patches (Hex #8B4513) on sharp corners.

#### 4.3 Wet Concrete (Floor)
*   **Base:** Dark Grey Concrete.
*   **Smoothness Map:** Varies by puddle location (0.9 for wet spots, 0.1 for dry).
*   **Normal Map:** Micro-pitting and tire tread marks from the Overland Rig.

#### 4.4 HUD / Data Clouds (VFX)
*   **Shader:** Unlit Emissive with Scanline alpha-clipping.
*   **Color:** Deep Phosphor Green (#00FF41).

### 5. Technical Art Constraints
*   **LOD Bias:** Aggressive for WebGL builds, High-Fidelity for Quest 3 native builds.
*   **Texture Resolution:** 2K minimum for the Table and HUD; 1K for environment.
*   **Draw Calls:** Minimize via Static Batching for the hangar structure.

---
*Authorized by Lead Technical Artist for GMRI.*
