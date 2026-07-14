import CoreGraphics
import Foundation
import Testing
@testable import StayputCore

@Test func migratesRulesWithoutRestoreFlags() throws {
    let data = Data(#"{"id":"070496C6-631C-4DBE-B351-08C6EA06B30D","bundleIdentifier":"notion.id","applicationName":"Notion","placement":"center","centeredWidth":1200,"centeredHeight":800}"#.utf8)
    let rule = try JSONDecoder().decode(WindowRule.self, from: data)

    #expect(rule.restoreSize)
    #expect(rule.restorePosition)
}

@Test func preservesIndependentRestoreFlags() throws {
    let original = WindowRule(
        bundleIdentifier: "notion.id",
        applicationName: "Notion",
        placement: .center,
        centeredWidth: 1200,
        centeredHeight: 800,
        restoreSize: true,
        restorePosition: false
    )
    let decoded = try JSONDecoder().decode(WindowRule.self, from: JSONEncoder().encode(original))

    #expect(decoded == original)
}

@Test func centersAndPreservesSize() {
    let frame = PlacementGeometry.frame(
        for: .center,
        visibleFrame: .init(x: 0, y: 40, width: 1440, height: 860),
        centeredSize: .init(width: 900, height: 600)
    )

    #expect(frame == .init(x: 270, y: 170, width: 900, height: 600))
}

@Test func clampsCenteredWindowsToTheDisplay() {
    let frame = PlacementGeometry.frame(
        for: .center,
        visibleFrame: .init(x: 0, y: 25, width: 800, height: 575),
        centeredSize: .init(width: 1200, height: 900)
    )

    #expect(frame == .init(x: 0, y: 25, width: 800, height: 575))
}

@Test func fillsDisplayHalves() {
    let visible = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let size = CGSize(width: 800, height: 600)

    #expect(PlacementGeometry.frame(for: .leftHalf, visibleFrame: visible, centeredSize: size) ==
        .init(x: -1920, y: 0, width: 960, height: 1080))
    #expect(PlacementGeometry.frame(for: .rightHalf, visibleFrame: visible, centeredSize: size) ==
        .init(x: -960, y: 0, width: 960, height: 1080))
}
