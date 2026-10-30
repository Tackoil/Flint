import CoreGraphics
import Testing
@testable import FlintCore

struct LauncherPlacementTests {
    private let expandedSize = CGSize(width: 760, height: 560)

    @Test func collapsedBarUsesTheTopOfTheCenteredExpandedPanel() {
        let placement = LauncherPlacement(visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                          expandedSize: expandedSize)
        #expect(placement.expandedFrame == CGRect(x: 340, y: 170, width: 760, height: 560))
        #expect(placement.frame(height: 56) == CGRect(x: 340, y: 674, width: 760, height: 56))
    }

    @Test func reversingAtIntermediateHeightsNeverMovesTheSearchAnchor() {
        let placement = LauncherPlacement(visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                          expandedSize: expandedSize)
        for height: CGFloat in [56, 56.5, 200.25, 232, 560, 320.5, 232, 56, 120.75, 560, 56] {
            let frame = placement.frame(height: height)
            #expect(frame.minX == 340)
            #expect(frame.maxY == 730)
        }
    }

    @Test func secondaryDisplayCoordinatesIncludeItsOriginAndVisibleArea() {
        let placement = LauncherPlacement(visibleFrame: CGRect(x: -1920, y: 80, width: 1920, height: 1080),
                                          expandedSize: expandedSize)
        #expect(placement.frame(height: 56) == CGRect(x: -1340, y: 844, width: 760, height: 56))
    }

    @Test func reopeningOnAnotherDisplayCreatesANewAnchor() {
        let first = LauncherPlacement(visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                      expandedSize: expandedSize)
        let second = LauncherPlacement(visibleFrame: CGRect(x: 1440, y: 100, width: 1920, height: 1080),
                                       expandedSize: expandedSize)
        #expect(first.frame(height: 56).minX == 340)
        #expect(second.frame(height: 56) == CGRect(x: 2020, y: 864, width: 760, height: 56))
    }

    @Test func compactQRCodeKeepsTheSameWidthAndSearchAnchor() {
        let placement = LauncherPlacement(visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                          expandedSize: expandedSize)
        let mode = LauncherDisplayMode.qrCode
        let frame = placement.frame(height: mode.height)
        #expect(frame == CGRect(x: 340, y: 330, width: 760, height: 400))
        #expect(frame.maxY == placement.expandedFrame.maxY)
        #expect(frame.midX == placement.expandedFrame.midX)
        #expect(placement.frame(height: LauncherDisplayMode.collapsed.height).width == 760)
    }
}
