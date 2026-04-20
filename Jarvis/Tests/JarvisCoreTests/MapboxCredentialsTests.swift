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

    func testSecretTokenRejectsResponderPrincipal() {
        let creds = MapboxCredentials(
            publicToken: "pk.abcdefghijklmnopqrstuvwxyz",
            secretToken: "sk.abcdefghijklmnopqrstuvwxyz"
        )
        let responder = Principal.responder(role: .emt)
        XCTAssertNil(creds.secretToken(for: responder), "responder tier must never see secret token")
        XCTAssertTrue(creds.hasSecretToken, "hasSecretToken must not gate on principal")
    }

    func testHasSecretTokenFalseWhenAbsent() {
        let creds = MapboxCredentials(publicToken: "pk.abcdefghijklmnopqrstuvwxyz", secretToken: nil)
        XCTAssertFalse(creds.hasSecretToken)
        XCTAssertNil(creds.secretToken(for: .operatorTier))
    }

    func testLoaderFallsBackToFileWhenNoEnv() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mapbox-file-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent(".jarvis/secrets"),
            withIntermediateDirectories: true
        )
        let contents = """
        MAPBOX_PUBLIC_TOKEN=pk.FILE_public_xxxxxxxxxxxxxxxxxxxx
        MAPBOX_SECRET_TOKEN=sk.FILE_secret_xxxxxxxxxxxxxxxxxxxx
        """
        try contents.write(
            to: tmp.appendingPathComponent(".jarvis/secrets/mapbox.env"),
            atomically: true, encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: tmp) }

        let creds = MapboxCredentialLoader.load(repoRoot: tmp, environment: [:])
        XCTAssertEqual(creds.publicToken, "pk.FILE_public_xxxxxxxxxxxxxxxxxxxx")
        XCTAssertEqual(creds.secretToken(for: .operatorTier), "sk.FILE_secret_xxxxxxxxxxxxxxxxxxxx")
    }

    func testValidateTokenLengthBoundary() {
        // Threshold is `prefix.count + 20` — strictly greater than.
        // "pk." (3) + 20 = 23 → need length >= 24.
        let shortAt23 = "pk." + String(repeating: "a", count: 20)      // len 23 → rejected
        let longAt24  = "pk." + String(repeating: "a", count: 21)      // len 24 → accepted
        XCTAssertNil(MapboxCredentialLoader.validateToken(shortAt23, prefix: "pk."))
        XCTAssertEqual(MapboxCredentialLoader.validateToken(longAt24, prefix: "pk."), longAt24)
        XCTAssertNil(MapboxCredentialLoader.validateToken(nil, prefix: "pk."))
    }

    func testDotenvParserSkipsMalformedAndMissing() throws {
        let missingURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mapbox-missing-\(UUID().uuidString).env")
        XCTAssertNil(MapboxCredentialLoader.parseDotenv(at: missingURL), "missing file returns nil")

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mapbox-dotenv-skip-\(UUID().uuidString).env")
        let contents = """

        # comment line
        THIS_HAS_NO_EQUALS_SIGN
        VALID_KEY=valid_value
        """
        try contents.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let parsed = try XCTUnwrap(MapboxCredentialLoader.parseDotenv(at: tmp))
        XCTAssertEqual(parsed["VALID_KEY"], "valid_value")
        XCTAssertNil(parsed["THIS_HAS_NO_EQUALS_SIGN"])
        XCTAssertEqual(parsed.count, 1, "comments, blanks, and no-= lines must all be skipped")
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

    // MARK: - Additional coverage

    func testLoaderUsesEnvironmentWithoutTouchingFileWhenBothPresent() throws {
        // If env supplies both tokens, the dotenv file must not be consulted at all.
        // Point repoRoot at a real path that contains a DELIBERATELY-BROKEN file —
        // if the loader reads it, it would end up with the file's values.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mapbox-envonly-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent(".jarvis/secrets"),
            withIntermediateDirectories: true
        )
        let poisoned = """
        MAPBOX_PUBLIC_TOKEN=pk.FILE_WINS_IF_READ_xxxxxxxxxxxxx
        MAPBOX_SECRET_TOKEN=sk.FILE_WINS_IF_READ_xxxxxxxxxxxxx
        """
        try poisoned.write(
            to: tmp.appendingPathComponent(".jarvis/secrets/mapbox.env"),
            atomically: true, encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: tmp) }

        let creds = MapboxCredentialLoader.load(
            repoRoot: tmp,
            environment: [
                "MAPBOX_PUBLIC_TOKEN": "pk.ENV_public_xxxxxxxxxxxxxxxxxxxx",
                "MAPBOX_SECRET_TOKEN": "sk.ENV_secret_xxxxxxxxxxxxxxxxxxxx"
            ]
        )
        XCTAssertEqual(creds.publicToken, "pk.ENV_public_xxxxxxxxxxxxxxxxxxxx")
        XCTAssertEqual(creds.secretToken(for: .operatorTier), "sk.ENV_secret_xxxxxxxxxxxxxxxxxxxx")
    }

    func testValidateTokenRejectsCorrectLengthButWrongPrefix() {
        // Long enough, right shape — but prefix doesn't match what the caller asked for.
        let sk = "sk." + String(repeating: "a", count: 25)
        XCTAssertNil(MapboxCredentialLoader.validateToken(sk, prefix: "pk."),
                     "secret-prefixed token must not be accepted as a public token")
        let pk = "pk." + String(repeating: "a", count: 25)
        XCTAssertNil(MapboxCredentialLoader.validateToken(pk, prefix: "sk."),
                     "public-prefixed token must not be accepted as a secret token")
    }

    func testHasSecretTokenTracksPresenceNotLength() {
        // Direct init accepts whatever the caller hands in — hasSecretToken
        // is a simple presence check; legality is the loader's job.
        let credsEmptyString = MapboxCredentials(publicToken: nil, secretToken: "")
        XCTAssertTrue(credsEmptyString.hasSecretToken,
                      "hasSecretToken must reflect non-nil even if empty; caller must validate")
        XCTAssertEqual(credsEmptyString.secretToken(for: .operatorTier), "")
    }

    func testSecretTokenRejectsSpecificCompanionMember() {
        let creds = MapboxCredentials(
            publicToken: "pk.abcdefghijklmnopqrstuvwxyz",
            secretToken: "sk.abcdefghijklmnopqrstuvwxyz"
        )
        let melissa = Principal.companion(memberID: "melissa")
        let wife = Principal.companion(memberID: "wife")
        XCTAssertNil(creds.secretToken(for: melissa))
        XCTAssertNil(creds.secretToken(for: wife),
                     "no companion memberID is ever authorized to see the secret token")
    }

    func testParseDotenvWithEmptyFileReturnsEmptyDict() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mapbox-empty-\(UUID().uuidString).env")
        try Data().write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let parsed = try XCTUnwrap(MapboxCredentialLoader.parseDotenv(at: tmp))
        XCTAssertTrue(parsed.isEmpty)
    }

    func testParseDotenvStripsOnlyMatchedSurroundingQuotes() throws {
        // An unmatched leading quote must be preserved verbatim — we only strip
        // true "…"-enclosed values.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mapbox-quoted-\(UUID().uuidString).env")
        let contents = """
        LEADING_ONLY="stayquoted
        TRAILING_ONLY=stayquoted"
        MATCHED="stripped"
        """
        try contents.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let parsed = try XCTUnwrap(MapboxCredentialLoader.parseDotenv(at: tmp))
        XCTAssertEqual(parsed["LEADING_ONLY"], "\"stayquoted")
        XCTAssertEqual(parsed["TRAILING_ONLY"], "stayquoted\"")
        XCTAssertEqual(parsed["MATCHED"], "stripped")
    }

    func testLoaderMergesEnvPublicAndFileSecret() throws {
        // Independent precedence per key: env wins for public, file fills in secret.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mapbox-mix-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent(".jarvis/secrets"),
            withIntermediateDirectories: true
        )
        try """
        MAPBOX_PUBLIC_TOKEN=pk.FILE_public_should_be_shadowed_xx
        MAPBOX_SECRET_TOKEN=sk.FILE_secret_wins_xxxxxxxxxxxxxxxxx
        """.write(
            to: tmp.appendingPathComponent(".jarvis/secrets/mapbox.env"),
            atomically: true, encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: tmp) }

        let creds = MapboxCredentialLoader.load(
            repoRoot: tmp,
            environment: ["MAPBOX_PUBLIC_TOKEN": "pk.ENV_public_wins_xxxxxxxxxxxxxxxxxxxx"]
        )
        XCTAssertEqual(creds.publicToken, "pk.ENV_public_wins_xxxxxxxxxxxxxxxxxxxx")
        XCTAssertEqual(creds.secretToken(for: .operatorTier), "sk.FILE_secret_wins_xxxxxxxxxxxxxxxxx")
    }
}
