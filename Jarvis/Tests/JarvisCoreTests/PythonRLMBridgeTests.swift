import XCTest
@testable import JarvisCore

final class PythonRLMBridgeTests: XCTestCase {
    func testRecursivePromptQueryReturnsTrace() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let prompt = """
        Planning phase defines the architecture.

        Implementation phase writes the code.

        Validation phase proves the build is sound.
        """

        let result = try runtime.pythonRLM.query(prompt: prompt, query: "Which phase proves the build?")

        XCTAssertTrue(result.response.lowercased().contains("validation"))
        XCTAssertFalse(result.trace.isEmpty)
        XCTAssertEqual(result.symbols.count, 3)
    }
}
