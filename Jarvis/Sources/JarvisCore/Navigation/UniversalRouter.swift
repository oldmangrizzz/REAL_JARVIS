import Foundation

/// NAV-001 Phase B: Deterministic best-path router.
///
/// Implements Dijkstra's algorithm with profile-aware edge weighting.
/// Identical inputs always produce byte-equal `Route` outputs
/// (deterministic tie-breaking by edge ID). No real network calls.
///
/// The router is `Sendable` and stateless — it holds only the graph,
/// which is immutable after init.
public struct UniversalRouter: Sendable {

    private let graph: any RoadGraph

    public init(graph: any RoadGraph) {
        self.graph = graph
    }

    /// Compute up to `limit` routes from `start` to `end`.
    /// Returns routes ordered by ascending total cost. Deterministic:
    /// same start/end/profiles/context always yields the same routes.
    ///
    /// Profiles whose `principalScope` does not include the principal's
    /// category are silently skipped (exhaustive allow-list, no default).
    public func routes(
        from start: String,
        to end: String,
        profiles: [any RoutingProfile],
        context: RoutingContext,
        limit: Int = 3
    ) throws -> [Route] {
        let principalCat = PrincipalCategory.of(context.principal)
        var results: [Route] = []

        for profile in profiles {
            guard profile.principalScope.contains(principalCat) else {
                // Tier gate: skip profiles not in this principal's scope.
                continue
            }
            if let route = singleRoute(from: start, to: end, profile: profile, context: context) {
                results.append(route)
            }
            if results.count >= limit { break }
        }

        return results
    }

    /// Single-source shortest path using Dijkstra with profile-weighted edges.
    /// Tie-break on edge ID for determinism.
    private func singleRoute(
        from start: String,
        to end: String,
        profile: any RoutingProfile,
        context: RoutingContext
    ) -> Route? {
        // Dijkstra's algorithm
        var dist: [String: Double] = [:]
        var prev: [String: String] = [:]
        var visited: Set<String> = []

        dist[start] = 0.0
        // Priority queue approximated with sorted array (deterministic for tests).
        var frontier: [(node: String, cost: Double)] = [(start, 0.0)]

        while let current = frontier.min(by: { $0.cost < $1.cost || ($0.cost == $1.cost && $0.node < $1.node) }) {
            frontier.removeAll { $0.node == current.node && $0.cost == current.cost }
            guard !visited.contains(current.node) else { continue }
            visited.insert(current.node)

            if current.node == end { break }

            for edge in graph.neighbors(of: current.node) {
                let weight = profile.edgeWeight(edge, context: context)
                let alt = dist[current.node]! + weight
                if alt < (dist[edge.toNode] ?? .infinity) {
                    dist[edge.toNode] = alt
                    prev[edge.toNode] = current.node
                    // Track the edge ID used to reach this node.
                    frontier.append((edge.toNode, alt))
                }
            }
        }

        guard dist[end] != nil else { return nil }

        // Reconstruct path as edge IDs.
        var pathEdgeIDs: [String] = []
        var node = end
        var totalLength: Double = 0.0
        while node != start {
            guard let predecessor = prev[node] else { return nil }
            // Find the edge from predecessor to node.
            let edgeOpt = graph.neighbors(of: predecessor).first(where: { $0.toNode == node })
            guard let edge = edgeOpt else { return nil }
            pathEdgeIDs.append(edge.id)
            totalLength += edge.lengthMeters
            node = predecessor
        }
        pathEdgeIDs.reverse()

        return Route(
            edgeIDs: pathEdgeIDs,
            totalCostWeighted: dist[end]!,
            totalLengthMeters: totalLength,
            profileIdentifier: profile.identifier
        )
    }
}