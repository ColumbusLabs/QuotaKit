import SwiftUI

/// Single source of truth for provider-card tint colors.
///
/// The raw swatches mirror the Mac `ProviderDescriptorRegistry` branding
/// colors. `color(for:)` returns an appearance-adaptive tint so very dark or
/// very light brand colors stay visible on iOS surfaces.
enum ProviderColorPalette {
    struct RawColor: Equatable {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color {
            Color(uiColor: UIColor { traits in
                let adapted = self.adaptedComponents(forDarkMode: traits.userInterfaceStyle == .dark)
                return UIColor(
                    red: adapted.red,
                    green: adapted.green,
                    blue: adapted.blue,
                    alpha: 1)
            })
        }

        private var luminance: Double {
            0.2126 * self.red + 0.7152 * self.green + 0.0722 * self.blue
        }

        func adaptedComponents(forDarkMode isDarkMode: Bool) -> RawColor {
            if isDarkMode {
                if self.luminance < 0.08 {
                    return self.mixed(with: RawColor(red: 1, green: 1, blue: 1), amount: 0.40)
                }
                if self.luminance < 0.14 {
                    return self.mixed(with: RawColor(red: 1, green: 1, blue: 1), amount: 0.44)
                }
                if self.luminance < 0.22 {
                    return self.mixed(with: RawColor(red: 1, green: 1, blue: 1), amount: 0.21)
                }
            }
            if !isDarkMode, self.luminance > 0.82 {
                return self.mixed(with: RawColor(red: 0, green: 0, blue: 0), amount: 0.42)
            }
            return self
        }

        private func mixed(with other: RawColor, amount: Double) -> RawColor {
            RawColor(
                red: self.red + (other.red - self.red) * amount,
                green: self.green + (other.green - self.green) * amount,
                blue: self.blue + (other.blue - self.blue) * amount)
        }
    }

    static func color(for providerIdentifier: String) -> Color {
        (self.rawColor(for: providerIdentifier) ?? self.fallback).color
    }

    static func rawColor(for providerIdentifier: String) -> RawColor? {
        self.palette[self.normalized(providerIdentifier)]
    }

    static func normalized(_ value: String) -> String {
        String(value
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) })
    }

    private static let fallback = RawColor(red: 0, green: 122 / 255, blue: 1)

    private static let palette: [String: RawColor] = {
        let entries: [(aliases: [String], color: RawColor)] = [
            (["codex"], RawColor(red: 73 / 255, green: 163 / 255, blue: 176 / 255)),
            (["claude"], RawColor(red: 204 / 255, green: 124 / 255, blue: 94 / 255)),
            (["cursor"], RawColor(red: 0, green: 0, blue: 0)),
            (["grok"], RawColor(red: 26 / 255, green: 26 / 255, blue: 26 / 255)),
        ]

        var table: [String: RawColor] = [:]
        for entry in entries {
            for alias in entry.aliases {
                table[Self.normalized(alias)] = entry.color
            }
        }
        return table
    }()
}
