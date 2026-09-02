import Foundation

/// Keyboard models supported by g810-led's LED protocol.
/// Ported from src/classes/Keyboard.h (GPLv3), see https://github.com/MatMoul/g810-led
public enum LogitechKeyboardModel: String, CaseIterable {
    case g213, g410, g413, g512, g513, g610, g810, g815, g910, gpro
}

public struct SupportedKeyboardEntry {
    public let vendorID: UInt16
    public let productID: UInt16
    public let model: LogitechKeyboardModel
}

public enum LogitechDevices {
    public static let logitechVendorID: UInt16 = 0x046d

    /// Ported verbatim from g810-led's `SupportedKeyboards` table
    /// (src/classes/Keyboard.h, GPLv3).
    public static let supportedKeyboards: [SupportedKeyboardEntry] = [
        .init(vendorID: 0x046d, productID: 0xc336, model: .g213),
        .init(vendorID: 0x046d, productID: 0xc330, model: .g410),
        .init(vendorID: 0x046d, productID: 0xc33a, model: .g413),
        .init(vendorID: 0x046d, productID: 0xc342, model: .g512),
        .init(vendorID: 0x046d, productID: 0xc33c, model: .g513),
        .init(vendorID: 0x046d, productID: 0xc333, model: .g610),
        .init(vendorID: 0x046d, productID: 0xc338, model: .g610),
        .init(vendorID: 0x046d, productID: 0xc331, model: .g810),
        .init(vendorID: 0x046d, productID: 0xc337, model: .g810),
        .init(vendorID: 0x046d, productID: 0xc33f, model: .g815),
        .init(vendorID: 0x046d, productID: 0xc32b, model: .g910),
        .init(vendorID: 0x046d, productID: 0xc335, model: .g910),
        .init(vendorID: 0x046d, productID: 0xc339, model: .gpro),
    ]

    public static func model(vendorID: UInt16, productID: UInt16) -> LogitechKeyboardModel? {
        supportedKeyboards.first {
            $0.vendorID == vendorID && $0.productID == productID
        }?.model
    }
}
