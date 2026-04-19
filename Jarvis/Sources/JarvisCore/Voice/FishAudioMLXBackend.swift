import Foundation

/// The original fish-audio MLX backend. Builds the bundled
/// mlx-audio-swift-tts executable and shells out to it for each render.
/// Heavyweight on this hardware (8 GB Mac swaps; needs >= 16 GB really)
/// but kept as a local fallback when the HTTP backend is unreachable.
public final class FishAudioMLXBackend: TTSBackend {
    public let identifier = "mlx-community/fish-audio-s2-pro-8bit"
    public let selectedVoiceLabel = "mlx-fish-audio-s2-pro-clone"
    public let sampleRate = 44_100

    private let paths: WorkspacePaths
    private let runner: AudioCommandRunning
    private let toolName = "mlx-audio-swift-tts"

    public init(paths: WorkspacePaths, runner: AudioCommandRunning = ProcessAudioCommandRunner()) {
        self.paths = paths
        self.runner = runner
    }

    public func synthesize(
        text: String,
        referenceAudioURL: URL,
        referenceTranscript: String,
        parameters: TTSRenderParameters,
        outputURL: URL
    ) throws {
        try ensureMLXPackageAvailable()
        try buildExecutable(named: toolName)
        let tool = try executableURL(named: toolName)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var arguments: [String] = [
            "--model", identifier,
            "--text", text,
            "--output", outputURL.path,
            "--ref_audio", referenceAudioURL.path,
            "--ref_text", referenceTranscript,
            "--temperature", String(parameters.temperature),
            "--top_p", String(parameters.topP)
        ]
        if let maxTokens = parameters.maxNewTokens {
            arguments.append(contentsOf: ["--max_new_tokens", String(maxTokens)])
        }

        _ = try runner.run(tool, arguments: arguments, currentDirectory: paths.mlxAudioPackageDirectory)
    }

    private func ensureMLXPackageAvailable() throws {
        let packageFile = paths.mlxAudioPackageDirectory.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: packageFile.path) else {
            throw JarvisError.processFailure("MLX Audio Swift package is missing at \(paths.mlxAudioPackageDirectory.path).")
        }
    }

    private func buildExecutable(named name: String) throws {
        if executableURLIfBuilt(named: name) != nil {
            try ensureMetalResourcesAvailable(forExecutableNamed: name)
            return
        }
        let env = URL(fileURLWithPath: "/usr/bin/env")
        _ = try runner.run(
            env,
            arguments: ["swift", "build", "-c", "release", "--product", name],
            currentDirectory: paths.mlxAudioPackageDirectory
        )
        try ensureMetalResourcesAvailable(forExecutableNamed: name)
    }

    private func executableURL(named name: String) throws -> URL {
        if let built = executableURLIfBuilt(named: name) {
            return built
        }
        throw JarvisError.processFailure("MLX executable '\(name)' was not found after build.")
    }

    private func executableURLIfBuilt(named name: String) -> URL? {
        let buildRoot = paths.mlxAudioPackageDirectory.appendingPathComponent(".build", isDirectory: true)
        guard FileManager.default.fileExists(atPath: buildRoot.path) else { return nil }
        let fileManager = FileManager.default
        let enumerator = FileManager.default.enumerator(at: buildRoot, includingPropertiesForKeys: [.isRegularFileKey])
        while let item = enumerator?.nextObject() as? URL {
            guard item.lastPathComponent == name else { continue }
            guard item.path.contains("/release/") else { continue }
            guard !item.path.contains(".dSYM/") else { continue }
            guard fileManager.isExecutableFile(atPath: item.path) else { continue }
            return item
        }
        return nil
    }

    private func ensureMetalResourcesAvailable(forExecutableNamed name: String) throws {
        guard let executableURL = executableURLIfBuilt(named: name) else { return }
        let executableDirectory = executableURL.deletingLastPathComponent()
        let expectedBundleURL = executableDirectory.appendingPathComponent("mlx-swift_Cmlx.bundle", isDirectory: true)
        let expectedMetallibURL = expectedBundleURL.appendingPathComponent("default.metallib")
        if FileManager.default.fileExists(atPath: expectedMetallibURL.path) {
            return
        }
        guard let sourceBundleURL = locateMetalBundle() else {
            throw JarvisError.processFailure("MLX metal resources are unavailable for \(name).")
        }
        if FileManager.default.fileExists(atPath: expectedBundleURL.path) {
            try FileManager.default.removeItem(at: expectedBundleURL)
        }
        try FileManager.default.copyItem(at: sourceBundleURL, to: expectedBundleURL)
    }

    private func locateMetalBundle() -> URL? {
        let fileManager = FileManager.default
        let searchRoots = [
            paths.mlxAudioPackageDirectory.appendingPathComponent(".build", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Developer", isDirectory: true)
                .appendingPathComponent("Xcode", isDirectory: true)
                .appendingPathComponent("DerivedData", isDirectory: true)
        ]
        for root in searchRoots where fileManager.fileExists(atPath: root.path) {
            let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])
            while let item = enumerator?.nextObject() as? URL {
                guard item.lastPathComponent == "mlx-swift_Cmlx.bundle" else { continue }
                let metallibURL = item.appendingPathComponent("default.metallib")
                if fileManager.fileExists(atPath: metallibURL.path) {
                    return item
                }
            }
        }
        return nil
    }
}
