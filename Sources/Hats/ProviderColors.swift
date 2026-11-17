import AppKit

enum ProviderColors {
    static let claude = dynamic(light: 0xD97757, dark: 0xE8957A)
    static let codex = dynamic(light: 0x5C6370, dark: 0x9AA1AD)

    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return srgb(isDark ? dark : light)
        }
    }

    static func srgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Tool {
    var hatColor: NSColor {
        switch self {
        case .claudeCode: return ProviderColors.claude
        }
    }
}
