import XCTest
@testable import JarvisCore

final class SkillRegistryTests: XCTestCase {
    func testRegistryLoadsJarvisNativeSkillsAndExecutesOne() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let registry = try JarvisSkillRegistry(paths: paths)

        let listed = registry.listPayload()
        let names = listed.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("stigmergic-regulation-skill"))
        XCTAssertTrue(names.contains("meta-harness-convex-observability-skill"))

        let result = try registry.execute(name: "stigmergic-regulation-skill", input: [
            "source": "planning",
            "target": "implementation",
            "currentPheromone": 0.5,
            "deposits": [["signal": 1, "magnitude": 1.0, "agentID": "tester"]]
        ], runtime: runtime)

        XCTAssertNotNil(result["pheromone"] as? Double)
        XCTAssertNotNil(result["effectiveEvaporation"] as? Double)
    }
}
