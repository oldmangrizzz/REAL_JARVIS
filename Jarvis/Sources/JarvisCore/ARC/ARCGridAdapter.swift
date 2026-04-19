import Foundation

// MARK: - ARC-AGI Grid Types

public struct ARCGrid: Codable, Sendable, Equatable {
    public let cells: [[Int]]
    public var rows: Int { cells.count }
    public var cols: Int { cells.first?.count ?? 0 }

    public init(cells: [[Int]]) {
        // CX-003: validate that all rows have equal column counts
        if let firstCount = cells.first?.count {
            precondition(cells.allSatisfy { $0.count == firstCount },
                "ARCGrid jagged array: rows have unequal column counts (expected \(firstCount), found \(cells.map { $0.count }))")
        }
        self.cells = cells
    }
}

public struct ARCTask: Codable, Sendable {
    public let train: [ARCPair]
    public let test: [ARCPair]
}

public struct ARCPair: Codable, Sendable {
    public let input: ARCGrid
    public let output: ARCGrid
}

// MARK: - Grid → Physics World
// Each cell becomes a static body in the physics engine, positioned by (col, row).
// Color maps to a label. This lets the physics engine's raycast and spatial queries
// operate on ARC grids as physical objects.

public struct ARCPhysicsBridge {
    public let engine: PhysicsEngine

    public init(engine: PhysicsEngine) {
        self.engine = engine
    }

    /// Load an ARC grid into the physics world as static bodies.
    /// Returns a mapping from BodyHandle to grid coordinate.
    @discardableResult
    public func loadGrid(_ grid: ARCGrid, world: WorldDescriptor = WorldDescriptor(gravity: .zero)) throws -> [BodyHandle: (row: Int, col: Int)] {
        // CX-026: guard before reset — empty grid should not silently wipe the world
        guard grid.rows > 0, grid.cols > 0 else {
            throw PhysicsError.invalidConfiguration("ARC grid is empty (0 rows or 0 cols)")
        }
        try engine.reset(world: world)
        var mapping: [BodyHandle: (row: Int, col: Int)] = [:]

        for row in 0..<grid.rows {
            for col in 0..<grid.cols {
                let value = grid.cells[row][col]
                guard value != 0 else { continue } // 0 = background, skip

                let handle = try engine.addBody(BodyDescriptor(
                    label: "cell_\(row)_\(col)_v\(value)",
                    shape: Shape(kind: .box, extents: Vec3(0.5, 0.5, 0.5)),
                    mass: 1.0,
                    isStatic: true,
                    initialTransform: Transform(
                        position: Vec3(Double(col), Double(grid.rows - 1 - row), 0)
                    )
                ))
                mapping[handle] = (row, col)
            }
        }
        return mapping
    }
}

// MARK: - Grid → NLB Summary (Natural Language Barrier compliant)
// The LLM sees text, never raw arrays. Per PRINCIPLES.md §6.

public struct ARCGridSummarizer {
    public static let colorNames = [
        0: "black", 1: "blue", 2: "red", 3: "green",
        4: "yellow", 5: "grey", 6: "magenta", 7: "orange",
        8: "cyan", 9: "maroon"
    ]

    /// Summarize a grid as NLB-compliant natural language.
    public static func summarize(_ grid: ARCGrid) -> String {
        var lines: [String] = []
        lines.append("Grid: \(grid.rows) rows x \(grid.cols) columns.")

        // Color distribution
        var counts: [Int: Int] = [:]
        for row in grid.cells {
            for val in row {
                counts[val, default: 0] += 1
            }
        }
        let total = grid.rows * grid.cols
        let dist = counts.sorted { $0.value > $1.value }
            .map { "\(colorNames[$0.key] ?? "?\($0.key)"): \($0.value)" }
            .joined(separator: ", ")
        lines.append("Colors: \(dist) (total \(total) cells).")

        // Spatial patterns (basic)
        let uniqueColors = counts.keys.filter { $0 != 0 }.sorted()
        lines.append("Non-background colors: \(uniqueColors.map { colorNames[$0] ?? "?\($0)" }.joined(separator: ", ")).")

        // Spatial structure description (NLB-compliant — no raw cell values)
        if grid.rows <= 12 && grid.cols <= 12 {
            var regionDescriptions: [String] = []

            let midRow = grid.rows / 2
            let midCol = grid.cols / 2
            let quadrants = [
                ("upper-left", 0..<midRow, 0..<midCol),
                ("upper-right", 0..<midRow, midCol..<grid.cols),
                ("lower-left", midRow..<grid.rows, 0..<midCol),
                ("lower-right", midRow..<grid.rows, midCol..<grid.cols)
            ]

            for (name, rowRange, colRange) in quadrants {
                var qColors: Set<Int> = []
                for r in rowRange {
                    for c in colRange {
                        let v = grid.cells[r][c]
                        if v != 0 { qColors.insert(v) }
                    }
                }
                if !qColors.isEmpty {
                    let colorList = qColors.sorted().map { colorNames[$0] ?? "color(\($0))" }.joined(separator: ", ")
                    regionDescriptions.append("\(name): \(colorList)")
                }
            }

            if regionDescriptions.isEmpty {
                lines.append("Spatial: all cells are background (black).")
            } else {
                lines.append("Spatial quadrants: " + regionDescriptions.joined(separator: "; ") + ".")
            }
        } else {
            lines.append("Grid too large for spatial analysis (\(grid.rows)x\(grid.cols)).")
        }

        return lines.joined(separator: "\n")
    }

    /// Summarize an ARC task (train pairs + test input) as NLB text.
    public static func summarizeTask(_ task: ARCTask) -> String {
        var sections: [String] = []
        sections.append("ARC Task with \(task.train.count) training pairs and \(task.test.count) test cases.")

        for (i, pair) in task.train.enumerated() {
            sections.append("\n--- Training Pair \(i + 1) ---")
            sections.append("INPUT:\n\(summarize(pair.input))")
            sections.append("OUTPUT:\n\(summarize(pair.output))")
        }

        for (i, pair) in task.test.enumerated() {
            sections.append("\n--- Test Case \(i + 1) ---")
            sections.append("INPUT:\n\(summarize(pair.input))")
            sections.append("(Output is the target to predict.)")
        }

        return sections.joined(separator: "\n")
    }
}
