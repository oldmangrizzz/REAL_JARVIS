import Foundation

/// NAV-001 Phase B: Protocol for a road/distance graph.
///
/// This is the graph abstraction consumed by `UniversalRouter`. A production
/// implementation wraps a real tiled graph (OpenStreetMap, Mapbox, etc.).
/// Tests inject `InMemoryRoadGraph` with fixture data.
///
/// CANON: operator-teachable; persistence ticket pending. The graph is
/// read-only for routing; it does not persist taught parameters.
public protocol RoadGraph: Sendable {
    func edge(id: String) -> RouteEdge?
    func neighbors(of node: String) -> [RouteEdge]
}

/// A directed edge in the road graph.
public struct RouteEdge: Sendable, Equatable, Hashable, Codable {
    public let id: String
    public let fromNode: String
    public let toNode: String
    public let lengthMeters: Double
    public let maxSpeedKPH: Double?
    public let attributes: [String: String]

    public init(id: String, fromNode: String, toNode: String,
                lengthMeters: Double, maxSpeedKPH: Double? = nil,
                attributes: [String: String] = [:]) {
        self.id = id
        self.fromNode = fromNode
        self.toNode = toNode
        self.lengthMeters = lengthMeters
        self.maxSpeedKPH = maxSpeedKPH
        self.attributes = attributes
    }
}

/// Context passed into `RoutingProfile.edgeWeight` for hazard-aware routing.
public struct RoutingContext: Sendable {
    public let principal: Principal
    public let activeHazards: [HazardOverlayFeature]
    public let requestedAt: Date

    public init(principal: Principal, activeHazards: [HazardOverlayFeature], requestedAt: Date = Date()) {
        self.principal = principal
        self.activeHazards = activeHazards
        self.requestedAt = requestedAt
    }
}

/// A computed route from one node to another.
public struct Route: Sendable, Equatable, Codable {
    public let edgeIDs: [String]
    public let totalCostWeighted: Double
    public let totalLengthMeters: Double
    public let profileIdentifier: String

    public init(edgeIDs: [String], totalCostWeighted: Double,
                totalLengthMeters: Double, profileIdentifier: String) {
        self.edgeIDs = edgeIDs
        self.totalCostWeighted = totalCostWeighted
        self.totalLengthMeters = totalLengthMeters
        self.profileIdentifier = profileIdentifier
    }
}

/// Routing profile protocol. Each profile defines which principal
/// categories are allowed and how edges are weighted.
///
/// Tier gating: `principalScope` is an exhaustive allow-list. If the
/// principal's category is not in the scope, the profile is not used
/// for that principal's routes.
public protocol RoutingProfile: Sendable {
    var identifier: String { get }
    var principalScope: Set<PrincipalCategory> { get }
    func edgeWeight(_ edge: RouteEdge, context: RoutingContext) -> Double
}

// MARK: - In-Memory Road Graph (test fixture only; do not ship to production)

/// Tiny in-memory graph for deterministic test routing. Loaded from
/// JSON fixture `route_graph_small.json`. Production graphs come from
/// real data pipelines — this is purely for hermetic unit tests.
public struct InMemoryRoadGraph: RoadGraph, Sendable {
    private let edgeMap: [String: RouteEdge]
    private let adjacency: [String: [RouteEdge]]

    public init(edges: [RouteEdge]) {
        var emap: [String: RouteEdge] = [:]
        var adj: [String: [RouteEdge]] = [:]
        for edge in edges {
            emap[edge.id] = edge
            adj[edge.fromNode, default: []].append(edge)
        }
        self.edgeMap = emap
        self.adjacency = adj
    }

    public func edge(id: String) -> RouteEdge? { edgeMap[id] }

    public func neighbors(of node: String) -> [RouteEdge] { adjacency[node] ?? [] }
}