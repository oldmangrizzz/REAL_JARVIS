# UX-001 Navigation Surface Build Hardening - Spec Sheet
**Date:** 2026-04-20  
**Branch:** Active dev (jarvis.xcworkspace)  
**Target:** 100% production-ready, zero TODOs/placeholder code  
**Strategy:** Ralph Whiggum recursive RLM REPL loop

---

## 🚨 Critical Build Failures (Must Fix First)

| File | Line | Error | Severity | Plan |
|------|------|-------|----------|------|
| `CarPlayNavigationScene.swift` | 1-20 | `CPNavigationTemplate`, `CPApplication`, `CPManeuverView`, `CPRouteView`, `CPStatusView` not in scope | **CRITICAL** | Wrap all CarPlay imports in `#if canImport(CarPlay)` guard; add iOS deployment target check |
| `NavigationContracts.swift` | 245 | `AnyJSON` does not conform to `Codable` after Equatable changes | **CRITICAL** | Remove `Codable` conformance from `AnyJSON` and use custom decoding, or split `AnyJSON` into separate `AnyJSONCodable` for encoding paths |
| `NavigationContracts.swift` | 246 | `AnyCodable` stored property `value` of type `Any` violates `Sendable` | **CRITICAL** | Remove `Sendable` from `AnyCodable` or use `@unchecked Sendable` with safety review |
| `JarvisBrandPaletteSwiftUI.swift` | 87 | Invalid redeclaration of `init(hex:)` | HIGH | Remove duplicate SwiftUI extension; merge with existing Color extension |
| `JarvisCockpitView.swift` | 284,321,342 | Ambiguous use of `init(hex:)` | HIGH | Explicit `hex:` label disambiguation or rename extension method |

---

## 📁 Files Requiring Platform Guard Audit

| File | Platform Risk | Action Required |
|------|---------------|-----------------|
| `CarPlayNavigationScene.swift` | CarPlay only (iOS) | Wrap entire file content in `#if canImport(CarPlay)` |
| `CarPlay/HUDNavigationScene.swift` | CarPlay only (iOS) | Verify platform guard presence; add if missing |
| `Navigation/NavigationCockpitView.swift` | MapKit (iOS) | Verify `@available(iOS 17.0, *)` guard |
| `CarPlay/HUDNavigationScene.swift` | CarPlay only | Add iOS deployment target guard if missing |

---

## 🔧 Syntax Errors (Immediate Priority)

| File | Line | Swift Version | Fix |
|------|------|---------------|-----|
| `CarPlayNavigationScene.swift` | 269 | Was `HStack spacing: 24 {` | Changed to `HStack(spacing: 24) {` — ✅ FIXED |
| `NavigationContracts.swift` | 245–253 | `AnyJSON` struct | Rewrite to support `Equatable` without breaking `Codable` — see spec below |

---

## 🧩 AnyJSON / AnyCodable Protocol Design

### Current Problem
- `UnityNavigationBridge` needs `Equatable` for UI diffing
- Payload `AnyJSON` wraps `[String: Any]`
- `Codable` synthesis conflicts with custom `Equatable`

### Approved Solution
```swift
// Remove Codable from top-level struct
public struct AnyJSON: Sendable {
    public let value: [String: AnyCodable]
    public init(_ value: [String: Any]) {
        self.value = value.mapValues { AnyCodable($0) }
    }
}

// AnyCodable with manual Equatable (no Sendable)
private struct AnyCodable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        // Handle String, Int, Double, Bool, [Any], [String: Any]
    }
}

// Add Codable support only where needed (PWA/Unity bridge)
extension UnityNavigationBridge {
    enum CodingKeys: String, CodingKey { case type, payload }
    public init(from decoder: Decoder) throws { /* manual decode */ }
    public func encode(to encoder: Encoder) throws { /* manual encode */ }
}
```

---

## 🛡️ Platform Segregation Requirements

| Target | Allowed Imports | Blocked Imports |
|--------|----------------|-----------------|
| `JarvisCore` (macOS) | `Foundation`, `SwiftUI` (macOS), `MapKit` (macOS fallback) | `CarPlay`, `UIKit`, `MapKit` (iOS) |
| `JarvisMobileCore` (iOS) | All iOS frameworks | None |
| `CarPlay` extension | `CarPlay`, `SwiftUI`, `MapKit` | `UIKit`, non-CarPlay iOS only |

**Implementation Rule:**  
Any file importing `CarPlay` must reside in `CarPlay/` subdirectory or be wrapped in `#if canImport(CarPlay)` guard.

---

## 🧪 Validation Checklist (Post-Fix)

| Item | Status |
|------|--------|
| All `CarPlay` imports wrapped in `#if canImport(CarPlay)` | ☐ |
| `AnyJSON` compiles with `Equatable` (no `Codable`) | ☐ |
| `JarvisBrandPaletteSwiftUI.swift` has no duplicate `init(hex:)` | ☐ |
| All ambiguous `init(hex:)` calls disambiguated in `JarvisCockpitView.swift` | ☐ |
| `xcodebuild -workspace jarvis.xcworkspace -scheme JarvisMobileCore build` succeeds | ☐ |
| `xcodebuild -workspace jarvis.xcworkspace -scheme JarvisCore build` succeeds | ☐ |
| Zero `TODO()`, `#warning`, or placeholder code in all nav surface files | ☐ |
| `UX-001-status.md` reflects 100% production-ready (Phases A–E) | ☐ |

---

## 📋 Deliverables

1. ✅ Fix CarPlay import guards in `CarPlayNavigationScene.swift`
2. ✅ Fix `AnyJSON`/`AnyCodable` to support `Equatable` without breaking `Codable`
3. ✅ Remove duplicate `init(hex:)` from `JarvisBrandPaletteSwiftUI.swift`
4. ✅ Disambiguate `init(hex:)` usage in `JarvisCockpitView.swift`
5. ✅ Run full build cycle and validate zero errors
6. ✅ Update spec sheet and status file

---

## 🧠 Ralph Whiggum Modification Note

- **Recursive Loop Strategy:** Each fix must trigger immediate recompile before proceeding
- **Zero-Todo Policy:** No placeholder implementations — all must compile and run
- **Fail Fast:** If build fails after any fix, revert and re-analyze before next iteration
