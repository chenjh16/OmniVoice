import AppKit
import Foundation

struct PasteboardSnapshot {
    struct Item {
        let entries: [(NSPasteboard.PasteboardType, Data)]
    }

    let items: [Item]
    var itemCount: Int { items.count }
    var typeCount: Int { items.reduce(0) { $0 + $1.entries.count } }

    static func capture() -> PasteboardSnapshot {
        let items = NSPasteboard.general.pasteboardItems?.map { item in
            Item(entries: item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            })
        } ?? []
        return PasteboardSnapshot(items: items)
    }

    @discardableResult
    func restore() -> Bool {
        NSPasteboard.general.clearContents()
        let restored = items.map { saved in
            let item = NSPasteboardItem()
            for (type, data) in saved.entries {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restored.isEmpty {
            return NSPasteboard.general.writeObjects(restored)
        }
        return true
    }
}
