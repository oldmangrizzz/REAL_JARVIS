import XCTest
@testable import JarvisCore

final class ARCGridAdapterTests: XCTestCase {
    override func setUp() {
        // Setup if needed
    }

    override func tearDown() {
        // Teardown if needed
    }

    // MARK: - Grid Parsing Tests

    func testGridParsing() throws {
        let gridData: [[Int]] = [
            [0, 1, 2],
            [3, 4, 5],
            [6, 7, 8]
        ]
        let grid = ARCGrid(cells: gridData)

        XCTAssertEqual(grid.rows, 3)
        XCTAssertEqual(grid.cols, 3)
        XCTAssertEqual(grid.cells[0][0], 0)
        XCTAssertEqual(grid.cells[1][1], 4)
        XCTAssertEqual(grid.cells[2][2], 8)
    }

    // MARK: - Grid → Physics Tests

    func testGridToPhysics() throws {
        let engine = StubPhysicsEngine()
        let bridge = ARCPhysicsBridge(engine: engine)

        let grid = ARCGrid(cells: [
            [1, 0, 2],
            [0, 3, 0]
        ])

        let mapping = try bridge.loadGrid(grid)

        // Only non-zero cells become bodies: 1, 2, 3 = 3 bodies
        XCTAssertEqual(mapping.count, 3)

        // Verify positions match grid coordinates (row, col)
        for (handle, coord) in mapping {
            let state = try engine.state(of: handle)
            // Grid uses (row, col), physics uses (x=col, y=row-from-bottom)
            XCTAssertEqual(state.transform.position.x, Double(coord.col), accuracy: 0.01)
            XCTAssertEqual(state.transform.position.y, Double(1 - coord.row), accuracy: 0.01)
        }
    }

    // MARK: - Grid Summary Tests

    func testGridSummary() throws {
        let grid = ARCGrid(cells: [
            [1, 2],
            [2, 1]
        ])

        let summary = ARCGridSummarizer.summarize(grid)

        // Check required components
        XCTAssert(summary.contains("Grid: 2 rows x 2 columns."))
        XCTAssert(summary.contains("Colors:"))
        XCTAssert(summary.contains("Non-background colors:"))
    }

    func testTaskSummary() throws {
        let trainPair = ARCPair(
            input: ARCGrid(cells: [[1, 2], [3, 4]]),
            output: ARCGrid(cells: [[5, 6], [7, 8]])
        )
        let testPair = ARCPair(
            input: ARCGrid(cells: [[9, 0], [1, 2]]),
            output: ARCGrid(cells: [[0, 0], [0, 0]])
        )
        let task = ARCTask(train: [trainPair], test: [testPair])

        let summary = ARCGridSummarizer.summarizeTask(task)

        // Check required sections
        XCTAssert(summary.contains("ARC Task with 1 training pairs and 1 test cases."))
        XCTAssert(summary.contains("--- Training Pair 1 ---"))
        XCTAssert(summary.contains("INPUT:"))
        XCTAssert(summary.contains("OUTPUT:"))
        XCTAssert(summary.contains("Test Case 1"))
    }

    // MARK: - Edge Cases

    func testEmptyGridHandling() throws {
        let engine = StubPhysicsEngine()
        let bridge = ARCPhysicsBridge(engine: engine)

        let grid = ARCGrid(cells: [
            [0, 0, 0],
            [0, 0, 0]
        ])

        let mapping = try bridge.loadGrid(grid)
        XCTAssertEqual(mapping.count, 0) // All zeros = no bodies
    }

    func testLargeGridSummaryBounds() throws {
        // Create a grid larger than 12x12
        var largeCells: [[Int]] = []
        for _ in 0..<15 {
            let row = Array(repeating: 1, count: 14)
            largeCells.append(row)
        }
        let grid = ARCGrid(cells: largeCells)

        let summary = ARCGridSummarizer.summarize(grid)

        // Should contain bounds message, NOT inline layout
        XCTAssert(summary.contains("Grid too large for spatial analysis"))
        XCTAssertFalse(summary.contains("Layout (row-major):"))
        XCTAssertFalse(summary.contains("R0:"))
    }
}
