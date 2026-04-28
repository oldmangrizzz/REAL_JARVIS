import CryptoKit
import Foundation
#if os(iOS)
import UIKit
#endif

public enum JarvisDeviceRole: String, Codable, CaseIterable, Sendable {
    case phone
    case tablet
    case watch
    case macDesktop
}

public struct JarvisHostConfiguration: Sendable {
    public let hostAddress: String
    public let hostPort: UInt16
    public let convexURL: URL
    public let sharedSecret: String
    public let convexAuthToken: String?
    public let tunnelConfigurationError: String?

    public var canConnectTunnel: Bool {
        tunnelConfigurationError == nil
    }

    public static func load(from bundle: Bundle = .main, role: JarvisDeviceRole) -> JarvisHostConfiguration {
        let hostAddress = bundle.object(forInfoDictionaryKey: "JARVIS_HOST_ADDRESS") as? String ?? "127.0.0.1"
        let hostPortString = bundle.object(forInfoDictionaryKey: "JARVIS_HOST_PORT") as? String ?? "9443"
        let convexString = bundle.object(forInfoDictionaryKey: "JARVIS_CONVEX_URL") as? String ?? "https://real-jarvis.convex.site"
        let authToken = bundle.object(forInfoDictionaryKey: "JARVIS_CONVEX_AUTH_TOKEN") as? String
        let configuredSecret = bundle.object(forInfoDictionaryKey: "JARVIS_SHARED_SECRET") as? String

        let trimmedSecret = configuredSecret?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPlaceholderSecret = trimmedSecret == nil
            || trimmedSecret == ""
            || trimmedSecret == "SET_VIA_BUILD_CONFIG"
            || trimmedSecret == "$(JARVIS_SHARED_SECRET)"
        let trimmedHost = hostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = hostPortString.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPlaceholderHost = trimmedHost.isEmpty
            || trimmedHost == "127.0.0.1"
            || trimmedHost == "localhost"
            || trimmedHost.hasPrefix("$(")
        let hasPlaceholderPort = trimmedPort.isEmpty || trimmedPort.hasPrefix("$(")

        let configurationError: String?
        if hasPlaceholderSecret {
            configurationError = "JARVIS_SHARED_SECRET must be injected before tunnel audio/control can connect."
        } else if hasPlaceholderHost {
            configurationError = "JARVIS_HOST_ADDRESS must be a real reachable host before tunnel audio/control can connect."
        } else if hasPlaceholderPort || UInt16(trimmedPort) == nil {
            configurationError = "JARVIS_HOST_PORT must be injected as a valid port before tunnel audio/control can connect."
        } else {
            configurationError = nil
        }

        #if DEBUG
        if hasPlaceholderSecret {
            NSLog("[JarvisHostConfiguration] WARNING: Shared secret is placeholder/empty; using debug-only derived tunnel secret.")
        }
        let resolvedPort = UInt16(trimmedPort) ?? 9443
        let seed = hasPlaceholderSecret
            ? derivedSecret(bundle: bundle, address: hostAddress, port: hostPortString, role: role)
            : trimmedSecret!
        #else
        let resolvedPort = UInt16(trimmedPort) ?? 9443
        let seed = hasPlaceholderSecret
            ? derivedSecret(bundle: bundle, address: hostAddress, port: hostPortString, role: role)
            : trimmedSecret!
        #endif

        return JarvisHostConfiguration(
            hostAddress: hostAddress,
            hostPort: resolvedPort,
            convexURL: URL(string: convexString) ?? URL(string: "https://real-jarvis.convex.site")!,
            sharedSecret: seed,
            convexAuthToken: authToken,
            tunnelConfigurationError: configurationError
        )
    }

    private static func derivedSecret(bundle: Bundle, address: String, port: String, role: JarvisDeviceRole) -> String {
        let material = "\(bundle.bundleIdentifier ?? "ai.realjarvis")|\(address)|\(port)|\(role.rawValue)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return Data(digest).base64EncodedString()
    }
}

public enum JarvisDeviceIdentity {
    public static func registration(role: JarvisDeviceRole, bundle: Bundle = .main) -> JarvisClientRegistration {
        let defaults = UserDefaults.standard
        let key = "jarvis.mobile.device-id.\(role.rawValue)"
        let deviceID = defaults.string(forKey: key) ?? {
            let generated = UUID().uuidString
            defaults.set(generated, forKey: key)
            return generated
        }()

        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"

        #if os(iOS)
        let idiomName: String = {
            switch UIDevice.current.userInterfaceIdiom {
            case .pad:
                return "iPadOS"
            case .phone:
                return "iOS"
            default:
                return "iOS"
            }
        }()
        let name = UIDevice.current.name
        #elseif os(watchOS)
        let idiomName = "watchOS"
        let name = "Jarvis Watch"
        #else
        let idiomName = "Apple"
        let name = Host.current().localizedName ?? "Jarvis Device"
        #endif

        return JarvisClientRegistration(
            deviceID: deviceID,
            deviceName: name,
            platform: idiomName,
            role: role.rawValue,
            appVersion: version
        )
    }
}
