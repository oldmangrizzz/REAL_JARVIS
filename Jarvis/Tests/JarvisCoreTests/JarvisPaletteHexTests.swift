import XCTest
@testable import JarvisCore

/// SPEC-009 brand-palette bridge. Hex tokens must resolve to the canonical
/// sRGB components so every platform target renders the same tier colour.
/// If these drift, Unity / Mac / Mobile surfaces start disagreeing about
/// what Grizz OS looks like and the evidence corpus can't tell you why.
final class JarvisPaletteHexTests: XCTestCase {

    func testGrizzEmeraldResolvesToExpectedSRGB() throws {
        let rgb = try XCTUnwrap(JarvisPaletteHex(hex: "#00A878"))
        XCTAssertEqual(rgb.red,   0.0,            accuracy: 0.001)
        XCTAssertEqual(rgb.green, 168.0 / 255.0,  accuracy: 0.001)
        XCTAssertEqual(rgb.blue,  120.0 / 255.0,  accuracy: 0.001)
    }

    func testCompanionTealResolvesToExpectedSRGB() throws {
        let rgb = try XCTUnwrap(JarvisPaletteHex(hex: "#00B8C4"))
        XCTAssertEqual(rgb.red,   0.0,            accuracy: 0.001)
        XCTAssertEqual(rgb.green, 184.0 / 255.0,  accuracy: 0.001)
        XCTAssertEqual(rgb.blue,  196.0 / 255.0,  accuracy: 0.001)
    }

    func testResponderDutyBlueResolvesToExpectedSRGB() throws {
        let rgb = try XCTUnwrap(JarvisPaletteHex(hex: "#0B5FFF"))
        XCTAssertEqual(rgb.red,   11.0 / 255.0,   accuracy: 0.001)
        XCTAssertEqual(rgb.green, 95.0 / 255.0,   accuracy: 0.001)
        XCTAssertEqual(rgb.blue,  1.0,            accuracy: 0.001)
    }

    func testHexParserAcceptsNoLeadingHashAndIsCaseInsensitive() throws {
        let a = try XCTUnwrap(JarvisPaletteHex(hex: "c8102e"))
        let b = try XCTUnwrap(JarvisPaletteHex(hex: "#C8102E"))
        XCTAssertEqual(a.red, b.red, accuracy: 0.0001)
        XCTAssertEqual(a.green, b.green, accuracy: 0.0001)
        XCTAssertEqual(a.blue, b.blue, accuracy: 0.0001)
    }

    func testHexParserRejectsMalformed() {
        XCTAssertNil(JarvisPaletteHex(hex: ""))
        XCTAssertNil(JarvisPaletteHex(hex: "#12345"))
        XCTAssertNil(JarvisPaletteHex(hex: "#1234567"))
        XCTAssertNil(JarvisPaletteHex(hex: "#GGGGGG"))
    }

    func testEveryCanonicalPaletteEntryIsParseable() {
        // CANON: every declared palette on JarvisBrandPalette must round-trip
        // through the hex parser. A future edit that introduces a malformed
        // token (e.g. typo'd accent hex) fails loudly in CI.
        let palettes: [JarvisBrandPalette] = [.grizzOS, .companionOS, .companionGuest, .responderOS]
        for p in palettes {
            for hex in [p.canvasBlackHex, p.chromeSilverHex, p.alertCrimsonHex, p.accentHex, p.accentGlowHex] {
                XCTAssertNotNil(JarvisPaletteHex(hex: hex), "Unparseable palette hex: \(hex)")
            }
        }
    }

    // MARK: - Parser robustness

    func testHexParserTrimsWhitespace() throws {
        let a = try XCTUnwrap(JarvisPaletteHex(hex: "   #C8102E   "))
        let b = try XCTUnwrap(JarvisPaletteHex(hex: "\n#C8102E\t"))
        XCTAssertEqual(a.red, b.red, accuracy: 1e-9)
    }

    func testHexParserRejectsShorthandAndExtraChars() {
        // 3-digit shorthand is NOT supported (parser requires exactly 6 hex digits).
        XCTAssertNil(JarvisPaletteHex(hex: "#FFF"))
        XCTAssertNil(JarvisPaletteHex(hex: "FFF"))
        // Trailing space inside after trim would leave extra char — use explicit bad case.
        XCTAssertNil(JarvisPaletteHex(hex: "#C8102EZZ"))
        // Non-hex sentinel in middle.
        XCTAssertNil(JarvisPaletteHex(hex: "#C81G2E"))
    }

    func testBlackAndWhiteBoundarySRGBComponents() throws {
        let black = try XCTUnwrap(JarvisPaletteHex(hex: "#000000"))
        XCTAssertEqual(black.red, 0, accuracy: 1e-9)
        XCTAssertEqual(black.green, 0, accuracy: 1e-9)
        XCTAssertEqual(black.blue, 0, accuracy: 1e-9)

        let white = try XCTUnwrap(JarvisPaletteHex(hex: "#FFFFFF"))
        XCTAssertEqual(white.red, 1, accuracy: 1e-9)
        XCTAssertEqual(white.green, 1, accuracy: 1e-9)
        XCTAssertEqual(white.blue, 1, accuracy: 1e-9)
    }

    // MARK: - Palette canon + principal routing

    func testTierLabelsAreCanon() {
        XCTAssertEqual(JarvisBrandPalette.grizzOS.tierLabel, "powered by Grizz OS")
        XCTAssertEqual(JarvisBrandPalette.companionOS.tierLabel, "powered by Companion OS")
        XCTAssertEqual(JarvisBrandPalette.companionGuest.tierLabel, "powered by Companion OS (guest)")
        XCTAssertEqual(JarvisBrandPalette.responderOS.tierLabel, "powered by Responder OS")
    }

    func testPaletteForPrincipalRoutesByTier() {
        XCTAssertEqual(JarvisBrandPalette.palette(for: .operatorTier), .grizzOS)
        XCTAssertEqual(JarvisBrandPalette.palette(for: .companion(memberID: "kid")), .companionOS)
        XCTAssertEqual(JarvisBrandPalette.palette(for: .guestTier), .companionGuest)
        XCTAssertEqual(JarvisBrandPalette.palette(for: .responder(role: .emt)), .responderOS)
        XCTAssertEqual(JarvisBrandPalette.palette(for: .responder(role: .emr)), .responderOS)
        XCTAssertEqual(JarvisBrandPalette.palette(for: .responder(role: .aemt)), .responderOS)
        XCTAssertEqual(JarvisBrandPalette.palette(for: .responder(role: .emtp)), .responderOS)
    }

    func testSharedCanonStaysConsistentAcrossTiers() {
        // Alert crimson must be invariant across tiers — "serious" reads the same house-wide.
        let alert = JarvisBrandPalette.grizzOS.alertCrimsonHex
        XCTAssertEqual(JarvisBrandPalette.companionOS.alertCrimsonHex, alert)
        XCTAssertEqual(JarvisBrandPalette.companionGuest.alertCrimsonHex, alert)
        XCTAssertEqual(JarvisBrandPalette.responderOS.alertCrimsonHex, alert)

        // Canvas is black for operator+companion (shared chassis), darker for responder.
        XCTAssertEqual(JarvisBrandPalette.grizzOS.canvasBlackHex, JarvisBrandPalette.companionOS.canvasBlackHex)
        XCTAssertEqual(JarvisBrandPalette.grizzOS.canvasBlackHex, JarvisBrandPalette.companionGuest.canvasBlackHex)
        XCTAssertNotEqual(JarvisBrandPalette.grizzOS.canvasBlackHex, JarvisBrandPalette.responderOS.canvasBlackHex)

        // Guest chrome is dimmed vs operator/companion.
        XCTAssertNotEqual(JarvisBrandPalette.grizzOS.chromeSilverHex, JarvisBrandPalette.companionGuest.chromeSilverHex)
    }
}

