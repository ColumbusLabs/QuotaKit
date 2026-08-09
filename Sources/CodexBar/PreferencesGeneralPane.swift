import AppKit
import CodexBarCore
import SwiftUI

enum PreferredCurrencyOption: String, CaseIterable, Identifiable {
    case auto
    case usd = "USD"
    case gbp = "GBP"
    case eur = "EUR"
    case cny = "CNY"
    case jpy = "JPY"
    case krw = "KRW"
    case cad = "CAD"
    case aud = "AUD"
    case hkd = "HKD"
    case twd = "TWD"
    case sgd = "SGD"
    case inr = "INR"

    var id: String {
        self.rawValue
    }

    var label: String {
        switch self {
        case .auto: L("currency_auto")
        case .usd: "USD ($)"
        case .gbp: "GBP (£)"
        case .eur: "EUR (€)"
        case .cny: "CNY (¥)"
        case .jpy: "JPY (¥)"
        case .krw: "KRW (₩)"
        case .cad: "CAD ($)"
        case .aud: "AUD ($)"
        case .hkd: "HKD ($)"
        case .twd: "TWD (NT$)"
        case .sgd: "SGD ($)"
        case .inr: "INR (₹)"
        }
    }
}

@MainActor
struct GeneralPane: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                SettingsMenuPicker(
                    selection: self.$settings.preferredCurrencyCode,
                    options: PreferredCurrencyOption.allCases.map(\.rawValue),
                    label: {
                        SettingsRowLabel(L("currency_title"), subtitle: L("currency_subtitle"))
                    },
                    optionLabel: { rawValue in
                        Text(verbatim: PreferredCurrencyOption(rawValue: rawValue)?.label ?? rawValue)
                    })
                    .onChange(of: self.settings.preferredCurrencyCode) { _, newValue in
                        guard CurrencyExchange.requiresLiveRates(preferredCurrencyCode: newValue) else { return }
                        Task {
                            let ratesChanged = await CurrencyExchange.shared.fetchLatestRatesIfNeeded(
                                preferredCurrencyCode: newValue)
                            if ratesChanged {
                                NotificationCenter.default.post(
                                    name: .codexbarCurrencyExchangeRatesDidChange,
                                    object: nil)
                            }
                        }
                    }

                SettingsMenuPicker(
                    selection: self.$settings.terminalApp,
                    options: GeneralSettingsMenuOptions.terminalApps(selected: self.settings.terminalApp),
                    label: {
                        SettingsRowLabel(L("terminal_app_title"), subtitle: L("terminal_app_subtitle"))
                    },
                    optionLabel: { option in
                        HStack(spacing: 6) {
                            if let icon = option.pickerIcon {
                                Image(nsImage: icon)
                            }
                            Text(option.label)
                        }
                    })

                Toggle(L("start_at_login_title"), isOn: self.$settings.launchAtLogin)
            } header: {
                Text(L("section_system"))
            }

            Section {
                SettingsMenuPicker(
                    selection: self.$settings.refreshFrequency,
                    options: GeneralSettingsMenuOptions.refreshFrequencies,
                    label: { Text(L("refresh_interval_title")) },
                    optionLabel: { option in Text(option.label) })

                Toggle(L("refresh_on_open_title"), isOn: self.$settings.refreshAllProvidersOnMenuOpen)

                Toggle(isOn: self.$settings.backgroundWorkLowPowerModeEnabled) {
                    SettingsRowLabel(
                        L("Low Power Mode"),
                        subtitle: L(
                            "Runs automatic provider, local usage, and storage refreshes no more often than every " +
                                "30 minutes. Manual refresh remains available."))
                }

                Toggle(isOn: self.$settings.statusChecksEnabled) {
                    SettingsRowLabel(
                        L("check_provider_status_title"),
                        subtitle: L("check_provider_status_subtitle"))
                }
            } header: {
                Text(L("section_refreshing"))
            } footer: {
                if self.settings.refreshFrequency == .manual {
                    SettingsSectionFooter(L("manual_refresh_hint"))
                }
            }

            Section {
                LabeledContent(L("open_menu_shortcut_title")) {
                    OpenMenuShortcutRecorder()
                }
            } header: {
                Text(L("section_keyboard_shortcut"))
            }

            Section {
                HStack {
                    Spacer()
                    Button(L("quit_app")) { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .scrollContentBackground(.hidden)
        .background(FocusResigningBackground())
    }
}
