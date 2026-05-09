import Foundation

public struct ModelsResponse: Decodable, Sendable {
    public struct Model: Decodable, Sendable {
        public let id: String
    }

    public let data: [Model]
}

public enum ModelFiltering {
    public static func allowedSpeechModelIDs(from response: ModelsResponse) -> [String] {
        AllowedSpeechModel.filterSpeechModels(from: response.data.map(\.id)).map(\.rawValue)
    }
}
