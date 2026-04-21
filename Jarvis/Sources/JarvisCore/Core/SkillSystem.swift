import Foundation

public typealias SkillHandler = (_ input: [String: Any], _ runtime: JarvisRuntime) async throws -> [String: Any]

public struct JarvisSkillDescriptor: Sendable {
    public let name: String
    public let description: String
    public let fileURL: URL
}

public final class JarvisSkillRegistry {
    private let descriptors: [JarvisSkillDescriptor]
    private let nativeHandlers: [String: SkillHandler]

    public init(paths: WorkspacePaths) throws {
        self.descriptors = try JarvisSkillRegistry.loadDescriptors(in: paths.skillDirectory)
        self.nativeHandlers = JarvisSkillRegistry.makeNativeHandlers(paths: paths)
    }

    public func listPayload() -> [[String: Any]] {
        descriptors.map { descriptor in
            [
                "name": descriptor.name,
                "description": descriptor.description,
                "callable": nativeHandlers[descriptor.name] != nil,
                "path": descriptor.fileURL.path
            ]
        }
        .sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
    }

    public func callableSkillNames() -> [String] {
        descriptors
            .map(\.name)
            .filter { nativeHandlers[$0] != nil }
            .sorted()
    }

    public func allSkillNames() -> [String] {
        descriptors.map(\.name).sorted()
    }

    public func execute(name: String, input: [String: Any], runtime: JarvisRuntime) async throws -> [String: Any] {
        guard descriptors.contains(where: { $0.name == name }) else {
            throw JarvisError.skillNotFound("Skill '\(name)' is not defined in agent-skills.")
        }
        guard let handler = nativeHandlers[name] else {
            throw JarvisError.nativeSkillUnavailable("Skill '\(name)' is documented but not bound to a native handler.")
        }
        return try await handler(input, runtime)
    }

    private static func loadDescriptors(in directory: URL) throws -> [JarvisSkillDescriptor] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return [] }

        let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)
        var result: [JarvisSkillDescriptor] = []
        while let item = enumerator?.nextObject() as? URL {
            guard item.lastPathComponent == "SKILL.md" else { continue }
            let content = try String(contentsOf: item, encoding: .utf8)
            if let descriptor = try parseDescriptor(from: content, fileURL: item) {
                result.append(descriptor)
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    private static func parseDescriptor(from content: String, fileURL: URL) throws -> JarvisSkillDescriptor? {
        let lines = content.components(separatedBy: .newlines)
        guard lines.first == "---" else { return nil }
        guard let closingIndex = lines.dropFirst().firstIndex(of: "---") else {
            throw JarvisError.serializationFailure("Invalid frontmatter in \(fileURL.path).")
        }
        let frontmatter = lines[1..<closingIndex]
        let pairs = Dictionary(uniqueKeysWithValues: frontmatter.compactMap { line -> (String, String)? in
            let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1])
        })
        guard let name = pairs["name"], let description = pairs["description"] else { return nil }
        return JarvisSkillDescriptor(name: name, description: description, fileURL: fileURL)
    }

    private static func makeNativeHandlers(paths: WorkspacePaths) -> [String: SkillHandler] {
        [
            "stigmergic-regulation-skill": { input, runtime async throws in
                let source = (input["source"] as? String) ?? "planner"
                let target = (input["target"] as? String) ?? "implementation"
                let current = (input["currentPheromone"] as? Double) ?? 0.0
                let baseEvaporation = (input["evaporation"] as? Double) ?? runtime.pheromind.baseEvaporation
                runtime.pheromind.baseEvaporation = baseEvaporation
                let edge = EdgeKey(source: source, target: target)
                runtime.pheromind.register(edge: edge, pheromone: current, somaticWeight: 0.4)

                let deposits = (input["deposits"] as? [[String: Any]]) ?? [
                    [
                        "signal": 1,
                        "magnitude": 1.0,
                        "agentID": "planner-a"
                    ]
                ]

                let mapped = try deposits.map { raw -> PheromoneDeposit in
                    guard let signalValue = raw["signal"] as? Int,
                          let signal = TernarySignal(rawValue: signalValue) else {
                        throw JarvisError.invalidInput("Each pheromone deposit must include signal = -1, 0, or 1.")
                    }
                    return PheromoneDeposit(
                        edge: edge,
                        signal: signal,
                        magnitude: (raw["magnitude"] as? Double) ?? 1.0,
                        agentID: (raw["agentID"] as? String) ?? "anonymous",
                        timestamp: Date()
                    )
                }

                let updated = try runtime.pheromind.applyGlobalUpdate(deposits: mapped)
                guard let state = updated[edge] else {
                    throw JarvisError.processFailure("Unable to update pheromone state for \(source)->\(target).")
                }
                try runtime.memory.recordSomaticPath(edge: edge, weight: state.somaticWeight)

                return [
                    "edge": ["source": source, "target": target],
                    "pheromone": state.pheromone,
                    "somaticWeight": state.somaticWeight,
                    "effectiveEvaporation": runtime.pheromind.effectiveEvaporation(for: state),
                    "recommendedNextEdge": runtime.pheromind.chooseNextEdge(from: source)?.dictionary ?? NSNull()
                ]
            },
            "recursive-language-model-repl-skill": { input, runtime async throws in
                let prompt = (input["prompt"] as? String) ?? ""
                let mode = (input["mode"] as? String) ?? "query"
                if mode == "repl" {
                    try await runtime.pythonRLM.startREPL(prompt: prompt)
                    return ["status": "interactive-repl-started"]
                }
                let query = (input["query"] as? String) ?? "Summarize the prompt."
                return try await runtime.pythonRLM.query(prompt: prompt, query: query).json
            },
            "memory-tier-memify-skill": { input, runtime async throws in
                let logPaths = (input["logPaths"] as? [String]) ?? []
                let logURLs = logPaths.isEmpty
                    ? try runtime.memory.defaultMemifyTargets()
                    : logPaths.map(runtime.paths.resolve(path:))
                let memify = try await runtime.memory.memify(logFileURLs: logURLs)
                let query = (input["query"] as? String) ?? "latest execution state"
                let page = try await runtime.memory.pageIn(query: query, limit: 4)
                return [
                    "memify": memify.json,
                    "page": page.json
                ]
            },
            "zero-shot-voice-synthesis-skill": { input, runtime async throws in
                let text = (input["text"] as? String) ?? "Good evening. I have assembled the system."
                let outputName = (input["outputName"] as? String) ?? "jarvis-response.aiff"
                let result = try await runtime.voice.synthesize(
                    text: text,
                    outputURL: runtime.paths.storageRoot.appendingPathComponent(outputName)
                )
                return result.json
            },
            "meta-harness-convex-observability-skill": { input, runtime async throws in
                let workflowURL = runtime.paths.resolve(path: (input["workflowPath"] as? String) ?? "Archon/MetaHarness/convex-observability-workflow.json")
                let result = try await runtime.metaHarness.runObservabilityWorkflow(at: workflowURL)
                return result.json
            }
        ]
    }
}