import Foundation
@testable import JarvisCore

func makeTestWorkspace() throws -> WorkspacePaths {
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let directories = [
        "agent-skills/skills",
        "Jarvis/Sources/JarvisCore/RLM",
        "Archon",
        ".jarvis/storage",
        ".jarvis/telemetry",
        ".jarvis/traces",
        ".jarvis/soul_anchor"
    ]
    for directory in directories {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
    }

    // Satisfy A&Ox4 Event probe: create a fresh telemetry file
    let dummyTelemetry = root.appendingPathComponent(".jarvis/telemetry/boot_event.jsonl")
    try "{\"event\":\"test_boot\"}\n".write(to: dummyTelemetry, atomically: true, encoding: .utf8)

    // Satisfy CapabilityRegistry and IntentParser/DisplayCommandExecutor tests
    let capabilitiesJSON = """
    {
      "displays": [
        {
          "id": "left-monitor",
          "displayName": "Left Monitor",
          "aliases": ["left monitor", "left screen", "left"],
          "type": "monitor",
          "transport": "homekit",
          "address": null,
          "capabilities": ["telemetry", "camera", "hud", "dashboard"],
          "room": "lab"
        },
        {
          "id": "lab-tv",
          "displayName": "Lab TV",
          "aliases": ["lab tv", "primary tv", "main tv"],
          "type": "tv",
          "transport": "airplay",
          "address": null,
          "capabilities": ["telemetry", "camera"],
          "room": "lab"
        },
        {
          "id": "workshop-projector",
          "displayName": "Workshop Projector",
          "aliases": ["workshop projector", "projector"],
          "type": "projector",
          "transport": "hdmi-cec",
          "address": null,
          "capabilities": ["telemetry"],
          "room": "workshop"
        }
      ],
      "accessories": [
        {
          "id": "kitchen-lights",
          "displayName": "Kitchen Lights",
          "aliases": ["kitchen lights", "kitchen"],
          "homeKitAccessoryID": "kitchen-lights-HK",
          "characteristics": ["on", "brightness"],
          "room": "kitchen"
        },
        {
          "id": "front-door-lock",
          "displayName": "Front Door Lock",
          "aliases": ["front door", "front door lock"],
          "homeKitAccessoryID": "front-door-HK",
          "characteristics": ["lock-target-state"],
          "room": "entry"
        },
        {
          "id": "lab-thermostat",
          "displayName": "Lab Thermostat",
          "aliases": ["lab thermostat", "thermostat"],
          "homeKitAccessoryID": "lab-thermo-HK",
          "characteristics": ["current-temperature", "target-temperature"],
          "room": "lab"
        }
      ]
    }
    """
    try capabilitiesJSON.write(to: root.appendingPathComponent(".jarvis/capabilities.json"),
                               atomically: true, encoding: .utf8)

    let skillNames = [
        "stigmergic-regulation-skill",
        "recursive-language-model-repl-skill",
        "memory-tier-memify-skill",
        "zero-shot-voice-synthesis-skill",
        "meta-harness-convex-observability-skill"
    ]

    for skillName in skillNames {
        let source = repoRoot.appendingPathComponent("agent-skills/skills/\(skillName)/SKILL.md")
        let destinationDir = root.appendingPathComponent("agent-skills/skills/\(skillName)", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destinationDir.appendingPathComponent("SKILL.md"))
    }

    try FileManager.default.copyItem(
        at: repoRoot.appendingPathComponent("Jarvis/Sources/JarvisCore/RLM/rlm_repl.py"),
        to: root.appendingPathComponent("Jarvis/Sources/JarvisCore/RLM/rlm_repl.py")
    )
    try FileManager.default.copyItem(
        at: repoRoot.appendingPathComponent("voice-samples/_originals_dirty/audio-1.mp3"),
        to: root.appendingPathComponent("audio-1.mp3")
    )

    let genesisContent = """
    {
      "status": "RATIFIED",
      "operator": {
        "callsign": "TestOperator",
        "role": "test"
      }
    }
    """
    try! genesisContent.write(to: root.appendingPathComponent(".jarvis/soul_anchor/genesis.json"), atomically: true, encoding: .utf8)

    return WorkspacePaths(root: root, storageRoot: root.appendingPathComponent(".jarvis", isDirectory: true))
}
