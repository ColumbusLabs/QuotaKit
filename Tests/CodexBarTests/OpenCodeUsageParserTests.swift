import Foundation
import Testing
@testable import CodexBarCore

@Suite
struct OpenCodeUsageParserTests {
    @Test
    func parsesWorkspaceIDs() {
        let text = ";0x00000089;((self.$R=self.$R||{})[\"codexbar\"]=[]," +
            "($R=>$R[0]=[$R[1]={id:\"wrk_01K6AR1ZET89H8NB691FQ2C2VB\",name:\"Default\",slug:null}])" +
            "($R[\"codexbar\"]))"
        let ids = OpenCodeUsageFetcher.parseWorkspaceIDs(text: text)
        #expect(ids == ["wrk_01K6AR1ZET89H8NB691FQ2C2VB"])
    }

    @Test
    func parsesSubscriptionUsage() throws {
        let text = "$R[16]($R[30],$R[41]={rollingUsage:$R[42]={status:\"ok\",resetInSec:5944,usagePercent:17}," +
            "weeklyUsage:$R[43]={status:\"ok\",resetInSec:278201,usagePercent:75}});"
        let now = Date(timeIntervalSince1970: 0)
        let snapshot = try OpenCodeUsageFetcher.parseSubscription(text: text, now: now)
        #expect(snapshot.rollingUsagePercent == 17)
        #expect(snapshot.weeklyUsagePercent == 75)
        #expect(snapshot.rollingResetInSec == 5944)
        #expect(snapshot.weeklyResetInSec == 278_201)
    }
}
