import XCTest
@testable import JarvisCore

final class HarnessTests: XCTestCase {
    private func writeWorkflow(_ yaml: String, at url: URL) throws {
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }

    private let canonicalWorkflow = """
    name: jarvis-default
    version: 1
    nodes:
      - id: planning
        kind: planning
        command: plan
        depends_on: []
      - id: implementation
        kind: implementation
        command: implement
        depends_on: [planning]
      - id: review
        kind: review
        command: review
        depends_on: [implementation]
    """

    func testMetaHarnessAddsValidationAndDiagnosisNodesWhenNeeded() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let workflowURL = paths.archonDirectory.appendingPathComponent("default_workflow.yaml")
        try writeWorkflow(canonicalWorkflow, at: workflowURL)

        let traceURL = paths.traceDirectory.appendingPathComponent("execution.jsonl")
        try """
        {"workflowId":"jarvis-default","stepId":"implementation","inputContext":"plan","outputResult":"missing dependency prevented schema generation","status":"failure"}
        """.write(to: traceURL, atomically: true, encoding: .utf8)

        let result = try runtime.metaHarness.diagnoseAndRewrite(workflowURL: workflowURL, traceDirectory: paths.traceDirectory)
        let rewritten = try String(contentsOf: workflowURL, encoding: .utf8)

        XCTAssertTrue(result.mutationApplied)
        XCTAssertTrue(rewritten.contains("validation"))
        XCTAssertTrue(rewritten.contains("counterfactual-diagnosis"))
    }

    // MARK: - idempotence

    func testRerunOnAlreadyMutatedWorkflowAppliesNoFurtherChanges() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let workflowURL = paths.archonDirectory.appendingPathComponent("default_workflow.yaml")
        try writeWorkflow(canonicalWorkflow, at: workflowURL)
        let traceURL = paths.traceDirectory.appendingPathComponent("execution.jsonl")
        try """
        {"workflowId":"jarvis-default","stepId":"implementation","outputResult":"missing dependency","status":"failure"}
        """.write(to: traceURL, atomically: true, encoding: .utf8)

        _ = try runtime.metaHarness.diagnoseAndRewrite(workflowURL: workflowURL, traceDirectory: paths.traceDirectory)
        let afterFirst = try String(contentsOf: workflowURL, encoding: .utf8)

        let second = try runtime.metaHarness.diagnoseAndRewrite(workflowURL: workflowURL, traceDirectory: paths.traceDirectory)
        let afterSecond = try String(contentsOf: workflowURL, encoding: .utf8)

        XCTAssertFalse(second.mutationApplied, "second pass should be a no-op — both validation and counterfactual-diagnosis already present")
        XCTAssertEqual(afterFirst, afterSecond, "workflow file should be byte-stable under rerun")
    }

    // MARK: - CX-042 feedback-loop guard

    func testFeedbackLoopGuardRejectsWorkflowWithThreeInjectedNodes() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let workflowURL = paths.archonDirectory.appendingPathComponent("default_workflow.yaml")
        // Three nodes with ids matching the guard set → reject.
        try writeWorkflow("""
        name: jarvis-default
        version: 1
        nodes:
          - id: validation
            kind: validation
            command: build
            depends_on: []
          - id: validation
            kind: validation
            command: build
            depends_on: []
          - id: counterfactual-diagnosis
            kind: diagnosis
            command: diag
            depends_on: []
        """, at: workflowURL)

        XCTAssertThrowsError(try runtime.metaHarness.diagnoseAndRewrite(
            workflowURL: workflowURL, traceDirectory: paths.traceDirectory
        )) { err in
            guard case JarvisError.processFailure(let msg) = err,
                  msg.contains("feedback loop") else {
                return XCTFail("expected feedback-loop processFailure, got \(err)")
            }
        }
    }

    // MARK: - diagnosis categorization

    func testDiagnosisCategorizesSchemaFailures() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let workflowURL = paths.archonDirectory.appendingPathComponent("default_workflow.yaml")
        try writeWorkflow(canonicalWorkflow, at: workflowURL)
        let traceURL = paths.traceDirectory.appendingPathComponent("execution.jsonl")
        try """
        {"workflowId":"jarvis-default","stepId":"implementation","outputResult":"failed to decode response json schema","status":"failure"}
        """.write(to: traceURL, atomically: true, encoding: .utf8)

        let result = try runtime.metaHarness.diagnoseAndRewrite(workflowURL: workflowURL, traceDirectory: paths.traceDirectory)
        XCTAssertTrue(result.diagnosis.contains("schema mismatch"), result.diagnosis)
    }

    func testDiagnosisCategorizesBuildFailures() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let workflowURL = paths.archonDirectory.appendingPathComponent("default_workflow.yaml")
        try writeWorkflow(canonicalWorkflow, at: workflowURL)
        let traceURL = paths.traceDirectory.appendingPathComponent("execution.jsonl")
        try """
        {"workflowId":"jarvis-default","stepId":"implementation","outputResult":"xcodebuild failed to compile swift module","status":"failure"}
        """.write(to: traceURL, atomically: true, encoding: .utf8)

        let result = try runtime.metaHarness.diagnoseAndRewrite(workflowURL: workflowURL, traceDirectory: paths.traceDirectory)
        XCTAssertTrue(result.diagnosis.contains("validation failure"), result.diagnosis)
    }

    func testDiagnosisReportsStableWorkflowWhenNoFailuresPresent() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let workflowURL = paths.archonDirectory.appendingPathComponent("default_workflow.yaml")
        try writeWorkflow(canonicalWorkflow, at: workflowURL)
        // Trace dir exists but is empty.
        let result = try runtime.metaHarness.diagnoseAndRewrite(workflowURL: workflowURL, traceDirectory: paths.traceDirectory)
        XCTAssertEqual(result.diagnosis, "no failure hotspot detected; workflow remains stable")
    }

    // MARK: - review depends_on linkage

    func testReviewGainsValidationDependency() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let workflowURL = paths.archonDirectory.appendingPathComponent("default_workflow.yaml")
        try writeWorkflow(canonicalWorkflow, at: workflowURL)
        _ = try runtime.metaHarness.diagnoseAndRewrite(workflowURL: workflowURL, traceDirectory: paths.traceDirectory)
        let rewritten = try String(contentsOf: workflowURL, encoding: .utf8)
        // The review node should now list validation among its depends_on.
        let reviewBlock = rewritten.components(separatedBy: "- id: review").last ?? ""
        XCTAssertTrue(reviewBlock.contains("validation"),
                      "review depends_on must gain 'validation' after injection")
    }

    // MARK: - ensureDefaultWorkflow bootstraps missing file

    func testMissingWorkflowIsBootstrappedWithCanonicalNodes() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let workflowURL = paths.archonDirectory.appendingPathComponent("default_workflow.yaml")
        XCTAssertFalse(FileManager.default.fileExists(atPath: workflowURL.path))

        _ = try runtime.metaHarness.diagnoseAndRewrite(workflowURL: workflowURL, traceDirectory: paths.traceDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workflowURL.path))
        let content = try String(contentsOf: workflowURL, encoding: .utf8)
        for required in ["planning", "implementation", "review"] {
            XCTAssertTrue(content.contains("id: \(required)"), "bootstrap must include \(required)")
        }
    }

    // MARK: - rollback hash + telemetry linkage

    func testResultExposesRollbackHashAndWorkflowPath() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let workflowURL = paths.archonDirectory.appendingPathComponent("default_workflow.yaml")
        try writeWorkflow(canonicalWorkflow, at: workflowURL)
        let result = try runtime.metaHarness.diagnoseAndRewrite(workflowURL: workflowURL, traceDirectory: paths.traceDirectory)
        XCTAssertEqual(result.workflowPath, workflowURL.path)
        XCTAssertEqual(result.rollbackHash.count, 64, "sha256 hex is 64 chars")
        XCTAssertTrue(result.rollbackHash.allSatisfy { $0.isHexDigit })
    }

    func testTelemetryReceivesHarnessMutationRecord() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let workflowURL = paths.archonDirectory.appendingPathComponent("default_workflow.yaml")
        try writeWorkflow(canonicalWorkflow, at: workflowURL)
        _ = try runtime.metaHarness.diagnoseAndRewrite(workflowURL: workflowURL, traceDirectory: paths.traceDirectory)

        let telemetryURL = runtime.telemetry.tableURL("harness_mutations")
        XCTAssertTrue(FileManager.default.fileExists(atPath: telemetryURL.path))
        let content = try String(contentsOf: telemetryURL)
        XCTAssertTrue(content.contains("\"workflowId\":\"jarvis-default\""))
        XCTAssertTrue(content.contains("\"evaluationScore\""))
    }
}

