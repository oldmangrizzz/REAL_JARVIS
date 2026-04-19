import Foundation

public final class AirPlayBridge {
    private let pythonPath = "/usr/bin/python3"
    private let pyatvScriptPath: String

    public init(paths: WorkspacePaths) {
        self.pyatvScriptPath = paths.storageRoot.appendingPathComponent("scripts/airplay_switch.py").path
    }

    public func switchInput(deviceAddress: String, appName: String) async throws -> ExecutionResult {
        guard FileManager.default.fileExists(atPath: pyatvScriptPath) else {
            throw JarvisError.processFailure("AirPlay script not found at \(pyatvScriptPath)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [pyatvScriptPath, deviceAddress, appName]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw JarvisError.processFailure("AirPlay switch failed for \(deviceAddress)")
        }

        return ExecutionResult(
            success: true,
            spokenText: "Switched to \(appName) on AirPlay device.",
            details: ["address": deviceAddress, "app": appName]
        )
    }
}
