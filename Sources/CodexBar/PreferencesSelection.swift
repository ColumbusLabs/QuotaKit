import Foundation
import Observation

@MainActor
@Observable
final class PreferencesSelection {
    var tab: PreferencesTab = .general
}
