import Foundation

/// SPEC-009 Mapbox credential loader.
///
/// Two tokens exist:
///
///   - **Public** (`pk.*`) — scoped styles + tilesets, safe to embed in
///     any client render. Exposed to any tier so Companion OS maps work
///     on family devices.
///   - **Secret** (`sk.*`) — full-account API access. Only operator-tier
///     code paths may read it; calling `secretToken(for:)` with any
///     non-operator principal fails closed.
///
/// Storage order of precedence (first match wins):
///   1. Environment variables `MAPBOX_PUBLIC_TOKEN` / `MAPBOX_SECRET_TOKEN`.
///   2. File at `.jarvis/secrets/mapbox.env` (dotenv, gitignored).
public struct MapboxCredentials: Sendable {
    public let publicToken: String?
    private let secretTokenValue: String?

    public init(publicToken: String?, secretToken: String?) {
        self.publicToken = publicToken
        self.secretTokenValue = secretToken
    }

    /// Secret token, guarded by principal tier. Returns nil for any
    /// non-operator principal.
    public func secretToken(for principal: Principal) -> String? {
        switch principal {
        case .operatorTier: return secretTokenValue
        case .companion, .guestTier, .responder: return nil
        }
    }

    public var hasSecretToken: Bool { secretTokenValue != nil }
}

public enum MapboxCredentialLoader {
    public static func load(
        repoRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> MapboxCredentials {
        var publicTok = environment["MAPBOX_PUBLIC_TOKEN"]
        var secretTok = environment["MAPBOX_SECRET_TOKEN"]

        if publicTok == nil || secretTok == nil {
            let fileURL = repoRoot.appendingPathComponent(".jarvis/secrets/mapbox.env")
            if let parsed = parseDotenv(at: fileURL) {
                if publicTok == nil { publicTok = parsed["MAPBOX_PUBLIC_TOKEN"] }
                if secretTok == nil { secretTok = parsed["MAPBOX_SECRET_TOKEN"] }
            }
        }

        return MapboxCredentials(
            publicToken: validateToken(publicTok, prefix: "pk."),
            secretToken: validateToken(secretTok, prefix: "sk.")
        )
    }

    static func parseDotenv(at url: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }
        var result: [String: String] = [:]
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }

    /// Validate prefix and shape. Rejects malformed tokens rather than
    /// vending them — a malformed token on a map render would fail
    /// silently at Mapbox, far from the cause.
    static func validateToken(_ token: String?, prefix: String) -> String? {
        guard let token, token.hasPrefix(prefix), token.count > prefix.count + 20 else { return nil }
        return token
    }
}
