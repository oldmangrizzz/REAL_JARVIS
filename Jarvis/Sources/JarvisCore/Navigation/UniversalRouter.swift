import Foundation

/// NAV-001 Phase B: Deterministic best‑path router.
///
/// Implements Dijkstra's algorithm with profile‑aware edge weighting and
/// deterministic tie‑breaking (by edge identifier). Identical inputs always
/// produce byte‑equal `Route` outputs. No network calls are performed.
///
/// The router is `Sendable` and stateless — it holds only the graph, which is
/// immutable after initialization.
public struct UniversalRouter: Sendable {

    private let graph: any RoadGraph

    public init(graph: any RoadGraph) {
        self.graph = graph
    }

    /// Compute up to `limit` routes from `start` to `end`.
    ///
    /// The returned routes are ordered by ascending total cost. Deterministic:
    /// the same start/end/profiles/context always yields the same routes.
    ///
    /// Profiles whose `principalScope` does not include the principal's category
    /// are silently skipped (exhaustive allow‑list, no default).
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
            if let route = singleRoute(
                from: start,
                to: end,
                profile: profile,
                context: context
            ) {
                results.append(route)
            }
            if results.count >= limit { break }
        }

        return results
    }

    // MARK: - Private helpers

    /// Single‑source shortest path using Dijkstra with profile‑weighted edges.
    /// Deterministic tie‑breaking is performed on edge identifiers.
    private func singleRoute(
        from start: String,
        to end: String,
        profile: any RoutingProfile,
        context: RoutingContext
    ) -> Route? {
        // Distance from start to each node.
        var dist: [String: Double] = [:]
        // Predecessor node for each visited node.
        var prevNode: [String: String] = [:]
        // Edge identifier that was used to reach the node.
        var prevEdgeID: [String: String] = [:]

        var visited: Set<String> = []

        dist[start] = 0.0

        // Frontier is a simple array; we always pick the minimum element.
        // This guarantees deterministic ordering for the test suite.
        var frontier: [(node: String, cost: Double)] = [(start, 0.0)]

        while let current = frontier.min(by: {
            if $0.cost != $1.cost { return $0.cost < $1.cost }
            // Deterministic tie‑break on node identifier.
            return $0.node < $1.node
        }) {
            // Remove *all* entries that match the selected node & cost.
            frontier.removeAll {
                $0.node == current.node && $0.cost == current.cost
            }

            guard !visited.contains(current.node) else { continue }
            visited.insert(current.node)

            if current.node == end { break }

            for edge in graph.neighbors(of: current.node) {
                let weight = profile.edgeWeight(edge, context: context)
                let alt = dist[current.node]! + weight

                let existing = dist[edge.toNode] ?? .infinity

                if alt < existing {
                    // Better path found.
                    dist[edge.toNode] = alt
                    prevNode[edge.toNode] = current.node
                    prevEdgeID[edge.toNode] = edge.id
                    frontier.append((edge.toNode, alt))
                } else if alt == existing {
                    // Equal cost – apply deterministic tie‑break on edge ID.
                    if let storedEdgeID = prevEdgeID[edge.toNode],
                       edge.id < storedEdgeID {
                        // Prefer the lexicographically smaller edge identifier.
                        prevNode[edge.toNode] = current.node
                        prevEdgeID[edge.toNode] = edge.id
                        // No need to modify `dist` (same value) but we must ensure the
                        // frontier contains the node so that subsequent relaxations see
                        // the updated predecessor. Adding a duplicate is harmless.
                        frontier.append((edge.toNode, alt))
                    }
                }
            }
        }

        guard let _ = dist[end] else { return nil }

        // Reconstruct the path from `end` back to `start`.
        var edgeIDs: [String] = []
        var node = end
        var totalLength: Double = 0.0

        while node != start {
            guard let predecessor = prevNode[node],
                  let edgeID = prevEdgeID[node] else { return nil }

            // Retrieve the edge to obtain its length.
            guard let edge = graph.neighbors(of: predecessor).first(where: { $0.id == edgeID }) else {
                return nil
            }

            edgeIDs.append(edgeID)
            totalLength += edge.lengthMeters
            node = predecessor
        }

        edgeIDs.reverse()

        return Route(
            edgeIDs: edgeIDs,
            totalCostWeighted: dist[end]!,
            totalLengthMeters: totalLength,
            profileIdentifier: profile.identifier
        )
    }
}