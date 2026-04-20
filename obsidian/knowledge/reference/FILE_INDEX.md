# File Index

One-line descriptions of top-level tree. For deeper per-module
structure see [[codebase/CODEBASE_MAP]] and the per-module pages under
`codebase/modules/`.

## Source
| Path | Role |
| --- | --- |
| `Jarvis/App/` | `JarvisCLI` target entry (`main.swift`). |
| `Jarvis/Sources/JarvisCore/` | Core Swift library (18 modules). |
| `Jarvis/Mac/` | macOS app shell. |
| `Jarvis/Mobile/` | iOS app. |
| `Jarvis/Watch/` | watchOS app + extension. |
| `Jarvis/Shared/` | Cross-platform wire format + crypto. |
| `Jarvis/MobileShared/` | iOS-only shared utilities. |
| `Jarvis/Tests/` | Swift test suites. See [[codebase/testing/TestSuite]]. |
| `Sources/` | Misc Swift sources outside the Jarvis target tree. |
| `Tests/` | Companion to `Sources/`. |
| `vendor/mlx-audio-swift/` | Vendored MLXAudio package. |

## Services / backends
| Path | Role |
| --- | --- |
| `services/jarvis-linux-node/` | Out-of-band tunnel daemon. |
| `services/vibevoice-tts/` | FastAPI TTS. |
| `convex/` | Convex schema + functions (`schema.ts`). |
| `Archon/` | Workflow DAGs (`default_workflow.yaml`). |
| `workshop/` | Experimental / staging area. |
| `cockpit/` | Web UI frontend. |
| `pwa/` | Progressive Web App + Unity WebGL loader. |
| `xr.grizzlymedicine.icu/` | Public XR landing. |
| `elijah_frames/`, `mcuhist/` | Canon corpus assets + indexes. |

## Canon + principles
| Path | Role |
| --- | --- |
| `CANON/` | Canon corpus + manifest. |
| `PRINCIPLES.md` | Founding principles. |
| `SOUL_ANCHOR.md` | Soul Anchor doctrine. |
| `VERIFICATION_PROTOCOL.md` | A&Ox4 verification rules. |
| `SOUL_ANCHOR.md` | Identity doctrine. |

## Specs / history
| Path | Role |
| --- | --- |
| `VULNERABILITY_CROSSREFERENCE_REPAIR_SPEC.md` | Master dedup + REPAIR list. |
| `GLM51_JOKER_*`, `QWEN_HARLEY_*`, `DEEPSEEK_REPAIR_SPEC.md`, etc. | Round-specific audits. See [[history/AUDIT_ROUNDS]]. |
| `claude*.md`, `glm*.md`, `gemmalog1.md` | Session transcripts. See [[history/SESSION_LOGS_INDEX]]. |
| `015-glm-redteam-remediation-TURNOVER.md`, `FINAL_PUSH_HANDOFF.md` | Handoffs. |
| `JARVIS_INTELLIGENCE_*`, `JARVIS_TRAINING_BRIEF.txt` | Rendered briefings. |

## Build + scripts
| Path | Role |
| --- | --- |
| `project.yml` | XcodeGen spec → `Jarvis.xcodeproj/`. |
| `Jarvis.xcodeproj/` | Generated Xcode project. |
| `jarvis.xcworkspace/` | Xcode workspace. |
| `Package.swift` | **Stub** (`tempcheck`) — not used. |
| `scripts/` | Zsh/Python operational scripts. See [[codebase/scripts/README]]. |

## Storage / runtime artifacts
| Path | Role |
| --- | --- |
| `checkpoints/` | Session checkpoints. |
| `storage/` | Runtime-persistent data. |
| `exports/` | Export destinations. |
| `voice-samples/` | Reference audio for voice cloning. |
| `obsidian/` | This wiki. |

## See also
- [[codebase/CODEBASE_MAP]]
- [[reference/ENTRY_POINTS]]
- [[reference/BUILD_AND_TEST]]
- [[reference/DEPENDENCIES]]
- [[reference/DEPLOYMENT]]
