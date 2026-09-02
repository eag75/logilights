import Foundation

/// Addressing groups used by the Logitech G-series LED protocol.
/// Ported from g810-led's `KeyAddressGroup` (src/classes/Keyboard.h, GPLv3).
enum KeyAddressGroup: UInt8 {
    case logo = 0x00
    case indicators
    case multimedia
    case gkeys
    case keys
}

/// Every individually addressable key/LED across the supported keyboard models.
/// The raw value's high byte encodes the `KeyAddressGroup`, the low byte the
/// in-group index used on the wire. Ported 1:1 from g810-led's `Key` enum
/// (src/classes/Keyboard.h, GPLv3) so device behavior matches upstream exactly.
public enum LogitechKey: UInt16 {
    case logo = 0x0001
    case logo2

    case backlight = 0x0101
    case game, caps, scroll, num

    case next = 0x02b5
    case prev, stop
    case play = 0x02cd
    case mute = 0x02e2

    case g1 = 0x0301
    case g2, g3, g4, g5, g6, g7, g8, g9

    case a = 0x0404
    case b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z
    case n1, n2, n3, n4, n5, n6, n7, n8, n9, n0
    case enter, esc, backspace, tab, space, minus, equal, openBracket, closeBracket
    case backslash, dollar, semicolon, quote, tilde, comma, period, slash, capsLock
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    case printScreen, scrollLock, pauseBreak, insert, home, pageUp, del, end, pageDown
    case arrowRight, arrowLeft, arrowBottom, arrowTop, numLock, numSlash, numAsterisk
    case numMinus, numPlus, numEnter
    case num1, num2, num3, num4, num5, num6, num7, num8, num9, num0
    case numDot, intlBackslash, menu

    case abntSlash = 0x0487

    case ctrlLeft = 0x04e0
    case shiftLeft, altLeft, winLeft
    case ctrlRight, shiftRight, altRight, winRight

    /// The `KeyAddressGroup` this key belongs to, derived from the raw value's high byte.
    var addressGroup: KeyAddressGroup {
        KeyAddressGroup(rawValue: UInt8(rawValue >> 8))!
    }

    /// The in-group wire index (low byte of the raw value).
    var groupIndex: UInt8 {
        UInt8(rawValue & 0x00ff)
    }
}

/// Named key groups, matching g810-led's `keyGroup*` constants
/// (src/classes/Keyboard.cpp, GPLv3).
enum LogitechKeyGroups {
    static let logo: [LogitechKey] = [.logo, .logo2]
    static let indicators: [LogitechKey] = [.caps, .num, .scroll, .game, .backlight]
    static let multimedia: [LogitechKey] = [.next, .prev, .stop, .play, .mute]
    static let gkeys: [LogitechKey] = [.g1, .g2, .g3, .g4, .g5, .g6, .g7, .g8, .g9]
    static let fkeys: [LogitechKey] = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]
    static let modifiers: [LogitechKey] = [
        .shiftLeft, .ctrlLeft, .winLeft, .altLeft,
        .altRight, .winRight, .ctrlRight, .shiftRight, .menu
    ]
    static let functions: [LogitechKey] = [
        .esc, .printScreen, .scrollLock, .pauseBreak,
        .insert, .del, .home, .end, .pageUp, .pageDown
    ]
    static let arrows: [LogitechKey] = [.arrowTop, .arrowLeft, .arrowBottom, .arrowRight]
    static let numeric: [LogitechKey] = [
        .num1, .num2, .num3, .num4, .num5,
        .num6, .num7, .num8, .num9, .num0,
        .numDot, .numEnter, .numPlus, .numMinus,
        .numAsterisk, .numSlash, .numLock
    ]
    static let keys: [LogitechKey] = [
        .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m,
        .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z,
        .n1, .n2, .n3, .n4, .n5, .n6, .n7, .n8, .n9, .n0,
        .enter, .backspace, .tab, .space, .minus, .equal,
        .openBracket, .closeBracket, .backslash, .dollar, .semicolon, .quote, .tilde,
        .comma, .period, .slash, .capsLock, .intlBackslash, .abntSlash
    ]

    /// All keys in the same order g810-led's `setAllKeys` assembles them.
    static func all() -> [LogitechKey] {
        logo + indicators + multimedia + gkeys + fkeys + functions + arrows + numeric + modifiers + keys
    }
}
