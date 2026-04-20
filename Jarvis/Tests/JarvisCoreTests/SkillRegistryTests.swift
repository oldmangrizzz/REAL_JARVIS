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

    // MARK: - listPayload / enumeration

    func testListPayloadIsSortedByName() throws {
        let paths = try makeTestWorkspace()
        let registry = try JarvisSkillRegistry(paths: paths)
        let names = registry.listPayload().compactMap { $0["name"] as? String }
        XCTAssertEqual(names, names.sorted(), "descriptors must be loaded sorted by name")
    }

    func testListPayloadExposesDescriptionAndFilePath() throws {
        let paths = try makeTestWorkspace()
        let registry = try JarvisSkillRegistry(paths: paths)
        let entry = try XCTUnwrap(registry.listPayload().first {
            ($0["name"] as? String) == "stigmergic-regulation-skill"
        })
        XCTAssertNotNil(entry["description"] as? String)
        XCTAssertFalse((entry["description"] as? String ?? "").isEmpty)
        XCTAssertNotNil(entry["path"] as? String)
    }

    func testCallableSkillNamesIsSubsetOfAllSkillNames() throws {
        let paths = try makeTestWorkspace()
        let registry = try JarvisSkillRegistry(paths: paths)
        let all = Set(registry.allSkillNames())
        let callable = Set(registry.callableSkillNames())
        XCTAssertTrue(callable.isSubset(of: all))
        XCTAssertTrue(callable.contains("stigmergic-regulation-skill"))
    }

    // MARK: - execute error paths

    func testExecuteUnknownSkillThrowsSkillNotFound() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let registry = try JarvisSkillRegistry(paths: paths)

        XCTAssertThrowsError(try registry.execute(name: "no-such-skill", input: [:], runtime: runtime)) { err in
            guard case JarvisError.skillNotFound = err else {
                return XCTFail("expected skillNotFound, got \(err)")
            }
        }
    }

    func testStigmergicSkillRejectsInvalidDepositSignal() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let registry = try JarvisSkillRegistry(paths: paths)

        XCTAssertThrowsError(try registry.execute(
            name: "stigmergic-regulation-skill",
            input: [
                "source": "s", "target": "t",
                "deposits": [["signal": 9, "magnitude": 1.0, "agentID": "x"]]
            ],
            runtime: runtime
        )) { err in
            guard case JarvisError.invalidInput = err else {
                return XCTFail("expected invalidInput for bad signal, got \(err)")
            }
        }
    }

    func testStigmergicSkillDefaultsApplyWhenInputOmitted() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let registry = try JarvisSkillRegistry(paths: paths)

        // No source/target/deposits provided — handler falls back to
        // (planner → implementation) and a default reinforce deposit.
        let result = try registry.execute(
            name: "stigmergic-regulation-skill",
            input: [:],
            runtime: runtime
        )
        let edge = try XCTUnwrap(result["edge"] as? [String: Any])
        XCTAssertEqual(edge["source"] as? String, "planner")
        XCTAssertEqual(edge["target"] as? String, "implementation")
        XCTAssertGreaterThan(try XCTUnwrap(result["pheromone"] as? Double), 0.0)
    }

    func testStigmergicSkillReflectsEvaporationOverride() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let registry = try JarvisSkillRegistry(paths: paths)

        _ = try registry.execute(
            name: "stigmergic-regulation-skill",
            input: [
                "source": "a", "target": "b",
                "evaporation": 0.42,
                "deposits": [["signal": 0, "magnitude": 0.0, "agentID": "n"]]
            ],
            runtime: runtime
        )
        XCTAssertEqual(runtime.pheromind.baseEvaporation, 0.42, accuracy: 1e-9,
                       "handler must push user-supplied evaporation into the engine")
    }
}

