import Foundation

/// An @unchecked Sendable wrapper for `[String: Any]` dictionaries.
///
/// Swift 6 considers `[String: Any]` non-Sendable because `Any` is not
/// constrained to Sendable. In practice, Jarvis bridges pass only
/// JSON-serializable values through these dictionaries, so crossing
/// concurrency boundaries is safe. This wrapper opts into Sendable
/// without runtime enforcement — use only where the payload is known
/// to contain value-type or otherwise Sendable contents.
public struct UnsafeSendableDict: @unchecked Sendable {
    public let value: [String: Any]

    public init(_ value: [String: Any]) {
        self.value = value
    }
}

/// An @unchecked Sendable wrapper for `[[String: Any]]` arrays.
///
/// Same rationale as `UnsafeSendableDict` — bridges return arrays of
/// JSON dictionaries which are safe to cross concurrency boundaries
/// in practice.
public struct UnsafeSendableDictArray: @unchecked Sendable {
    public let value: [[String: Any]]

    public init(_ value: [[String: Any]]) {
        self.value = value
    }
}