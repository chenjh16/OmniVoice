import Foundation

public enum JSONCNormalizer {
    public static func normalize(_ input: String) -> String {
        removeTrailingCommas(from: removeComments(from: input))
    }

    public static func removeComments(from input: String) -> String {
        var output = ""
        var index = input.startIndex
        var inString = false
        var escaping = false
        while index < input.endIndex {
            let char = input[index]
            let next = input.index(after: index)
            if inString {
                output.append(char)
                if escaping {
                    escaping = false
                } else if char == "\\" {
                    escaping = true
                } else if char == "\"" {
                    inString = false
                }
                index = next
                continue
            }
            if char == "\"" {
                inString = true
                output.append(char)
                index = next
                continue
            }
            if char == "/", next < input.endIndex {
                let nextChar = input[next]
                if nextChar == "/" {
                    index = input.index(after: next)
                    while index < input.endIndex, input[index] != "\n" {
                        index = input.index(after: index)
                    }
                    if index < input.endIndex {
                        output.append("\n")
                        index = input.index(after: index)
                    }
                    continue
                }
                if nextChar == "*" {
                    index = input.index(after: next)
                    while index < input.endIndex {
                        let blockNext = input.index(after: index)
                        if input[index] == "*", blockNext < input.endIndex, input[blockNext] == "/" {
                            index = input.index(after: blockNext)
                            break
                        }
                        index = blockNext
                    }
                    continue
                }
            }
            output.append(char)
            index = next
        }
        return output
    }

    public static func removeTrailingCommas(from input: String) -> String {
        var output = ""
        var index = input.startIndex
        var inString = false
        var escaping = false
        while index < input.endIndex {
            let char = input[index]
            if inString {
                output.append(char)
                if escaping {
                    escaping = false
                } else if char == "\\" {
                    escaping = true
                } else if char == "\"" {
                    inString = false
                }
                index = input.index(after: index)
                continue
            }
            if char == "\"" {
                inString = true
                output.append(char)
                index = input.index(after: index)
                continue
            }
            if char == "," {
                var lookahead = input.index(after: index)
                while lookahead < input.endIndex, input[lookahead].isWhitespace {
                    lookahead = input.index(after: lookahead)
                }
                if lookahead < input.endIndex, (input[lookahead] == "}" || input[lookahead] == "]") {
                    index = input.index(after: index)
                    continue
                }
            }
            output.append(char)
            index = input.index(after: index)
        }
        return output
    }
}

extension URL {
    var normalizedMimoBaseURL: URL? {
        MimoConfig.normalizedBaseURL(from: absoluteString)
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension ConfigLoader {
    func readJSONObject(url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        let stripped = JSONCNormalizer.normalize(raw)
        guard let jsonData = stripped.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        return object
    }
}
