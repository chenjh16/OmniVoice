import Foundation

struct ModelsResponse: Decodable, Sendable {
    struct Model: Decodable, Sendable {
        let id: String
    }

    let data: [Model]
}
