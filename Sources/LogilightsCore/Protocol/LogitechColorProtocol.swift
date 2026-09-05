import Foundation

/// A raw HID Output report to send to the keyboard.
/// `reportID` is also the report's first byte (Logitech's own convention).
public struct HIDOutputReport: Equatable {
    public let reportID: UInt8
    public let bytes: [UInt8]

    public init(reportID: UInt8, bytes: [UInt8]) {
        self.reportID = reportID
        self.bytes = bytes
    }
}

/// Pure byte-encoding logic for setting a single solid color across an entire
/// keyboard, ported from g810-led's `LedKeyboard::setAllKeys` /
/// `LedKeyboard::setKeys` / `LedKeyboard::commit` / `LedKeyboard::getKeyGroupAddress`
/// (src/classes/Keyboard.cpp, GPLv3 — https://github.com/MatMoul/g810-led).
///
/// No hardware/IOKit access happens here, which keeps this fully unit-testable.
/// Reports use HID Output report type (not Feature) and are written with
/// `IOHIDDeviceSetReport(_:kIOHIDReportTypeOutput:...)` by `LightingApplier`.
public enum LogitechColorProtocol {

    /// Builds the ordered list of Output reports to send in order to set
    /// `color` across the whole keyboard, followed by a commit report if the
    /// model requires one (the commit report, if any, is the last element).
    public static func setAllKeysReports(model: LogitechKeyboardModel, color: LogitechColor) -> [HIDOutputReport] {
        var reports: [HIDOutputReport]
        switch model {
        case .g213:
            reports = g213Reports(color: color)
        case .g413:
            reports = g413Reports(color: color)
        case .g815:
            reports = g815Reports(color: color)
        case .g410, .g512, .g513, .g610, .g810, .g910, .gpro:
            reports = defaultReports(model: model, color: color)
        }
        if let commit = commitReport(model: model) {
            reports.append(commit)
        }
        return reports
    }

    /// Ported from `LedKeyboard::commit`. Returns nil for models that are
    /// non-transactional (g213, g413) and therefore need no commit report.
    public static func commitReport(model: LogitechKeyboardModel) -> HIDOutputReport? {
        var bytes: [UInt8]
        switch model {
        case .g213, .g413:
            return nil
        case .g410, .g512, .g513, .g610, .g810, .gpro:
            bytes = [0x11, 0xff, 0x0c, 0x5a]
        case .g815:
            bytes = [0x11, 0xff, 0x10, 0x7f]
        case .g910:
            bytes = [0x11, 0xff, 0x0f, 0x5d]
        }
        return pad(&bytes, to: 20)
    }

    // MARK: - g213 (region-based, no per-key addressing)

    /// Ported from `LedKeyboard::setAllKeys` (g213 branch) + `setRegion`.
    private static func g213Reports(color: LogitechColor) -> [HIDOutputReport] {
        (0x01...0x05).map { region -> HIDOutputReport in
            var bytes: [UInt8] = [0x11, 0xff, 0x0c, 0x3a, UInt8(region), 0x01, color.red, color.green, color.blue]
            return pad(&bytes, to: 20)
        }
    }

    // MARK: - g413 (single native "color" effect packet)

    /// Ported from `LedKeyboard::setAllKeys` (g413 branch) via `setNativeEffect`
    /// with effect = color, part = keys, period = 0, storage = none.
    private static func g413Reports(color: LogitechColor) -> [HIDOutputReport] {
        var bytes: [UInt8] = [
            0x11, 0xff, 0x0c, 0x3c,
            0x00, // NativeEffectPart::keys
            0x01, // NativeEffectGroup::color
            color.red, color.green, color.blue,
            0x00, 0x00, // breathing period
            0x00, 0x00, // cycle period
            0x00,       // wave variation
            0x64,       // unused
            0x00,       // wave period (high byte)
            0x00,       // NativeEffectStorage::none
            0x00, 0x00, 0x00,
        ]
        return [pad(&bytes, to: 20)]
    }

    // MARK: - Default per-key protocol (g410, g512, g513, g610, g810, g910, gpro)

    private struct GroupAddress {
        let reportID: UInt8
        let header: [UInt8] // full 8-byte header including reportID, or empty if unsupported
        let dataSize: Int
    }

    /// Ported from `LedKeyboard::getKeyGroupAddress`.
    private static func groupAddress(model: LogitechKeyboardModel, group: KeyAddressGroup) -> GroupAddress? {
        let header: [UInt8]
        let dataSize: Int
        switch (model, group) {
        case (.g410, .logo), (.g512, .logo), (.g513, .logo), (.gpro, .logo),
             (.g610, .logo), (.g810, .logo):
            header = [0x11, 0xff, 0x0c, 0x3a, 0x00, 0x10, 0x00, 0x01]; dataSize = 20
        case (.g910, .logo):
            header = [0x11, 0xff, 0x0f, 0x3a, 0x00, 0x10, 0x00, 0x02]; dataSize = 20
        case (_, .indicators):
            header = [0x12, 0xff, 0x0c, 0x3a, 0x00, 0x40, 0x00, 0x05]; dataSize = 64
        case (.g610, .multimedia), (.g810, .multimedia):
            // gpro's setKeys() *does* bucket multimedia keys (same rule as
            // g610/g810), but g810-led's getKeyGroupAddress returns an empty
            // header for gpro's multimedia group, so no report is ever sent.
            // We reproduce that net effect by not matching gpro here — the
            // caller's `guard let address = ... else continue` then skips it.
            header = [0x12, 0xff, 0x0c, 0x3a, 0x00, 0x02, 0x00, 0x05]; dataSize = 64
        case (.g910, .gkeys):
            header = [0x12, 0xff, 0x0f, 0x3e, 0x00, 0x04, 0x00, 0x09]; dataSize = 64
        case (.g910, .keys):
            header = [0x12, 0xff, 0x0f, 0x3d, 0x00, 0x01, 0x00, 0x0e]; dataSize = 64
        case (_, .keys):
            header = [0x12, 0xff, 0x0c, 0x3a, 0x00, 0x01, 0x00, 0x0e]; dataSize = 64
        default:
            return nil // group not addressable on this model
        }
        return GroupAddress(reportID: header[0], header: header, dataSize: dataSize)
    }

    /// Ported from the `default:` branch of `LedKeyboard::setKeys`, which
    /// re-sorts `LedKeyboard::setAllKeys`'s flat key list into up to 5
    /// per-group buckets, applying model-specific inclusion/limit rules,
    /// then emits one or more reports per non-empty bucket.
    private static func defaultReports(model: LogitechKeyboardModel, color: LogitechColor) -> [HIDOutputReport] {
        var buckets: [KeyAddressGroup: [LogitechKey]] = [:]

        func include(_ key: LogitechKey, in group: KeyAddressGroup, limit: Int) {
            let current = buckets[group, default: []]
            if current.count <= limit {
                buckets[group, default: []].append(key)
            }
        }

        for key in LogitechKeyGroups.all() {
            switch key.addressGroup {
            case .logo:
                switch model {
                case .g610, .g810, .gpro:
                    if key == .logo { include(key, in: .logo, limit: 1) }
                case .g910:
                    include(key, in: .logo, limit: 2)
                default:
                    break
                }
            case .indicators:
                include(key, in: .indicators, limit: 5)
            case .multimedia:
                switch model {
                case .g610, .g810, .gpro:
                    include(key, in: .multimedia, limit: 5)
                default:
                    break
                }
            case .gkeys:
                switch model {
                case .g910:
                    include(key, in: .gkeys, limit: 9)
                default:
                    break
                }
            case .keys:
                switch model {
                case .g512, .g513, .g610, .g810, .g910, .gpro:
                    include(key, in: .keys, limit: 120)
                case .g410:
                    if key.rawValue < LogitechKey.numLock.rawValue || key.rawValue > LogitechKey.numDot.rawValue {
                        include(key, in: .keys, limit: 120)
                    }
                default:
                    break
                }
            }
        }

        var reports: [HIDOutputReport] = []
        for group: KeyAddressGroup in [.logo, .indicators, .multimedia, .gkeys, .keys] {
            guard let keys = buckets[group], !keys.isEmpty else { continue }
            guard let address = groupAddress(model: model, group: group) else { continue }

            let maxKeyCount = (address.dataSize - 8) / 4
            var index = 0
            while index < keys.count {
                var bytes = address.header
                let chunk = keys[index..<min(index + maxKeyCount, keys.count)]
                for key in chunk {
                    bytes.append(key.groupIndex)
                    bytes.append(color.red)
                    bytes.append(color.green)
                    bytes.append(color.blue)
                }
                reports.append(pad(&bytes, to: address.dataSize))
                index += maxKeyCount
            }
        }
        return reports
    }

    // MARK: - g815 (keys grouped by color, custom per-key address bytes)

    /// Ported from the g815 branch of `LedKeyboard::setKeys`. Since we only
    /// ever set a single solid color here, all applicable keys form one
    /// color group, chunked into packets of up to 13 keys.
    private static func g815Reports(color: LogitechColor) -> [HIDOutputReport] {
        let keys = LogitechKeyGroups.all().compactMap { g815Address(for: $0) }
        let maxKeyPerColor = 13

        var reports: [HIDOutputReport] = []
        var index = 0
        while index < keys.count {
            var bytes: [UInt8] = [0x11, 0xff, 0x10, 0x6c, color.red, color.green, color.blue]
            let chunk = keys[index..<min(index + maxKeyPerColor, keys.count)]
            bytes.append(contentsOf: chunk)
            reports.append(pad(&bytes, to: 20))
            index += maxKeyPerColor
        }
        return reports
    }

    /// Ported from the inner key-address `switch` in the g815 branch of
    /// `LedKeyboard::setKeys`. Returns nil for keys g815 doesn't expose an
    /// individual LED address for (matching upstream, which silently omits
    /// them rather than sending a placeholder byte).
    private static func g815Address(for key: LogitechKey) -> UInt8? {
        switch key {
        case .logo2, .game, .caps, .scroll, .num, .stop, .g6, .g7, .g8, .g9:
            return nil
        case .play:
            return 0x9b
        case .mute:
            return 0x9c
        case .next:
            return 0x9d
        case .prev:
            return 0x9e
        case .ctrlLeft, .shiftLeft, .altLeft, .winLeft,
             .ctrlRight, .shiftRight, .altRight, .winRight:
            return key.groupIndex &- 0x78
        default:
            switch key.addressGroup {
            case .logo:
                return key.groupIndex &+ 0xd1
            case .indicators:
                return key.groupIndex &+ 0x98
            case .gkeys:
                return key.groupIndex &+ 0xb3
            case .keys:
                return key.groupIndex &- 0x03
            case .multimedia:
                return nil
            }
        }
    }

    // MARK: - Helpers

    @discardableResult
    private static func pad(_ bytes: inout [UInt8], to size: Int) -> HIDOutputReport {
        if bytes.count < size {
            bytes.append(contentsOf: repeatElement(0x00, count: size - bytes.count))
        }
        return HIDOutputReport(reportID: bytes[0], bytes: bytes)
    }
}
