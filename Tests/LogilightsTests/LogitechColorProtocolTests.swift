import XCTest
@testable import LogilightsCore

final class LogitechColorProtocolTests: XCTestCase {

    private let red = LogitechColor(red: 0xff, green: 0x00, blue: 0x00)

    // MARK: - g213

    func testG213SendsFiveRegionReportsAndNoCommit() {
        let reports = LogitechColorProtocol.setAllKeysReports(model: .g213, color: red)
        XCTAssertEqual(reports.count, 5)
        for (index, report) in reports.enumerated() {
            let region = UInt8(index + 1)
            XCTAssertEqual(report.reportID, 0x11)
            XCTAssertEqual(report.bytes.count, 20)
            XCTAssertEqual(Array(report.bytes.prefix(9)),
                            [0x11, 0xff, 0x0c, 0x3a, region, 0x01, 0xff, 0x00, 0x00])
            XCTAssertTrue(report.bytes.dropFirst(9).allSatisfy { $0 == 0x00 })
        }
        XCTAssertNil(LogitechColorProtocol.commitReport(model: .g213))
    }

    // MARK: - g413

    func testG413SendsSingleNativeColorEffectPacket() {
        let reports = LogitechColorProtocol.setAllKeysReports(model: .g413, color: red)
        XCTAssertEqual(reports.count, 1)
        let report = reports[0]
        XCTAssertEqual(report.bytes.count, 20)
        XCTAssertEqual(Array(report.bytes.prefix(9)),
                        [0x11, 0xff, 0x0c, 0x3c, 0x00, 0x01, 0xff, 0x00, 0x00])
        XCTAssertNil(LogitechColorProtocol.commitReport(model: .g413))
    }

    // MARK: - g810 (default per-key protocol)

    func testG810CommitReport() {
        let commit = LogitechColorProtocol.commitReport(model: .g810)
        XCTAssertEqual(commit?.bytes, [0x11, 0xff, 0x0c, 0x5a] + Array(repeating: 0x00, count: 16))
    }

    func testG810IncludesLogoIndicatorsMultimediaAndKeysButNoGKeys() {
        let reports = LogitechColorProtocol.setAllKeysReports(model: .g810, color: red)
        XCTAssertFalse(reports.isEmpty)

        // Last report must be the commit report.
        XCTAssertEqual(reports.last, LogitechColorProtocol.commitReport(model: .g810))

        let reportIDs = Set(reports.dropLast().map(\.reportID))
        XCTAssertTrue(reportIDs.contains(0x11)) // logo (short report)
        XCTAssertTrue(reportIDs.contains(0x12)) // indicators/multimedia/keys (long report)

        // The logo report is the short (20-byte) one addressed at 0x0c/0x3a/0x10.
        let logoReport = reports.first { $0.bytes.count == 20 && $0.bytes[0] == 0x11 }
        XCTAssertNotNil(logoReport)
        XCTAssertEqual(Array(logoReport!.bytes.prefix(8)),
                        [0x11, 0xff, 0x0c, 0x3a, 0x00, 0x10, 0x00, 0x01])
        // Logo key group index is 0x01 (LogitechKey.logo groupIndex).
        XCTAssertEqual(Array(logoReport!.bytes[8...11]), [0x01, 0xff, 0x00, 0x00])
    }

    func testG910GetsGKeysGroupButG810DoesNot() {
        let g910Reports = LogitechColorProtocol.setAllKeysReports(model: .g910, color: red)
        let g810Reports = LogitechColorProtocol.setAllKeysReports(model: .g810, color: red)

        func containsGKeysHeader(_ reports: [HIDOutputReport]) -> Bool {
            reports.contains { $0.bytes.count >= 8 && Array($0.bytes.prefix(4)) == [0x12, 0xff, 0x0f, 0x3e] }
        }

        XCTAssertTrue(containsGKeysHeader(g910Reports))
        XCTAssertFalse(containsGKeysHeader(g810Reports))
    }

    // MARK: - g815 (color-grouped protocol)

    func testG815ChunksKeysInGroupsOfThirteenAndSkipsUnaddressableKeys() {
        let reports = LogitechColorProtocol.setAllKeysReports(model: .g815, color: red)
        XCTAssertFalse(reports.isEmpty)

        // Last report must be g815's own commit report.
        XCTAssertEqual(reports.last?.bytes, [0x11, 0xff, 0x10, 0x7f] + Array(repeating: 0x00, count: 16))

        for report in reports.dropLast() {
            XCTAssertEqual(report.bytes.count, 20)
            XCTAssertEqual(Array(report.bytes.prefix(7)), [0x11, 0xff, 0x10, 0x6c, 0xff, 0x00, 0x00])
        }
    }

    // MARK: - Cross-model sanity

    func testAllModelsProduceAtLeastOneReport() {
        for model in LogitechKeyboardModel.allCases {
            let reports = LogitechColorProtocol.setAllKeysReports(model: model, color: red)
            XCTAssertFalse(reports.isEmpty, "\(model) produced no reports")
            for report in reports {
                XCTAssertTrue(report.bytes.count == 20 || report.bytes.count == 64,
                               "\(model) produced a report of unexpected size \(report.bytes.count)")
                XCTAssertEqual(report.bytes.first, report.reportID)
            }
        }
    }
}
