import XCTest
@testable import JarvisCore

final class WorkspacePathsTests: XCTestCase {
    private var tempRoot: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("wp-tests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root = tempRoot, fm.fileExists(atPath: root.path) {
            try? fm.removeItem(at: root)
        }
    }

    // MARK: - Init derives all paths from root

    func testInitDerivesCanonicalLayoutUnderRoot() {
        let p = WorkspacePaths(root: tempRoot)
        XCTAssertEqual(p.agentSkillsRoot, tempRoot.appendingPathComponent("agent-skills", isDirectory: true))
        XCTAssertEqual(p.skillDirectory, p.agentSkillsRoot.appendingPathComponent("skills", isDirectory: true))
        XCTAssertEqual(p.archonDirectory.lastPathComponent, "Archon")
        XCTAssertEqual(p.convexDirectory.lastPathComponent, "convex")
        XCTAssertEqual(p.vendorDirectory.lastPathComponent, "vendor")
        XCTAssertEqual(p.mlxAudioPackageDirectory.lastPathComponent, "mlx-audio-swift")
        XCTAssertEqual(p.voiceSamplesDirectory.lastPathComponent, "voice-samples")
        XCTAssertEqual(p.rlmScriptURL.lastPathComponent, "rlm_repl.py")
    }

    func testDefaultStorageRootIsDotJarvisUnderRoot() {
        let p = WorkspacePaths(root: tempRoot)
        XCTAssertEqual(p.storageRoot, tempRoot.appendingPathComponent(".jarvis", isDirectory: true))
        XCTAssertEqual(p.storageDirectory.lastPathComponent, "storage")
        XCTAssertEqual(p.telemetryDirectory.lastPathComponent, "telemetry")
        XCTAssertEqual(p.traceDirectory.lastPathComponent, "traces")
        XCTAssertEqual(p.interfaceLogURL.lastPathComponent, "interface.log")
        XCTAssertEqual(p.interfacePIDURL.lastPathComponent, "interface.pid")
        XCTAssertEqual(p.capabilityConfigURL.lastPathComponent, "capabilities.json")
    }

    func testExplicitStorageRootOverridesDefault() {
        let custom = tempRoot.appendingPathComponent("custom-store", isDirectory: true)
        let p = WorkspacePaths(root: tempRoot, storageRoot: custom)
        XCTAssertEqual(p.storageRoot, custom)
        // Downstream paths chain off explicit root, not .jarvis
        XCTAssertTrue(p.storageDirectory.path.hasPrefix(custom.path))
        XCTAssertTrue(p.telemetryDirectory.path.hasPrefix(custom.path))
        XCTAssertTrue(p.controlPlaneDirectory.path.hasPrefix(custom.path))
    }

    func testControlPlaneStatusFileLeafNames() {
        let p = WorkspacePaths(root: tempRoot)
        XCTAssertEqual(p.guiIntentQueueURL.lastPathComponent, "gui-intents.json")
        XCTAssertEqual(p.nodeRegistryStatusURL.lastPathComponent, "node-registry.json")
        XCTAssertEqual(p.rustDeskRegistryURL.lastPathComponent, "rustdesk-registry.json")
        XCTAssertEqual(p.commandRegistryURL.lastPathComponent, "command-registry.json")
        XCTAssertEqual(p.regulationStatusURL.lastPathComponent, "regulation.json")
        XCTAssertEqual(p.sovereignStatusURL.lastPathComponent, "sovereign-dashboard.json")
        XCTAssertEqual(p.homebridgeConfigURL.lastPathComponent, "config.json")
        XCTAssertEqual(p.homebridgeStatusURL.lastPathComponent, "status.json")
    }

    // MARK: - resolve(path:)

    func testResolveAbsolutePathReturnsAsIs() {
        let p = WorkspacePaths(root: tempRoot)
        let abs = "/tmp/some/absolute/file.txt"
        let url = p.resolve(path: abs)
        XCTAssertEqual(url.path, abs)
    }

    func testResolveRelativePathJoinsUnderRoot() {
        let p = WorkspacePaths(root: tempRoot)
        let url = p.resolve(path: "foo/bar.txt")
        XCTAssertEqual(url, tempRoot.appendingPathComponent("foo/bar.txt"))
    }

    // MARK: - ensureSupportDirectories

    func testEnsureSupportDirectoriesCreatesAll() throws {
        let p = WorkspacePaths(root: tempRoot)
        try p.ensureSupportDirectories()
        for d in [
            p.storageRoot, p.storageDirectory, p.voiceCacheDirectory,
            p.controlPlaneDirectory, p.homebridgeDirectory,
            p.obsidianDirectory, p.obsidianPluginsDirectory,
            p.flatCockpitDirectory, p.xrSurfaceDirectory,
            p.telemetryDirectory, p.traceDirectory,
            p.archonDirectory, p.convexDirectory, p.vendorDirectory, p.voiceSamplesDirectory
        ] {
            var isDir: ObjCBool = false
            XCTAssertTrue(fm.fileExists(atPath: d.path, isDirectory: &isDir), "missing: \(d.path)")
            XCTAssertTrue(isDir.boolValue, "not directory: \(d.path)")
        }
    }

    func testEnsureSupportDirectoriesIdempotent() throws {
        let p = WorkspacePaths(root: tempRoot)
        try p.ensureSupportDirectories()
        XCTAssertNoThrow(try p.ensureSupportDirectories())
    }

    // MARK: - discover

    func testDiscoverFindsRootFromNestedSubdirectory() throws {
        // Plant workspace markers.
        try fm.createDirectory(at: tempRoot.appendingPathComponent("agent-skills"), withIntermediateDirectories: true)
        try fm.createDirectory(at: tempRoot.appendingPathComponent("jarvis.xcworkspace"), withIntermediateDirectories: true)
        let nested = tempRoot.appendingPathComponent("a/b/c", isDirectory: true)
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)

        let found = try WorkspacePaths.discover(from: nested)
        XCTAssertEqual(found.root.standardizedFileURL.resolvingSymlinksInPath().path,
                       tempRoot.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    func testDiscoverThrowsWhenNoMarkers() {
        let bare = tempRoot.appendingPathComponent("bare", isDirectory: true)
        try? fm.createDirectory(at: bare, withIntermediateDirectories: true)
        // Walk up from inside a temp dir that has no markers anywhere on path to /.
        // If the real repo sits above tempRoot we can't guarantee this throws — so check
        // by starting from a subtree clearly outside any checkout: our isolated tempRoot
        // is under NSTemporaryDirectory which has no agent-skills + jarvis.xcworkspace siblings.
        XCTAssertThrowsError(try WorkspacePaths.discover(from: bare)) { err in
            guard case JarvisError.workspaceNotFound = err else {
                return XCTFail("expected .workspaceNotFound, got \(err)")
            }
        }
    }

    // MARK: - audioSampleURLs

    func testAudioSampleURLsPrefersVoiceSamplesDirWhenPopulated() throws {
        let p = WorkspacePaths(root: tempRoot)
        try fm.createDirectory(at: p.voiceSamplesDirectory, withIntermediateDirectories: true)
        let wav = p.voiceSamplesDirectory.appendingPathComponent("b.wav")
        let mp3 = p.voiceSamplesDirectory.appendingPathComponent("a.mp3")
        let txt = p.voiceSamplesDirectory.appendingPathComponent("ignore.txt")
        try Data().write(to: wav)
        try Data().write(to: mp3)
        try Data().write(to: txt)
        // Root-level audio should be ignored when voice-samples has content.
        try Data().write(to: tempRoot.appendingPathComponent("root.mp3"))

        let urls = try p.audioSampleURLs()
        let names = urls.map { $0.lastPathComponent }
        XCTAssertEqual(names, ["a.mp3", "b.wav"])
    }

    func testAudioSampleURLsFallsBackToRootWhenSamplesMissingOrEmpty() throws {
        let p = WorkspacePaths(root: tempRoot)
        // voiceSamplesDirectory does not exist → fallback
        try Data().write(to: tempRoot.appendingPathComponent("z.wav"))
        try Data().write(to: tempRoot.appendingPathComponent("a.m4a"))
        try Data().write(to: tempRoot.appendingPathComponent("note.txt"))

        let urls = try p.audioSampleURLs()
        let names = urls.map { $0.lastPathComponent }
        XCTAssertEqual(names, ["a.m4a", "z.wav"])
    }

    func testAudioSampleURLsCaseInsensitiveExtensions() throws {
        let p = WorkspacePaths(root: tempRoot)
        try fm.createDirectory(at: p.voiceSamplesDirectory, withIntermediateDirectories: true)
        try Data().write(to: p.voiceSamplesDirectory.appendingPathComponent("SHOUT.WAV"))
        try Data().write(to: p.voiceSamplesDirectory.appendingPathComponent("soft.MP3"))

        let urls = try p.audioSampleURLs()
        XCTAssertEqual(urls.count, 2)
    }

    // MARK: - JarvisError description passthrough

    func testJarvisErrorDescriptionsSurfaceMessage() {
        XCTAssertEqual(JarvisError.workspaceNotFound("nope").description, "nope")
        XCTAssertEqual(JarvisError.invalidInput("bad").description, "bad")
        XCTAssertEqual(JarvisError.skillNotFound("missing").description, "missing")
        XCTAssertEqual(JarvisError.nativeSkillUnavailable("na").description, "na")
        XCTAssertEqual(JarvisError.processFailure("boom").description, "boom")
        XCTAssertEqual(JarvisError.serializationFailure("json").description, "json")
    }
}
