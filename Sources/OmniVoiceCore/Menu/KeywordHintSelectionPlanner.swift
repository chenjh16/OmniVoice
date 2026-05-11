import Foundation

struct KeywordHintSelectionPlan: Equatable {
    let isEnabled: Bool
    let selectedIDs: [String]
}

enum KeywordHintSelectionPlanner {
    static func toggleEnabled(isEnabled: Bool, selectedIDs currentIDs: [String], availableIDs: [String]) -> KeywordHintSelectionPlan {
        let selectedIDs = sanitizedSelectedIDs(currentIDs, availableIDs: availableIDs)
        guard isEnabled else {
            return KeywordHintSelectionPlan(isEnabled: !selectedIDs.isEmpty, selectedIDs: selectedIDs)
        }
        return KeywordHintSelectionPlan(isEnabled: false, selectedIDs: [])
    }

    static func toggleGroup(
        _ id: String,
        selectedIDs currentIDs: [String],
        availableIDs: [String] = []
    ) -> KeywordHintSelectionPlan {
        let availableIDSet = Set(availableIDs.filter(KeywordGroupValidator.isValidID))
        guard availableIDSet.isEmpty || availableIDSet.contains(id) else {
            let selectedIDs = sanitizedSelectedIDs(currentIDs, availableIDs: availableIDs)
            return KeywordHintSelectionPlan(isEnabled: !selectedIDs.isEmpty, selectedIDs: selectedIDs)
        }
        var selectedIDs = sanitizedSelectedIDs(currentIDs, availableIDs: availableIDs)

        if selectedIDs.contains(id) {
            selectedIDs.removeAll { $0 == id }
        } else if KeywordGroupValidator.isValidID(id) {
            selectedIDs.append(id)
        }

        return KeywordHintSelectionPlan(
            isEnabled: !selectedIDs.isEmpty,
            selectedIDs: selectedIDs
        )
    }

    private static func sanitizedSelectedIDs(_ currentIDs: [String], availableIDs: [String]) -> [String] {
        let availableIDSet = Set(availableIDs.filter(KeywordGroupValidator.isValidID))
        var seen: Set<String> = []
        return currentIDs.filter { candidate in
            guard KeywordGroupValidator.isValidID(candidate), !seen.contains(candidate) else {
                return false
            }
            guard availableIDSet.isEmpty || availableIDSet.contains(candidate) else {
                return false
            }
            seen.insert(candidate)
            return true
        }
    }
}
