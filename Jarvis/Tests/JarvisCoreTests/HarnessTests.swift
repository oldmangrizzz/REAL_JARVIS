import XCTest
@testable import JarvisCore

final class HarnessTests: XCTestCase {
    func testMetaHarnessAddsValidationAndDiagnosisNodesWhenNeeded() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let workflowURL = paths.archonDirectory.appendingPathComponent("default_workflow.yaml")
        try """
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
        """.write(to: workflowURL, atomically: true, encoding: .utf8)

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
}
