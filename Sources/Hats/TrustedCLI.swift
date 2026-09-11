import Foundation
import Security

enum TrustedCLI {
    static let requirementText = "identifier \"com.anthropic.claude-code\" "
        + "and anchor apple generic "
        + "and certificate leaf[subject.OU] = Q6L2SF6YDW"

    static let requirement: SecRequirement? = {
        var compiled: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &compiled)
                == errSecSuccess else { return nil }
        return compiled
    }()

    static func isTheRealCLI(pid: Int32) -> Bool? {
        guard let requirement else { return nil }
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
