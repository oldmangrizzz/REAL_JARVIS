import Foundation

public final class HDMICECBridge {
    private let cecClientPath = "/usr/local/bin/cec-client"

    public func switchInput(outputPort: Int) throws -> ExecutionResult {
        guard FileManager.default.fileExists(atPath: cecClientPath) else {
            throw JarvisError.processFailure("cec-client not found. Install: brew install cec-client")
        }
        // echo "tx 1f:82:PORT" | cec-client -s
        // 1f = recorder address, 82 = active source command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "echo 'tx 1f:82:\(String(outputPort, radix: 16).uppercased())' | \(cecClientPath) -s -p 1"]
        try process.run()
        process.waitUntilExit()

        return ExecutionResult(
            success: process.terminationStatus == 0,
            spokenText: process.terminationStatus == 0 ? "Switched HDMI input." : "HDMI-CEC switch failed.",
            details: ["port": String(outputPort)]
        )
    }
}
