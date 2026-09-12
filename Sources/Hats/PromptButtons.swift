import Foundation

enum PromptButtons {
    static func leftToRight(_ titles: [String]) -> [(index: Int, title: String)] {
        titles.enumerated().map { (index: $0.offset, title: $0.element) }.reversed()
    }

    static func isDefault(_ index: Int, of count: Int) -> Bool { index == 0 }

    static func isCancel(_ index: Int, of count: Int) -> Bool { index == count - 1 }

    static func dismissed(of count: Int) -> Int { count - 1 }
}
