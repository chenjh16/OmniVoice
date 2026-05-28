import Foundation

public struct ExternalASRSettings: Equatable, Sendable {
    public let providerID: String?

    public init(providerID: String? = nil) {
        self.providerID = Self.sanitizedProviderID(providerID)
    }

    public static let defaultSettings = ExternalASRSettings()

    public static func sanitizedProviderID(_ value: String?) -> String? {
        guard let value = value?.nilIfBlank,
              isValidProviderID(value) else {
            return nil
        }
        return value
    }

    public static func isValidProviderID(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }
}
