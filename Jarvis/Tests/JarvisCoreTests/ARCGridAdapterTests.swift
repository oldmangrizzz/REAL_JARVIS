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

    // MARK: - Additional coverage

    func testZeroRowGridInit() {
        // Empty cells array is permitted by init (no precondition fires).
        let grid = ARCGrid(cells: [])
        XCTAssertEqual(grid.rows, 0)
        XCTAssertEqual(grid.cols, 0)
    }

    func testLoadGridZeroDimensionsThrows() {
        let engine = StubPhysicsEngine()
        let bridge = ARCPhysicsBridge(engine: engine)

        XCTAssertThrowsError(try bridge.loadGrid(ARCGrid(cells: []))) { err in
            guard case PhysicsError.invalidConfiguration = err else {
                return XCTFail("expected .invalidConfiguration, got \(err)")
            }
        }
    }

    func testQuadrantDetectionPlacesColorsInCorrectRegion() {
        // 4x4 grid with distinct markers in each quadrant.
        // upper-left=blue(1), upper-right=red(2), lower-left=green(3), lower-right=yellow(4).
        let grid = ARCGrid(cells: [
            [1, 0, 0, 2],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [3, 0, 0, 4]
        ])
        let s = ARCGridSummarizer.summarize(grid)
        XCTAssertTrue(s.contains("upper-left: blue"), s)
        XCTAssertTrue(s.contains("upper-right: red"), s)
        XCTAssertTrue(s.contains("lower-left: green"), s)
        XCTAssertTrue(s.contains("lower-right: yellow"), s)
    }

    func testAllBackgroundGridReportsAllBlackSpatial() {
        let grid = ARCGrid(cells: [
            [0, 0],
            [0, 0]
        ])
        let s = ARCGridSummarizer.summarize(grid)
        XCTAssertTrue(s.contains("Spatial: all cells are background (black)."), s)
        // "Non-background colors: ." (empty list) should be present too.
        XCTAssertTrue(s.contains("Non-background colors: ."), s)
    }

    func testColorNameMapCoversAllTenCanonColors() {
        XCTAssertEqual(ARCGridSummarizer.colorNames[0], "black")
        XCTAssertEqual(ARCGridSummarizer.colorNames[1], "blue")
        XCTAssertEqual(ARCGridSummarizer.colorNames[2], "red")
        XCTAssertEqual(ARCGridSummarizer.colorNames[3], "green")
        XCTAssertEqual(ARCGridSummarizer.colorNames[4], "yellow")
        XCTAssertEqual(ARCGridSummarizer.colorNames[5], "grey")
        XCTAssertEqual(ARCGridSummarizer.colorNames[6], "magenta")
        XCTAssertEqual(ARCGridSummarizer.colorNames[7], "orange")
        XCTAssertEqual(ARCGridSummarizer.colorNames[8], "cyan")
        XCTAssertEqual(ARCGridSummarizer.colorNames[9], "maroon")
    }

    func testColorCountsSortedDescending() {
        // 2 ones, 1 two, 1 three → "blue: 2" appears before "red: 1" / "green: 1" in Colors line.
        let grid = ARCGrid(cells: [[1, 1], [2, 3]])
        let s = ARCGridSummarizer.summarize(grid)
        let colorsLine = s.split(separator: "\n").first(where: { $0.hasPrefix("Colors:") }).map(String.init) ?? ""
        let blueIdx = colorsLine.range(of: "blue: 2")?.lowerBound
        XCTAssertNotNil(blueIdx, "expected 'blue: 2' in: \(colorsLine)")
        XCTAssertTrue(colorsLine.contains("(total 4 cells)"), colorsLine)
    }

    func testARCGridCodableRoundTrip() throws {
        let original = ARCGrid(cells: [[1, 2, 3], [4, 5, 6]])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ARCGrid.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}

