import SwiftUI
import AppKit
import LogilightsCore

extension LogitechColor {
    var swiftUIColor: Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }

    /// `#rrggbb`, for showing the exact value the device will receive.
    var hexString: String {
        String(format: "#%02x%02x%02x", red, green, blue)
    }

    init(_ color: Color) {
        let rgb = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        self.init(
            red: UInt8((rgb.redComponent * 255).rounded().clamped(to: 0...255)),
            green: UInt8((rgb.greenComponent * 255).rounded().clamped(to: 0...255)),
            blue: UInt8((rgb.blueComponent * 255).rounded().clamped(to: 0...255))
        )
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
