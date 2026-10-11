import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var viewModel = OnboardingViewModel()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    switch viewModel.page {
                    case .welcome: welcome
                    case .safety: safety
                    case .access: FullDiskAccessGuide()
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(viewModel.page)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            Divider()
            footer
                .padding(16)
        }
        .frame(width: 640, height: 600)
        .animation(Theme.spring, value: viewModel.page)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                ModuleIcon(module: .smartScan, size: 64)
                VStack(alignment: .leading) {
                    Text("Willkommen bei Sweep")
                        .font(.largeTitle.weight(.semibold))
                    Text("Ein ruhiger, ehrlicher Helfer für mehr Platz auf deinem Mac.")
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                feature(.junk, "Caches, Logs und Entwickler-Reste aufräumen")
                feature(.uninstaller, "Apps samt aller Reste deinstallieren oder zurücksetzen")
                feature(.spaceMap, "Sehen, wo dein Speicherplatz hingeht")
                feature(.duplicates, "Doppelte, große und alte Dateien finden")
                feature(.malware, "Verdächtige Autostarts und Erweiterungen erkennen")
            }
        }
    }

    private var safety: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Sicherheit zuerst")
                .font(.largeTitle.weight(.semibold))
            Text("Sweep geht mit deinen Daten vorsichtig um. Diese Regeln gelten immer:")
                .foregroundStyle(.secondary)
            SafetyPromises()
        }
    }

    private func feature(_ module: SweepModule, _ text: String) -> some View {
        HStack(spacing: 12) {
            ModuleIcon(module: module, size: 30)
            Text(text).font(.body)
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(OnboardingViewModel.Page.allCases, id: \.self) { page in
                    Capsule()
                        .fill(page == viewModel.page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: page == viewModel.page ? 18 : 7, height: 7)
                }
            }
            Spacer()
            if !viewModel.isFirstPage {
                Button("Zurück") { viewModel.back() }
            }
            if viewModel.isLastPage {
                Button(model.permissions.hasFullDiskAccess ? "Los geht’s" : "Später erteilen") {
                    model.completeOnboarding()
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Weiter") { viewModel.next() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
    }
}
