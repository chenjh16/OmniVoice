import Foundation

enum IdentifierValidator {
    static let maximumLength = 48
    static let pattern = #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#

    static func isValid(
        _ value: String,
        reservedValues: Set<String> = [],
        disallowedValues: Set<String> = []
    ) -> Bool {
        guard let trimmed = value.nilIfBlank,
              trimmed.count <= maximumLength,
              !reservedValues.contains(trimmed),
              !disallowedValues.contains(trimmed) else {
            return false
        }
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}
