import Foundation
import Testing
@testable import Skincare

struct FreeScanQuotaTests {
    @Test func rollClearsAfterSevenDays() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let state = FreeScanQuota.State(periodStart: start, count: 7)
        let beforeDeadline = FreeScanQuota.rolled(
            state,
            now: start.addingTimeInterval(6 * 24 * 3600),
            windowDays: 7
        )
        #expect(beforeDeadline.count == 7)
        #expect(beforeDeadline.periodStart == start)

        let afterDeadline = FreeScanQuota.rolled(
            state,
            now: start.addingTimeInterval(7 * 24 * 3600),
            windowDays: 7
        )
        #expect(afterDeadline.count == 0)
        #expect(afterDeadline.periodStart == nil)
    }

    @Test func rollWithNoPeriodIsZero() {
        let rolled = FreeScanQuota.rolled(
            .init(periodStart: nil, count: 3),
            now: Date(),
            windowDays: 7
        )
        #expect(rolled.count == 0)
        #expect(rolled.periodStart == nil)
    }
}
