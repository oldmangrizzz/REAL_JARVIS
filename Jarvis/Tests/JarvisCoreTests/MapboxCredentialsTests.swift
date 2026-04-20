import XCTest
@testable import JarvisCore

/// SPEC-009 Mapbox credential discipline:
///   - Public token available to any tier.
///   - Secret token ONLY reachable from operator tier.
///   - Malformed tokens are rejected at load, not passed through.
final class MapboxCredentialsTests: XCTestCase {

    func testSecretTokenIsOperatorOnly() {
        let creds = MapboxCredentials(
            publicToken: "pk.abcdefghijklmnopqrstuvwxyz",
            secretToken: "sk.abcdefghijklmnopqrstuvwxyz"
        )
        XCTAssertNotNil(creds.secretToken(for: .operatorTier))
        XCTAssertNil(creds.secretToken(for: .companion(memberID: "wife")))
        XCTAssertNil(creds.secretToken(for: .guestTier))
    }

    func testLoaderPrefersEnvironmentOverFile() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mapbox-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent(".jarvis/secrets"),
            withIntermediateDirectories: true
        )
        let fileContents = """
        MAPBOX_PUBLIC_TOKEN=pk.FILE_public_xxxxxxxxxxxxxxxxxxxx
        MAPBOX_SECRET_TOKEN=sk.FILE_secret_xxxxxxxxxxxxxxxxxxxx
        """
        try fileContents.write(
            to: tmp.appendingPathComponent(".jarvis/secrets/mapbox.env"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: tmp) }

        let creds = MapboxCredentialLoader.load(
            repoRoot: tmp,
            environment: [
                "MAPBOX_PUBLIC_TOKEN": "pk.ENV_public_xxxxxxxxxxxxxxxxxxxx"
                // secret NOT in env — should fall back to file.
            ]
        )
        XCTAssertEqual(creds.publicToken, "pk.ENV_public_xxxxxxxxxxxxxxxxxxxx")
        XCTAssertEqual(creds.secretToken(for: .operatorTier), "sk.FILE_secret_xxxxxxxxxxxxxxxxxxxx")
    }

    func testLoaderRejectsMalformedTokens() {
        let creds = MapboxCredentialLoader.load(
            repoRoot: URL(fileURLWithPath: "/nonexistent-repo-\(UUID().uuidString)"),
            environment: [
                "MAPBOX_PUBLIC_TOKEN": "not-a-real-token",
                "MAPBOX_SECRET_TOKEN": "pk.wrong-prefix-xxxxxxxxxxxxxxxxx"
            ]
        )
        XCTAssertNil(creds.publicToken, "non-pk. prefix must be rejected")
        XCTAssertNil(creds.secretToken(for: .operatorTier), "pk.-prefixed secret must be rejected")
    }

    func testLoaderReturnsNilWhenNoSourcePresent() {
        let creds = MapboxCredentialLoader.load(
            repoRoot: URL(fileURLWithPath: "/nonexistent-repo-\(UUID().uuidString)"),
            environment: [:]
        )
        XCTAssertNil(creds.publicToken)
        XCTAssertNil(creds.secretToken(for: .operatorTier))
        XCTAssertFalse(creds.hasSecretToken)
    }

    func testDotenvParserHandlesCommentsAndQuotes() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mapbox-dotenv-\(UUID().uuidString).env")
        let contents = """
        # this is a comment
        MAPBOX_PUBLIC_TOKEN="pk.quoted_value_xxxxxxxxxxxxxxxxx"
          MAPBOX_SECRET_TOKEN = sk.unquoted_value_xxxxxxxxxxxxxxxxx
        """
        try contents.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let parsed = try XCTUnwrap(MapboxCredentialLoader.parseDotenv(at: tmp))
        XCTAssertEqual(parsed["MAPBOX_PUBLIC_TOKEN"], "pk.quoted_value_xxxxxxxxxxxxxxxxx")
        XCTAssertEqual(parsed["MAPBOX_SECRET_TOKEN"], "sk.unquoted_value_xxxxxxxxxxxxxxxxx")
    }
}
