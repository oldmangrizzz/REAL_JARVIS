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
}
