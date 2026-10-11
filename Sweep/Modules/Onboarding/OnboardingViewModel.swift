import Foundation
import Observation

@Observable
@MainActor
final class OnboardingViewModel {
    enum Page: Int, CaseIterable {
        case welcome, safety, access
    }

    var page: Page = .welcome

    var isLastPage: Bool { page == Page.allCases.last }
    var isFirstPage: Bool { page == Page.allCases.first }

    func next() {
        guard let next = Page(rawValue: page.rawValue + 1) else { return }
        page = next
    }

    func back() {
        guard let previous = Page(rawValue: page.rawValue - 1) else { return }
        page = previous
    }
}
