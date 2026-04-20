import SwiftUI

// MARK: - SceneBriefingView (Phase E)

/// Phase E — Pre-search briefing card.
/// 
/// Consumes a `SceneBriefing` (GLM defines the type). Renders:
/// - Destination summary (name, jurisdiction, nearest cross-streets)
/// - Access notes (entrances, ADA if Companion; ingress/egress if Responder)
/// - Surrounding hazards (current overlays within N meters)
/// - "Last updated" per data source — non-negotiable honesty about staleness
/// 
/// Card is audio-first — every element has a short spoken form for voice output.
public struct SceneBriefingView: View {
    let briefing: SceneBriefing
    let principal: Principal
    
    public init(briefing: SceneBriefing, principal: Principal) {
        self.briefing = briefing
        self.principal = principal
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DestinationSummary(destination: briefing.destination)
                .padding(.bottom, 8)
            
            Divider()
                .background(NavigationDesignTokens.SceneBriefing.stroke(for: principal))
            
            AccessNotesView(notes: briefing.accessNotes, principal: principal)
                .padding(.bottom, 8)
            
            HazardSummaryView(hazards: briefing.surroundingHazards, principal: principal)
                .padding(.bottom, 8)
            
            SourceAttestationView(attestations: briefing.sourceAttestations)
                .padding(.bottom, 4)
        }
        .padding(16)
        .background(NavigationDesignTokens.SceneBriefing.color(for: principal))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(NavigationDesignTokens.SceneBriefing.stroke(for: principal), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - DestinationSummary

private struct DestinationSummary: View {
    let destination: DestinationInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Destination")
                .font(.system(size: NavigationDesignTokens.Typography.hudSmall, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: JarvisGMRIPalette.emeraldGreenHex))
            
            Text(destination.name)
                .font(.system(size: NavigationDesignTokens.Typography.hudMedium, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex))
            
            if let jurisdiction = destination.jurisdiction, !jurisdiction.isEmpty {
                Text("Jurisdiction: \(jurisdiction)")
                    .font(.system(size: NavigationDesignTokens.Typography.hudSmall, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex).opacity(0.7))
            }
            
            if let crossStreets = destination.nearestCrossStreets, !crossStreets.isEmpty {
                Text("Near: \(crossStreets)")
                    .font(.system(size: NavigationDesignTokens.Typography.hudSmall, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex).opacity(0.7))
            }
        }
    }
    
    // Audio-readable summary for voice-first surfaces
    var audioSummary: String {
        var parts: [String] = []
        parts.append("Destination: \(destination.name)")
        if let jurisdiction = destination.jurisdiction, !jurisdiction.isEmpty {
            parts.append("Jurisdiction: \(jurisdiction)")
        }
        if let crossStreets = destination.nearestCrossStreets, !crossStreets.isEmpty {
            parts.append("Near: \(crossStreets)")
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - AccessNotesView

private struct AccessNotesView: View {
    let notes: AccessNotes
    let principal: Principal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Access")
                .font(.system(size: NavigationDesignTokens.Typography.hudSmall, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: JarvisGMRIPalette.emeraldGreenHex))
            
            AccessEntrancesView(entrances: notes.entrances, principal: principal)
            
            AccessibilityView(info: notes.accessibility, principal: principal)
            
            if let ingressEgress = notes.ingressEgress, !ingressEgress.isEmpty {
                Text("Ingress/Egress: \(ingressEgress)")
                    .font(.system(size: NavigationDesignTokens.Typography.hudSmall, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex).opacity(0.7))
            }
        }
    }
    
    var audioSummary: String {
        var parts: [String] = []
        parts.append("Access: \(notes.entrances.count) entrances available")
        parts.append("Accessibility: \(notes.accessibility.description)")
        if let ingressEgress = notes.ingressEgress, !ingressEgress.isEmpty {
            parts.append("Ingress/egress: \(ingressEgress)")
        }
        return parts.joined(separator=". ")
    }
}

private struct AccessEntrancesView: View {
    let entrances: [Entrance]
    let principal: Principal
    
    var body: some View {
        ForEach(entrances, id: \.name) { entrance in
            HStack {
                Text("Entrance")
                    .font(.system(size: NavigationDesignTokens.Typography.hudSmall, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex).opacity(0.8))
                Spacer()
                Text(entrance.name)
                    .font(.system(size: NavigationDesignTokens.Typography.hudSmall, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex))
            }
        }
    }
}

private struct AccessibilityView: View {
    let info: AccessibilityInfo
    let principal: Principal
    
    var body: some View {
        HStack(spacing: 12) {
            AccessibilityIcon(feature: "curbCuts", available: info.curbCuts, principal: principal)
            AccessibilityIcon(feature: "elevators", available: info.elevators, principal: principal)
            AccessibilityIcon(feature: "parking", available: info.accessibleParking, principal: principal)
        }
    }
    
    var audioSummary: String {
        var features: [String] = []
        if info.curbCuts { features.append("curb cuts") }
        if info.elevators { features.append("elevators") }
        if info.accessibleParking { features.append("accessible parking") }
        return features.isEmpty ? "no accessibility features reported" : features.joined(separator: ", ")
    }
}

private struct AccessibilityIcon: View {
    let feature: String
    let available: Bool
    let principal: Principal
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconFor(feature: feature, available: available))
                .foregroundStyle(colorFor(feature: feature, available: available))
                .font(.system(size: 12))
            Text(labelFor(feature: feature, available: available))
                .font(.system(size: NavigationDesignTokens.Typography.hudSmall, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex).opacity(available ? 1 : 0.5))
        }
    }
    
    private func iconFor(feature: String, available: Bool) -> String {
        switch feature {
        case "curbCuts": return available ? "arrow.down.left.and.arrow.up.right" : "slash.circle"
        case "elevators": return available ? "arrow.up.and.down.square" : "slash.circle"
        case "parking": return available ? "p.circle.fill" : "slash.circle"
        default: return "minus.circle"
        }
    }
    
    private func colorFor(feature: String, available: Bool) -> Color {
        available ? Color(hex: JarvisGMRIPalette.emeraldGreenHex) : Color(hex: JarvisGMRIPalette.crimsonHex)
    }
    
    private func labelFor(feature: String, available: Bool) -> String {
        switch feature {
        case "curbCuts": return "Curb cuts"
        case "elevators": return "Elevators"
        case "parking": return "Parking"
        default: return feature
        }
    }
}

// MARK: - HazardSummaryView

private struct HazardSummaryView: View {
    let hazards: [HazardSummary]
    let principal: Principal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Surrounding Hazards")
                .font(.system(size: NavigationDesignTokens.Typography.hudSmall, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: JarvisGMRIPalette.emeraldGreenHex))
            
            if hazards.isEmpty {
                Text("No nearby hazards")
                    .font(.system(size: NavigationDesignTokens.Typography.hudSmall, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex).opacity(0.7))
            } else {
                ForEach(hazards, id: \.type) { hazard in
                    HazardRow(hazard: hazard, principal: principal)
                }
            }
        }
    }
    
    var audioSummary: String {
        if hazards.isEmpty {
            return "No nearby hazards. All clear."
        }
        let sorted = hazards.sorted { $0.distanceMeters < $1.distanceMeters }
        return "Nearby hazards: " + sorted.prefix(3).map { h in
            let dist = h.distanceMeters >= 1000 ? String(format: "%.1f km", h.distanceMeters/1000) : String(format: "%.0f m", h.distanceMeters)
            return "\(h.type.description) at \(dist)"
        }.joined(separator: "; ")
    }
}

private struct HazardRow: View {
    let hazard: HazardSummary
    let principal: Principal
    
    var body: some View {
        HStack {
            Text(hazard.type.description)
                .font(.system(size: NavigationDesignTokens.Typography.hudSmall, weight: .medium, design: .monospaced))
                .foregroundStyle(hazardColor(for: hazard.severity))
            Spacer()
            Text(hazard.distanceText())
                .font(.system(size: NavigationDesignTokens.Typography.hudSmall, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex))
        }
    }
    
    private func hazardColor(for severity: Severity) -> Color {
        switch severity {
        case .critical: return NavigationDesignTokens.HazardCritical.color(for: principal)
        case .elevated: return NavigationDesignTokens.HazardElevated.color(for: principal)
        case .informational: return NavigationDesignTokens.HazardInfo.color(for: principal)
        }
    }
}

extension HazardSummary {
    func distanceText() -> String {
        let meters = distanceMeters
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        } else {
            return String(format: "%.0f m", meters)
        }
    }
}

extension HazardType {
    var description: String {
        switch self {
        case .fire: return "Active Fire"
        case .severeWeather: return "Severe Weather"
        case .seismic: return "Seismic Activity"
        case .traffic: return "Traffic incident"
        case .emergencyServices: return "EMS Activity"
        case .other(let name): return name
        }
    }
}

// MARK: - SourceAttestationView

/// "Last updated" per data source — non-negotiable honesty about staleness.
public struct SourceAttestationView: View {
    let attestations: [SourceAttestation]
    
    public init(attestations: [SourceAttestation]) {
        self.attestations = attestations
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Data Last Updated")
                .font(.system(size: NavigationDesignTokens.Typography.hudSmall, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex).opacity(0.7))
            
            ForEach(attestations, id: \.sourceKey) { attestation in
                HStack {
                    Text(sourceLabel(for: attestation.sourceKey))
                        .font(.system(size: NavigationDesignTokens.Typography.hudSmall, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex))
                    Spacer()
                    Text(attestation.lastUpdated.timeAgo())
                        .font(.system(size: NavigationDesignTokens.Typography.hudSmall, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex).opacity(0.8))
                }
            }
        }
    }
    
    private func sourceLabel(for key: String) -> String {
        // Map source keys to human-readable labels
        let mapping: [String: String] = [
            "osm.tiles": "OpenStreetMap",
            "mapbox.tiles": "Mapbox",
            "txdot.drivetexas": "TxDOT DriveTexas",
            "firms.nasa": "NASA FIRMS (Fires)",
            "noaa.nws": "NOAA/NWS (Weather)",
            "usgs.quake": "USGS Earthquakes",
            "recreation.gov": "Recreation.gov",
            "nps.api": "NPS API",
            "blm.arcgis": "BLM Open Data",
            "osm.overpass": "OSM Overpass",
            "epa.airnow": "EPA AirNow",
            "noaa.tides": "NOAA Tides",
            "wikipedia.rest": "Wikipedia"
        ]
        return mapping[key] ?? key
    }
}

extension String {
    /// Convert ISO 8601 to human-readable time ago (e.g., "5 min ago").
    func timeAgo() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let date = formatter.date(from: self) else { return self }
        let now = Date()
        let components = Calendar.current.dateComponents([.minute, .hour, .day], from: date, to: now)
        
        if let minutes = components.minute, minutes < 60 {
            if minutes == 0 {
                return "Just now"
            }
            return "\(minutes) min ago"
        }
        
        if let hours = components.hour, hours < 24 {
            return "\(hours) hr\(hours > 1 ? "s" : "") ago"
        }
        
        if let days = components.day {
            return "\(days) day\(days > 1 ? "s" : "") ago"
        }
        
        return self
    }
}

// MARK: - Test Support

#if DEBUG

struct SceneBriefingView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SceneBriefingView(briefing: .previewOperator, principal: .operatorTier)
                .previewDisplayName("Operator Tier")
                .background(Color.black)
            
            SceneBriefingView(briefing: .previewCompanion, principal: .companion(memberID: "fam-001"))
                .previewDisplayName("Companion Tier")
                .background(Color.black)
            
            SceneBriefingView(briefing: .previewResponder, principal: .responder(role: .emt))
                .previewDisplayName("Responder EMT Tier")
                .background(Color.black)
        }
        .previewLayout(.sizeThatFits)
    }
    
    static var previewData: SceneBriefing {
        SceneBriefing(
            destination: DestinationInfo(
                name: "GMRI Field Station",
                jurisdiction: "Bexar County",
                nearestCrossStreets: "Lambs Ave & Blanco St",
                coordinates: [29.4241, -98.4934]
            ),
            accessNotes: AccessNotes(
                entrances: [
                    Entrance(name: "North Entrance", location: [29.4242, -98.4933], accessibilityRating: .accessible),
                    Entrance(name: "South Gate", location: [29.4239, -98.4936], accessibilityRating: .limited)
                ],
                accessibility: AccessibilityInfo(curbCuts: true, elevators: false, accessibleParking: true),
                ingressEgress: "Perimeter road accessible (Responder only)"
            ),
            surroundingHazards: [
                HazardSummary(type: .traffic, severity: .elevated, distanceMeters: 450, observedAt: "2026-04-20T10:15:00Z"),
                HazardSummary(type: .severeWeather, severity: .informational, distanceMeters: 850, observedAt: "2026-04-20T10:12:00Z")
            ],
            sourceAttestations: [
                SourceAttestation(sourceKey: "osm.tiles", lastUpdated: "2026-04-20T10:10:00Z"),
                SourceAttestation(sourceKey: "txdot.drivetexas", lastUpdated: "2026-04-20T10:14:00Z"),
                SourceAttestation(sourceKey: "noaa.nws", lastUpdated: "2026-04-20T10:13:00Z")
            ]
        )
    }
    
    static var previewOperator: SceneBriefing {
        previewData
    }
    
    static var previewCompanion: SceneBriefing {
        previewData
    }
    
    static var previewResponder: SceneBriefing {
        var data = previewData
        data.accessNotes.ingressEgress = "All perimeter roads accessible. EMS preferred routing available."
        return data
    }
}

#endif
