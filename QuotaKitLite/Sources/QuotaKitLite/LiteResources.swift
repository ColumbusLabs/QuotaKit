import AppKit

/// Provider logos copied from the full app (068 §7.2). `Scripts/install.sh` puts them in the
/// app bundle's `Contents/Resources`, so they load from `Bundle.main`.
enum LiteResources {
    static func templateIcon(named name: String, pointSize: CGFloat = 16) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.size = NSSize(width: pointSize, height: pointSize)
        image.isTemplate = true
        return image
    }
}
