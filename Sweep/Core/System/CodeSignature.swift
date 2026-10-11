import Foundation
import Security

/// Reads the code signature of an executable or bundle without running it.
enum CodeSignature {
    enum Status: Equatable, Sendable {
        case apple
        case developer(team: String?, signer: String?)
        case adHoc
        case unsigned
        case invalid
        case missing

        var isTrustworthy: Bool {
            switch self {
            case .apple, .developer: true
            default: false
            }
        }

        var description: String {
            switch self {
            case .apple: "Von Apple signiert"
            case .developer(let team, let signer): "Signiert: \(signer ?? team ?? "Entwickler")"
            case .adHoc: "Nur lokal (ad hoc) signiert"
            case .unsigned: "Nicht signiert"
            case .invalid: "Signatur ungültig oder beschädigt"
            case .missing: "Datei fehlt"
            }
        }
    }

    static func check(_ url: URL) -> Status {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let code = staticCode else {
            return .unsigned
        }
        let flags = SecCSFlags(rawValue: kSecCSDoNotValidateResources)
        let validity = SecStaticCodeCheckValidity(code, flags, nil)
        if validity == errSecCSUnsigned { return .unsigned }
        guard validity == errSecSuccess else { return .invalid }

        var requirement: SecRequirement?
        if SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess,
           let requirement, SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess {
            return .apple
        }

        var information: CFDictionary?
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        let info = information as? [String: Any] ?? [:]
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        guard let leaf = certificates.first else { return .adHoc }
        let signer = SecCertificateCopySubjectSummary(leaf) as String?
        return .developer(team: team, signer: signer)
    }
}
