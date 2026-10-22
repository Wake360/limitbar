import SwiftUI

extension Provider {
    var displayName: String { rawValue.capitalized }

    nonisolated var nsIcon: NSImage {
        let url = Bundle.module.url(forResource: rawValue, withExtension: "svg", subdirectory: "Resources/Icons")
        guard let url, let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil) ?? NSImage()
        }
        image.isTemplate = true
        return image
    }

    var icon: Image { Image(nsImage: nsIcon) }
}
