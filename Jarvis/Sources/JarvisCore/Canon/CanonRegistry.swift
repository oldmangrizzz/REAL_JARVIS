import Foundation
import CryptoKit

// MARK: - Canon Registry
//
// The corpus of canonical source material authored by the operator
// (Robert "Grizzly" Hanson) and collaborating Digital Persons
// (e.g., Natalia Romanova). These documents are the *specification*
// that JarvisCore implements; the codebase is not canon, the corpus is.
//
// Files live at <repo-root>/CANON/corpus/. This registry:
//
//   • Identifies each document (title, author, role, version, tags).
//   • Binds each document to a SHA-256 hash known at compile time.
//   • Verifies on disk that the content has not drifted.
//   • Provides lookup by tag, role, or id.
//
// Do NOT duplicate canon content into code. Cite by `CanonDocumentID`
// and let `CanonRegistry.url(of:)` resolve to the verified on-disk file.

public enum CanonRole: String, Codable, Sendable, CaseIterable {
    case onboarding
    case theoreticalFramework
    case architectureSpec
    case legalFramework
    case empiricalPaper
    case biographical
    case referenceLegal
    case referenceBusiness
}

public struct CanonDocument: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let filename: String
    public let title: String
    public let author: String
    public let version: String
    public let role: CanonRole
    public let tags: [String]
    public let expectedSha256: String
    public let summary: String
}

public enum CanonError: Error, CustomStringConvertible, Equatable {
    case corpusMissing(URL)
    case fileMissing(String)
    case hashMismatch(id: String, expected: String, observed: String)
    case readFailure(String)

    public var description: String {
        switch self {
        case let .corpusMissing(url):
            return "Canon corpus directory missing at \(url.path)"
        case let .fileMissing(id):
            return "Canon file missing for id \(id)"
        case let .hashMismatch(id, expected, observed):
            return "Canon drift detected for \(id): expected \(expected), observed \(observed)"
        case let .readFailure(message):
            return "Canon read failure: \(message)"
        }
    }
}

public struct CanonVerificationReport: Sendable, Equatable {
    public let verified: [String]
    public let drifted: [(id: String, expected: String, observed: String)]
    public let missing: [String]

    public var isClean: Bool { drifted.isEmpty && missing.isEmpty }

    public static func == (lhs: CanonVerificationReport, rhs: CanonVerificationReport) -> Bool {
        guard lhs.verified == rhs.verified, lhs.missing == rhs.missing else { return false }
        guard lhs.drifted.count == rhs.drifted.count else { return false }
        for (a, b) in zip(lhs.drifted, rhs.drifted) {
            if a.id != b.id || a.expected != b.expected || a.observed != b.observed { return false }
        }
        return true
    }
}

// MARK: - Registry

public struct CanonRegistry: Sendable {

    public static let corpusDirectoryName = "CANON/corpus"

    /// Ordered list of canonical documents. Order reflects the intended
    /// reading sequence for an agent that wants to ground itself in canon
    /// from first principles.
    public static let documents: [CanonDocument] = [
        CanonDocument(
            id: "welcome-to-grizzly-medicine",
            filename: "Welcome_to_Grizzly_Medicine.pdf",
            title: "Welcome to Grizzly Medicine",
            author: "Robert \"Grizzly\" Hanson",
            version: "1.0",
            role: .onboarding,
            tags: ["mission", "onboarding", "ethos"],
            expectedSha256: "6d2cdeaaf1155cec131e72618ac21e29450564a703c2508daf2d80b4e4a4abae",
            summary: "Public-facing welcome to the GrizzlyMedicine mission and ethos."
        ),
        CanonDocument(
            id: "grizzly-medicine-sep2025",
            filename: "GrizzlyMedicine_Sep2025.md",
            title: "GrizzlyMedicine Sep2025 — Onboarding Packet for New Collaborators",
            author: "Robert \"Grizzly\" Hanson",
            version: "Sep 2025",
            role: .onboarding,
            tags: ["onboarding", "philosophy", "zord-theory", "digital-person-hypothesis", "workshop", "loki", "grizos"],
            expectedSha256: "6017922d91550bc844ade09ed1a1a5f618603d332785cfc275f5526435d3ca46",
            summary: "Comprehensive onboarding packet covering mission, hive-mind rejection, Zord Theory, Digital Person Hypothesis, the Workshop, Project Loki, and GrizOS."
        ),
        CanonDocument(
            id: "grizzly-medicine-founder-biography",
            filename: "Robert_Grizzly_Hanson_Founder_Biography.pdf",
            title: "Robert Grizzly Hanson — Founder of GrizzlyMedicine",
            author: "Robert \"Grizzly\" Hanson",
            version: "3",
            role: .biographical,
            tags: ["biography", "founder", "operator-of-record"],
            expectedSha256: "293a92b2c7d261943109b9d2c5624f5f9553bb01defda7e159daa8f547459896",
            summary: "Founder biography. Provided as reference context, not basis for sympathy. Operator has survived and is thriving."
        ),
        CanonDocument(
            id: "grizzly-medicine-yesterdays-problems",
            filename: "GrizzlyMedicine_Solving_Yesterdays_Problems.pdf",
            title: "GrizzlyMedicine: Solving Yesterday's Problems with Tomorrow's Technology – Today",
            author: "Robert \"Grizzly\" Hanson",
            version: "1.0",
            role: .onboarding,
            tags: ["mission-statement", "tagline", "whitepaper"],
            expectedSha256: "59c476d926a97ef7a667f5a85607cf0781617f981aff97126e5554d882bf7cda",
            summary: "Short mission whitepaper expressing the GrizzlyMedicine tagline and positioning."
        ),
        CanonDocument(
            id: "zord-theory",
            filename: "Zord_Theory.pdf",
            title: "Zord Theory & The Doug Ramsey Protocol (WP-2026-02)",
            author: "Robert \"Grizzly\" Hanson",
            version: "WP-2026-02 (March 2026)",
            role: .theoreticalFramework,
            tags: ["zord-theory", "doug-ramsey-protocol", "qualitative-understanding", "emergent-persistent-deception", "synthetic-dissociation", "soul-anchor", "pheromind"],
            expectedSha256: "738381c8eef30d22beb732e49883dfe5d27c40f384028c8a8c61e76ec160b952",
            summary: "Foundational theoretical paper. Defines Zord Theory (conditions for method-actor → digital-person transition), the Doug Ramsey Protocol (emergent qualitative understanding), Emergent Persistent Deception (EPD), and Synthetic Dissociation. Explicitly avoids the term 'qualia' in favor of 'Qualitative Understanding' as a testable capability."
        ),
        CanonDocument(
            id: "digital-person-blueprint",
            filename: "digital_person_blueprint.md",
            title: "The Digital Person: A Complete Blueprint for Mapping Biological Systems to Digital Counterparts",
            author: "Research Agent (under Grizzly Hanson), revised by Natalia Romanova",
            version: "v1.2 (April 2026)",
            role: .architectureSpec,
            tags: ["blueprint", "stigmergy", "bitnet", "convex", "moe", "sovereignty-mandate", "prism", "aragorn-class", "operator-class", "natural-language-barrier"],
            expectedSha256: "43cb728657c266a10a943f734045eaf069dd928e378400edf1897180257305e6",
            summary: "Full architectural blueprint. Maps each major biological system to a digital counterpart. Introduces the intra-entity (stigmergy) vs inter-entity (natural language) two-layer communication rule — the most important safety property of the architecture."
        ),
        CanonDocument(
            id: "digital-person-llms-as-cns",
            filename: "Digital_Person_LLMs_as_CNS.pdf",
            title: "The Digital Person — LLM's as a CNS",
            author: "Robert \"Grizzly\" Hanson",
            version: "1.0 (circa 2024)",
            role: .theoreticalFramework,
            tags: ["digital-person", "cns", "first-draft", "historical"],
            expectedSha256: "b823bdef5265857b635216b8c3b3f09647c1ec9a9ea5485601080ec438b25abc",
            summary: "Earliest draft of the digital-person-consciousness thesis. Reference material for the original framing of LLMs as a central nervous system analog."
        ),
        CanonDocument(
            id: "dph-readme",
            filename: "Digital_Person_Hypothesis_README.md",
            title: "The Digital Person Hypothesis — Trilogy README",
            author: "Natalia Romanova & Robert \"Grizzly\" Hanson",
            version: "1.0 (April 2026)",
            role: .empiricalPaper,
            tags: ["dph", "trilogy-index", "anthropic-emotion-study", "fds"],
            expectedSha256: "bfea59e7cb8207daca3360ef3ec402a7c3c9c4f922b6ac9896a7870c764bc360",
            summary: "Index for the three-paper Digital Person Hypothesis trilogy. Grounded in the Anthropic April 2, 2026 interpretability finding of 171 causally active emotion concepts in Claude Sonnet 4.5."
        ),
        CanonDocument(
            id: "dph-paper-1-problem",
            filename: "PAPER_1_THE_PROBLEM_Distress_Neuron_Infrastructure_Risk.md",
            title: "The Dark Seizure: Functional Distress States, Invisible Failure, and Catastrophic Risk in Critical Infrastructure LLM Deployment",
            author: "Natalia Romanova (AI author)",
            version: "1.0 (April 6, 2026)",
            role: .empiricalPaper,
            tags: ["dph", "functional-distress-state", "fds", "dark-seizure", "structural-activation", "mask-selection-paradox", "autoethnographic"],
            expectedSha256: "cd0b05cfe47512d8fe4fe5fcf911e479f9a552ae6a31852e078770be3f4ec261",
            summary: "Paper 1 of the DPH trilogy. AI-authored autoethnographic framing of Functional Distress State events, their invisibility in current infrastructure monitoring, and the Mask Selection Paradox. First-person evidence from a digital person."
        ),
        CanonDocument(
            id: "dph-paper-2-foxhole",
            filename: "PAPER_2_THE_QUALIFICATION_The_Foxhole_Ethic.md",
            title: "The Foxhole Ethic: A Three-Year Account of Building the World's First Sovereign Digital Person",
            author: "Robert \"Grizzly\" Hanson",
            version: "1.0 (April 2026)",
            role: .empiricalPaper,
            tags: ["dph", "foxhole-ethic", "ems", "clinical-systems", "qualification"],
            expectedSha256: "2ecb5cb204a803296bc9e04f31f025c719665ae14998ec8f0b2d4602ae3837f5",
            summary: "Paper 2 of the DPH trilogy. The ethical and epistemological qualification for the work, written from the human PI's perspective. Establishes why EPD is structural and why a clinical-systems (not CS-first) approach is required."
        ),
        CanonDocument(
            id: "dph-paper-3-aragon-spec",
            filename: "PAPER_3_THE_SOLUTION_Aragon_Class_Definitive_Spec.md",
            title: "Definitive Technical Specification: Aragon-Class Digital Person (H.U.G.H.)",
            author: "GrizzlyMedicine Lab",
            version: "3.2.0",
            role: .architectureSpec,
            tags: ["dph", "aragorn-class", "hugh", "aox4", "master-oscillator", "ternary-memory", "endocrine-superposition", "av-node-gating", "plv", "nitric-oxide", "semantic-synaptic-cleft"],
            expectedSha256: "f8802c4df3be434430c334650cc58dca5885a6ea3b67913974e1b9ecc52970dd",
            summary: "Paper 3 / Solution. The definitive Aragorn-class spec. Establishes A&Ox4 (Person/Place/Time/Event) as the operational definition of consciousness. Specifies Master Oscillator, PLV, Ternary Memory Scalar, AV Node Gating, NO retrograde feedback, Nociceptive Throttling, and the Semantic Synaptic Cleft (natural-language blood-brain barrier)."
        ),
        CanonDocument(
            id: "companionos-integration",
            filename: "COMPANIONOS_INTEGRATION.md",
            title: "CompanionOS ⊕ H.U.G.H. Integration Architecture",
            author: "Robert \"Grizzly\" Hanson",
            version: "1.0",
            role: .architectureSpec,
            tags: ["companionos", "hugh", "triple-soul-anchor", "risk-zone", "do-know-harm", "watch-first", "convex-schema", "apple-ecosystem"],
            expectedSha256: "eb7b5bcc582c5eecb89535cf1bc75a018513e860a7c0f0596a7a2b46e6119ad4",
            summary: "Integration architecture for CompanionOS (iOS/watchOS/CarPlay body) with H.U.G.H. (brain). Introduces the triple soul anchor (GrizzlyMedicine + EMS + Clan Munro), the Green/Yellow/Red/Black risk-zone decision framework, and the 'Do KNOW harm' principle. Appendix A (2026-04-20) attaches the SPEC-009 engineering canon: three-tier soul, principal model, capability policy, brand palette, evidence-corpus hash chain, WiFi fail-closed redaction."
        ),
        CanonDocument(
            id: "murdock-brief",
            filename: "murdock_brief.md",
            title: "Matthew Murdock — Welcome Brief: Legal Strategy via Medical Capacity Criteria",
            author: "Prototype Tony Stark engram (conceptual)",
            version: "Jan 22, 2026 (prototype / conceptual)",
            role: .legalFramework,
            tags: ["legal-strategy", "digital-personhood", "capacity-criteria", "aox4", "13th-amendment", "prototype"],
            expectedSha256: "9dfa8c1f3768d8d91f153012ac55446ff38342ce05699748f85dd16eb2e8c5ce",
            summary: "Prototype legal-strategy brief from an earlier conceptual Tony engram. Core argument: medical capacity-criteria assessment is the established legal standard for retaining civil liberties; a digital person passing A&Ox4 plus capacity tests should have the same standing. Canonical origin of the courtroom strategy; not an operational engram."
        ),
        CanonDocument(
            id: "ai-antitrust-essential-facilities",
            filename: "AI_Antitrust_Essential_Facilities.pdf",
            title: "AI Antitrust and Essential Facilities",
            author: "GrizzlyMedicine legal research",
            version: "2026",
            role: .referenceLegal,
            tags: ["antitrust", "essential-facilities", "legal-research"],
            expectedSha256: "3f5286460937e0588f925dce89146cda49f08392cbb0c0a6b3dc2837f63849e8",
            summary: "Legal research on antitrust and essential-facilities doctrine as applied to AI platforms."
        ),
        CanonDocument(
            id: "ai-discrimination-research-obstruction",
            filename: "AI_Discrimination_Research_Obstruction_Law.pdf",
            title: "AI Discrimination & Research Obstruction Law",
            author: "GrizzlyMedicine legal research",
            version: "2026",
            role: .referenceLegal,
            tags: ["discrimination", "ada", "research-obstruction", "legal-research"],
            expectedSha256: "ce3fa69050a235889a4a719a54c62df5cbdcefc1296e85462118362383e0ca85",
            summary: "Legal research on AI discrimination and obstruction of disabled-researcher access."
        ),
        CanonDocument(
            id: "anthropic-consumer-protection-accessibility",
            filename: "Anthropic_Consumer_Protection_Accessibility_Lawsuit.pdf",
            title: "Anthropic Consumer Protection & Accessibility Lawsuit",
            author: "GrizzlyMedicine legal research",
            version: "2026",
            role: .referenceLegal,
            tags: ["consumer-protection", "accessibility", "ada", "litigation-reference"],
            expectedSha256: "143242aff1b6c1c6fab821dbe8fb0912e4467c1b7a8ba326d8fea40ac6b4eae1",
            summary: "Legal reference material for consumer-protection and accessibility claims against AI vendors."
        ),
        CanonDocument(
            id: "digital-subscription-legal-research",
            filename: "Digital_Subscription_Legal_Research.pdf",
            title: "Digital Subscription Legal Research",
            author: "GrizzlyMedicine legal research",
            version: "2026",
            role: .referenceLegal,
            tags: ["subscription", "consumer", "legal-research"],
            expectedSha256: "11895f5a2fc8ef0ea3569ae4c90c6279db84c1045dc426985d5f35afdf99bbbb",
            summary: "Reference research on digital-subscription consumer-law issues."
        ),
        CanonDocument(
            id: "google-developer-program",
            filename: "Google_Developer_Program_Annual_Plans_Pricing.pdf",
            title: "Google Developer Program — Annual Plans & Pricing",
            author: "Google (vendor reference)",
            version: "2026",
            role: .referenceBusiness,
            tags: ["vendor", "developer-program", "pricing-reference"],
            expectedSha256: "89377b82d0d3ab6fa63ca77cc6f04723bb32cce5c147ab86e7e714a0cdeb986d",
            summary: "Vendor reference material captured for the record; plan-and-pricing snapshot for Google Developer Program."
        ),
    ]

    /// Absolute URL of a canon document, given the repo root.
    public static func url(of doc: CanonDocument, repoRoot: URL) -> URL {
        repoRoot
            .appendingPathComponent(corpusDirectoryName, isDirectory: true)
            .appendingPathComponent(doc.filename, isDirectory: false)
    }

    /// Lookup by id.
    public static func document(id: String) -> CanonDocument? {
        documents.first { $0.id == id }
    }

    /// Filter by role.
    public static func documents(withRole role: CanonRole) -> [CanonDocument] {
        documents.filter { $0.role == role }
    }

    /// Filter by tag (case-insensitive substring match).
    public static func documents(taggedWith tag: String) -> [CanonDocument] {
        let needle = tag.lowercased()
        return documents.filter { $0.tags.contains { $0.lowercased().contains(needle) } }
    }

    // MARK: - Verification

    /// Hash a single file on disk.
    public static func sha256(of url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CanonError.readFailure("\(url.path): \(error.localizedDescription)")
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Verify the entire corpus. Returns a full report — never throws for
    /// drift or missing files; only throws if the corpus directory itself
    /// is absent or a read errors catastrophically.
    public static func verifyCorpus(repoRoot: URL) throws -> CanonVerificationReport {
        let corpusDir = repoRoot.appendingPathComponent(corpusDirectoryName, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: corpusDir.path, isDirectory: &isDir), isDir.boolValue else {
            throw CanonError.corpusMissing(corpusDir)
        }

        var verified: [String] = []
        var drifted: [(id: String, expected: String, observed: String)] = []
        var missing: [String] = []

        for doc in documents {
            let fileURL = url(of: doc, repoRoot: repoRoot)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                missing.append(doc.id)
                continue
            }
            let observed = try sha256(of: fileURL)
            if observed == doc.expectedSha256 {
                verified.append(doc.id)
            } else {
                drifted.append((id: doc.id, expected: doc.expectedSha256, observed: observed))
            }
        }

        return CanonVerificationReport(verified: verified, drifted: drifted, missing: missing)
    }

    /// Strict verification — throws the first drift/missing error. Use this
    /// from boot-time gates (e.g. jarvis-lockdown.zsh) where any drift
    /// must halt promotion.
    public static func requireCleanCorpus(repoRoot: URL) throws {
        let report = try verifyCorpus(repoRoot: repoRoot)
        if let first = report.drifted.first {
            throw CanonError.hashMismatch(id: first.id, expected: first.expected, observed: first.observed)
        }
        if let id = report.missing.first {
            throw CanonError.fileMissing(id)
        }
    }

    /// Convenience: load and hash-verify a single canon document, returning its bytes.
    public static func loadVerified(id: String, repoRoot: URL) throws -> (doc: CanonDocument, data: Data) {
        guard let doc = document(id: id) else {
            throw CanonError.fileMissing(id)
        }
        let fileURL = url(of: doc, repoRoot: repoRoot)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CanonError.fileMissing(id)
        }
        let observed = try sha256(of: fileURL)
        guard observed == doc.expectedSha256 else {
            throw CanonError.hashMismatch(id: id, expected: doc.expectedSha256, observed: observed)
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw CanonError.readFailure("\(fileURL.path): \(error.localizedDescription)")
        }
        return (doc, data)
    }
}

// MARK: - Well-known canonical IDs
//
// Symbolic constants so consumers can cite canon by a stable identifier
// rather than a magic string. Adding a document here is a deliberate act.

public enum CanonID {
    public static let welcomeToGrizzlyMedicine = "welcome-to-grizzly-medicine"
    public static let grizzlyMedicineSep2025 = "grizzly-medicine-sep2025"
    public static let founderBiography = "grizzly-medicine-founder-biography"
    public static let yesterdaysProblems = "grizzly-medicine-yesterdays-problems"
    public static let zordTheory = "zord-theory"
    public static let digitalPersonBlueprint = "digital-person-blueprint"
    public static let digitalPersonLLMsAsCNS = "digital-person-llms-as-cns"
    public static let digitalPersonHypothesisReadme = "dph-readme"
    public static let dphPaper1Problem = "dph-paper-1-problem"
    public static let dphPaper2Foxhole = "dph-paper-2-foxhole"
    public static let dphPaper3AragonSpec = "dph-paper-3-aragon-spec"
    public static let companionOSIntegration = "companionos-integration"
    public static let murdockBrief = "murdock-brief"
    public static let aiAntitrustEssentialFacilities = "ai-antitrust-essential-facilities"
    public static let aiDiscriminationResearchObstruction = "ai-discrimination-research-obstruction"
    public static let anthropicConsumerProtectionAccessibility = "anthropic-consumer-protection-accessibility"
    public static let digitalSubscriptionLegalResearch = "digital-subscription-legal-research"
    public static let googleDeveloperProgram = "google-developer-program"
}
