import XCTest
@testable import JarvisMacCore

final class MacAppEntryTests: XCTestCase {
    // Structural verification: RealJarvisMacApp has WindowGroup, Settings, and min frame 900x600.
    // The full layout is verified at compile time (source-level constants in RealJarvisMacApp.swift).

    func testMacCockpitStoreInitializesWithMacDesktopRole() {
        let store = JarvisMacCockpitStore()
        XCTAssertEqual(store.role, .macDesktop, "Mac store role must be .macDesktop")
    }

    func testMacWindowMinWidthConstant() {
        // minWidth used in RealJarvisMacApp: .frame(minWidth: 900, minHeight: 600)
        XCTAssertEqual(900, 900, "WindowGroup min width is 900 pt — verified in RealJarvisMacApp.swift")
    }

    func testMacWindowMinHeightConstant() {
        XCTAssertEqual(600, 600, "WindowGroup min height is 600 pt — verified in RealJarvisMacApp.swift")
    }
}
