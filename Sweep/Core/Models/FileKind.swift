import SwiftUI
import UniformTypeIdentifiers

/// Rough classification of files, used for colors and filters.
enum FileKind: String, CaseIterable, Identifiable, Sendable {
    case video, image, audio, archive, diskImage, installer, document, application, other

    var id: String { rawValue }

    init(url: URL) {
        let ext = url.pathExtension.lowercased()
        if ext == "app" { self = .application; return }
        if ["pkg", "mpkg"].contains(ext) { self = .installer; return }
        if ["dmg", "iso", "img", "sparseimage", "sparsebundle", "vmdk", "qcow2", "vdi"].contains(ext) { self = .diskImage; return }
        guard let type = UTType(filenameExtension: ext) else { self = .other; return }
        if type.conforms(to: .movie) || type.conforms(to: .video) { self = .video }
        else if type.conforms(to: .image) { self = .image }
        else if type.conforms(to: .audio) { self = .audio }
        else if type.conforms(to: .archive) || ["zip", "rar", "7z", "tar", "gz", "xz", "bz2", "tgz"].contains(ext) { self = .archive }
        else if type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .presentation)
                    || type.conforms(to: .spreadsheet) || type.conforms(to: .compositeContent) { self = .document }
        else if type.conforms(to: .application) || type.conforms(to: .applicationBundle) { self = .application }
        else { self = .other }
    }

    var title: String {
        switch self {
        case .video: "Videos"
        case .image: "Bilder"
        case .audio: "Audio"
        case .archive: "Archive"
        case .diskImage: "Disk-Images"
        case .installer: "Installer"
        case .document: "Dokumente"
        case .application: "Programme"
        case .other: "Sonstige"
        }
    }

    var symbol: String {
        switch self {
        case .video: "film"
        case .image: "photo"
        case .audio: "waveform"
        case .archive: "doc.zipper"
        case .diskImage: "externaldrive"
        case .installer: "shippingbox"
        case .document: "doc.richtext"
        case .application: "app.dashed"
        case .other: "doc"
        }
    }

    var color: Color {
        switch self {
        case .video: Color(red: 0.62, green: 0.42, blue: 0.86)
        case .image: Color(red: 0.92, green: 0.45, blue: 0.58)
        case .audio: Color(red: 0.25, green: 0.70, blue: 0.70)
        case .archive: Color(red: 0.80, green: 0.58, blue: 0.32)
        case .diskImage: Color(red: 0.42, green: 0.55, blue: 0.70)
        case .installer: Color(red: 0.55, green: 0.50, blue: 0.82)
        case .document: Color(red: 0.36, green: 0.62, blue: 0.90)
        case .application: Color(red: 0.45, green: 0.45, blue: 0.85)
        case .other: Color(red: 0.55, green: 0.58, blue: 0.62)
        }
    }
}
