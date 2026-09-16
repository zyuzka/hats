import Foundation
@testable import Hats

final class FakeKeychain {
    var contents: [String: Data]
    var readFailures: Set<String> = []
    var failReadsAfter: Int?
    var writeFailures: Set<String> = []
    var deleteFailures: Set<String> = []
    var swallowsWrites = false
    var listFailure: Error?

    var reads: [String] = []
    var writes: [(service: String, data: Data)] = []
    var deletes: [String] = []

    private var readCounts: [String: Int] = [:]

    init(_ contents: [String: Data] = [:]) { self.contents = contents }

    func world() -> KeychainWorld {
        KeychainWorld(
            read: { [self] service in try self.reading(service) },
            write: { [self] service, data in try self.writing(service, data) },
            delete: { [self] service in try self.deleting(service) },
            parkedAccountIDs: { [self] in try self.listing() }
        )
    }

    private func reading(_ service: String) throws -> Data? {
        reads.append(service)
        if readFailures.contains(service) {
            throw KeychainError(operation: "read \(service)", detail: "interaction not allowed")
        }
        readCounts[service, default: 0] += 1
        if let after = failReadsAfter, readCounts[service, default: 0] > after {
            throw KeychainError(operation: "read \(service)", detail: "interaction not allowed")
        }

        return contents[service]
    }

    private func writing(_ service: String, _ data: Data) throws {
        writes.append((service, data))
        if writeFailures.contains(service) {
            throw KeychainError(operation: "write \(service)", detail: "the keychain is locked")
        }
        guard !swallowsWrites else { return }
        contents[service] = data
    }

    private func deleting(_ service: String) throws {
        deletes.append(service)
        if deleteFailures.contains(service) {
            throw KeychainError(operation: "delete \(service)", detail: "the keychain is locked")
        }
        contents.removeValue(forKey: service)
    }

    private func listing() throws -> [String] {
        if let listFailure { throw listFailure }
        let prefixes = [Slot.parked(""), Slot.legacyParked("")]
        var ids: Set<String> = []
        for service in contents.keys {
            guard let prefix = prefixes.first(where: { service.hasPrefix($0) }) else { continue }
            let id = String(service.dropFirst(prefix.count))
            if !id.isEmpty { ids.insert(id) }
        }

        return Array(ids)
    }
}
