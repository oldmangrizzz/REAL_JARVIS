import XCTest
@testable import JarvisCore

/// SPEC-009 Wi-Fi scanner tier redaction. Below operator tier, raw SSID
/// and BSSID must never appear in the snapshot — location-leak material.
/// The stable BSSID hash remains so PresenceDetector can still cluster
/// rooms regardless of principal.
final class WiFiScannerRedactionTests: XCTestCase {

    // These tests run without a real WLAN interface in CI, so they exercise
    // the fail-closed path. That is exactly the 2026 contract: no interface
    // means nil SSID, nil BSSID, status = .noInterface — never a plausible
    // zero snapshot that callers might mistake for reality.

    func testNoInterfaceFailsClosedForOperator() throws {
        guard #available(macOS 12.0, *) else { throw XCTSkip("requires macOS 12+") }
        let scanner = WiFiEnvironmentScanner()
        let snap = scanner.currentSnapshot(for: .operatorTier)
        if snap.status == .noInterface {
            XCTAssertNil(snap.ssid)
            XCTAssertNil(snap.bssid)
            XCTAssertNil(snap.bssidHash)
            XCTAssertEqual(snap.rssi, 0)
            XCTAssertEqual(snap.channel, 0)
        } else {
            // Real interface present (developer laptop): operator must see raw.
            // We do NOT assert non-nil SSID because Apple may return nil for
            // disassociated interfaces; we only assert the hash/raw alignment.
            if snap.bssid != nil { XCTAssertNotNil(snap.bssidHash) }
        }
    }

    func testCompanionTierAlwaysGetsRedactedIdentifiers() throws {
        guard #available(macOS 12.0, *) else { throw XCTSkip("requires macOS 12+") }
        let scanner = WiFiEnvironmentScanner()
        let snap = scanner.currentSnapshot(for: .companion(memberID: "fam-1"))
        // Redaction invariant: SSID + raw BSSID are ALWAYS nil below operator,
        // regardless of whether the interface was readable.
        XCTAssertNil(snap.ssid, "Companion tier must never see raw SSID")
        XCTAssertNil(snap.bssid, "Companion tier must never see raw BSSID")
    }

    func testGuestTierAlwaysGetsRedactedIdentifiers() throws {
        guard #available(macOS 12.0, *) else { throw XCTSkip("requires macOS 12+") }
        let scanner = WiFiEnvironmentScanner()
        let snap = scanner.currentSnapshot(for: .guestTier)
        XCTAssertNil(snap.ssid)
        XCTAssertNil(snap.bssid)
    }

    func testScanForNetworksIsEmptyBelowOperator() throws {
        guard #available(macOS 13.0, *) else { throw XCTSkip("requires macOS 13+") }
        let scanner = WiFiEnvironmentScanner()
        XCTAssertTrue(scanner.scanForNetworks(for: .companion(memberID: "fam-1")).isEmpty)
        XCTAssertTrue(scanner.scanForNetworks(for: .guestTier).isEmpty)
    }

    func testLegacySnapshotRoutesToOperatorTier() throws {
        // Existing PresenceDetector callers use the no-arg API. It must
        // behave exactly like a principal=operator call so existing room
        // baselines keep working.
        guard #available(macOS 12.0, *) else { throw XCTSkip("requires macOS 12+") }
        let scanner = WiFiEnvironmentScanner()
        let legacy = scanner.currentSnapshot()
        let operatorSnap = scanner.currentSnapshot(for: .operatorTier)
        XCTAssertEqual(legacy.status, operatorSnap.status)
        // rssi + channel + hash should agree (SSID/BSSID may differ only if
        // the network changed between the two calls — not a reliability
        // concern for this assertion.)
        XCTAssertEqual(legacy.channel, operatorSnap.channel)
    }
}
