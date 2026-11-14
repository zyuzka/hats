import Darwin
import Foundation

enum SessionWindowState: String, Equatable {
    case read
    case compacted
}

struct SessionWindow: Equatable {
    let session: String
    let cwd: String?
    let title: String?
    let tokens: Int?
    let window: Int?
    let percent: Int?
    let state: SessionWindowState
    let measuredAt: Date

    static let folderName = "session-windows"

    static func getPercent(tokens: Int, window: Int) -> Int {
        let share = Double(tokens) / Double(window) * 100
        let floor = share.rounded(.down)
        let rounded = share - floor >= 0.5 ? floor + 1 : floor

        return Int(min(100, max(0, rounded)))
    }
}

enum SessionWindowRead: Equatable {
    case read(SessionWindow)
    case skipped(String)
}

enum SessionWindowFile {
    static let sizeCap = 64 * 1024
    static let sessionPattern = "^[A-Za-z0-9-]{1,80}$"

    static func getRecord(_ name: String, in folder: URL) -> SessionWindowRead {
        let descriptor = open(folder.appendingPathComponent(name).path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            return .skipped(errno == ELOOP ? "it is a link" : String(cString: strerror(errno)))
        }
        defer { close(descriptor) }
        var facts = stat()
        guard fstat(descriptor, &facts) == 0 else { return .skipped(String(cString: strerror(errno))) }
        guard facts.st_mode & S_IFMT == S_IFREG else { return .skipped("it is not a regular file") }
        guard let data = getBytesUpToTheCap(descriptor) else { return .skipped("it could not be read") }
        guard data.count <= sizeCap else { return .skipped("it is larger than 64 KB") }

        return getRecord(parsing: data, name: name)
    }

    static func getBytesUpToTheCap(_ descriptor: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while data.count <= sizeCap {
            let count = Darwin.read(
                descriptor,
                &buffer,
                buffer.count
            )
            guard count >= 0 else { return nil }
            guard count > 0 else { break }
            data.append(contentsOf: buffer[0..<count])
        }
        return data
    }

    static func getRecord(parsing data: Data, name: String) -> SessionWindowRead {
        guard let raw = try? JSONDecoder().decode(SessionWindowFields.self, from: data) else {
            return .skipped("it is not a session window record")
        }
        guard raw.session.range(of: sessionPattern, options: .regularExpression) != nil,
              name == raw.session + ".json"
        else { return .skipped("its name is not its session") }
        guard let state = SessionWindowState(rawValue: raw.state) else { return .skipped("its state is unknown") }
        guard let measuredAt = UsageReading.date(from: raw.measuredAt) else {
            return .skipped("measured_at is not a time")
        }
        if let trouble = findTroubleWithTheNumbers(raw, state: state) { return .skipped(trouble) }

        return .read(SessionWindow(
            session: raw.session,
            cwd: raw.cwd,
            title: raw.title,
            tokens: raw.tokens,
            window: raw.window,
            percent: raw.percent,
            state: state,
            measuredAt: measuredAt
        ))
    }

    private static func findTroubleWithTheNumbers(_ raw: SessionWindowFields, state: SessionWindowState) -> String? {
        guard state == .read else {
            let hasNoNumbers = raw.tokens == nil && raw.window == nil && raw.percent == nil
            return hasNoNumbers ? nil : "a compacted session carries numbers"
        }
        guard let tokens = raw.tokens, tokens >= 0 else { return "tokens are missing or negative" }
        guard let window = raw.window else {
            return raw.percent == nil ? nil : "a percent without a window"
        }
        guard window > 0 else { return "the window is not positive" }
        guard let percent = raw.percent, (0...100).contains(percent) else { return "the percent is outside 0…100" }

        return percent == SessionWindow.getPercent(tokens: tokens, window: window)
            ? nil
            : "the percent does not match tokens and window"
    }
}

private struct SessionWindowFields: Decodable {
    let session: String
    let cwd: String?
    let title: String?
    let tokens: Int?
    let window: Int?
    let percent: Int?
    let state: String
    let measuredAt: String

    enum CodingKeys: String, CodingKey {
        case session
        case cwd
        case title
        case tokens
        case window
        case percent
        case state
        case measuredAt = "measured_at"
    }
}
