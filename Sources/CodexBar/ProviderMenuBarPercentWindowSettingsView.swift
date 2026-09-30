import CodexBarCore
import SwiftUI

/// Per-provider picker for the menu bar metric and percent window.
///
/// Window choices write a provider layout override so they survive changes to the global layout.
/// Monthly Plan writes the existing per-provider metric preference.
@MainActor
struct ProviderMenuBarPercentWindowSettingsView: View {
    let provider: UsageProvider
    @Bindable var settings: SettingsStore

    var body: some View {
        ProviderMenuBarPercentWindowPicker(
            provider: self.provider,
            iconStyle: self.settings.menuBarIconStyle,
            layout: self.layoutBinding,
            metric: self.metricBinding)
    }

    var layoutBinding: Binding<MenuBarLayout> {
        Binding(
            get: { self.settings.menuBarLayoutResolution(for: self.provider).layout },
            set: { self.settings.setMenuBarLayout($0, for: self.provider) })
    }

    var metricBinding: Binding<MenuBarMetricPreference> {
        Binding(
            get: { self.settings.menuBarMetricPreference(for: self.provider) },
            set: { self.settings.setMenuBarMetricPreference($0, for: self.provider) })
    }
}

@MainActor
struct ProviderMenuBarPercentWindowPicker: View {
    let provider: UsageProvider
    let iconStyle: MenuBarIconStyle
    @Binding var layout: MenuBarLayout
    var metric: Binding<MenuBarMetricPreference> = .constant(.automatic)

    var body: some View {
        let layout = self.layout
        let available = MenuBarPercentWindowPreference.available(for: self.provider, layout: layout)
        if MenuBarPercentWindowPreference.isVisible(
            iconStyle: self.iconStyle,
            layout: layout,
            available: available)
        {
            let selection = self.selectionBinding.wrappedValue
            Section {
                Picker(L("menu_bar_metric_title"), selection: self.selectionBinding) {
                    if selection == nil {
                        // Mixed windows are only describable in the layout editor; surface that
                        // state instead of pretending one option is selected.
                        Text(L("menu_bar_layout_preset_custom"))
                            .tag(MenuBarPercentWindowPreference?.none)
                    }
                    ForEach(available) { preference in
                        Text(preference.label(for: self.provider)).tag(MenuBarPercentWindowPreference?.some(preference))
                    }
                }
                .pickerStyle(.menu)
                .listRowSeparator(.hidden)
            } footer: {
                SettingsSectionFooter(L("menu_bar_metric_subtitle"))
            }
            .background(FocusResigningBackground())
        }
    }

    var selectionBinding: Binding<MenuBarPercentWindowPreference?> {
        Binding(
            get: {
                let layout = self.layout
                let available = MenuBarPercentWindowPreference.available(for: self.provider, layout: layout)
                let metric = available.contains(.monthlyPlan) ? self.metric.wrappedValue : nil
                return MenuBarPercentWindowPreference.current(in: layout, metric: metric)
                    .flatMap { available.contains($0) ? $0 : nil }
            },
            set: { preference in
                let layout = self.layout
                let available = MenuBarPercentWindowPreference.available(for: self.provider, layout: layout)
                guard let preference, available.contains(preference) else { return }

                let updated = preference.applied(to: layout)
                if MenuBarPercentWindowPreference.available(for: self.provider).contains(.monthlyPlan) {
                    self.metric.wrappedValue = preference.menuBarMetric
                    // Without a percent token, the metric is the only value this picker controls.
                    // Avoid pinning a copy of the current global layout at provider scope.
                    guard MenuBarPercentWindowPreference.hasPercentToken(in: layout) else { return }
                }
                self.layout = updated
            })
    }
}
