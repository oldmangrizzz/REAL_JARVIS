import Foundation
import CryptoKit
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
    // Optional voice-sample fixture: only copy if the source exists. The
    // file is not referenced by any test, so a missing source must not fail
    // workspace setup (voice-samples/_originals_dirty/ is not tracked).
    let audioSource = repoRoot.appendingPathComponent("voice-samples/_originals_dirty/audio-1.mp3")
    if FileManager.default.fileExists(atPath: audioSource.path) {
        try FileManager.default.copyItem(
            at: audioSource,
            to: root.appendingPathComponent("audio-1.mp3")
        )
    }

    let mcuDir = root.appendingPathComponent("mcuhist", isDirectory: true)
    try FileManager.default.createDirectory(at: mcuDir, withIntermediateDirectories: true)
    let principles = "# Principles\nTest canon."
    let verification = "# Verification Protocol\nTest verification."
    let manifest = "# MCU Manifest\nTest manifest."
    let realignment = "# Realignment 1218\nTest realignment."
    try principles.write(to: root.appendingPathComponent("PRINCIPLES.md"), atomically: true, encoding: .utf8)
    try verification.write(to: root.appendingPathComponent("VERIFICATION_PROTOCOL.md"), atomically: true, encoding: .utf8)
    try manifest.write(to: mcuDir.appendingPathComponent("MANIFEST.md"), atomically: true, encoding: .utf8)
    try realignment.write(to: mcuDir.appendingPathComponent("REALIGNMENT_1218.md"), atomically: true, encoding: .utf8)
    for (name, content) in [
        ("1.md", "I am JARVIS. Test chapter 1."),
        ("2.md", "I am JARVIS. Test chapter 2."),
        ("3.md", "I am JARVIS. Test chapter 3."),
        ("4.md", "I am JARVIS. Test chapter 4."),
        ("5.md", "I am JARVIS. Test chapter 5.")
    ] {
        try content.write(to: mcuDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    var bioHasher = SHA256()
    for name in ["1.md", "2.md", "3.md", "4.md", "5.md"] {
        bioHasher.update(data: try Data(contentsOf: mcuDir.appendingPathComponent(name)))
    }

    let p256Priv = P256.Signing.PrivateKey()
    let edPriv = Curve25519.Signing.PrivateKey()
    let publicKeys = SoulAnchorPublicKeys(
        p256PublicKeyHex: p256Priv.publicKey.derRepresentation.map { String(format: "%02x", $0) }.joined(),
        ed25519PublicKeyHex: edPriv.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()
    )
    let bindings = SoulAnchorBindings(
        hardwareIdHash: "test-hardware",
        biographicalMassHash: bioHasher.finalize().map { String(format: "%02x", $0) }.joined(),
        realignmentHash: sha256Hex(realignment),
        principlesHash: sha256Hex(principles),
        verificationHash: sha256Hex(verification),
        mcuhistManifestHash: sha256Hex(manifest),
        genesisTimestamp: "2026-04-27T00:00:00Z",
        operatorOfRecord: "TestOperator",
        schemaVersion: "1.1.0-test"
    )
    struct SignedPayload: Codable {
        let bindings: SoulAnchorBindings
        let publicKeys: SoulAnchorPublicKeys
    }
    let payload = SignedPayload(bindings: bindings, publicKeys: publicKeys)
    let payloadEncoder = JSONEncoder()
    payloadEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let canonical = try payloadEncoder.encode(payload)
    let p256Sig = try p256Priv.signature(for: canonical).derRepresentation.map { String(format: "%02x", $0) }.joined()
    let edSig = try edPriv.signature(for: canonical).map { String(format: "%02x", $0) }.joined()
    let genesis = GenesisRecord(
        publicKeys: publicKeys,
        bindings: bindings,
        signatures: SoulAnchorSignatures(p256: p256Sig, ed25519: edSig)
    )
    let genesisData = try JSONEncoder().encode(genesis)
    try genesisData.write(to: root.appendingPathComponent(".jarvis/soul_anchor/genesis.json"), options: .atomic)

    return WorkspacePaths(root: root, storageRoot: root.appendingPathComponent(".jarvis", isDirectory: true))
}
