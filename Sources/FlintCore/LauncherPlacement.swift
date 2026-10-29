import CoreGraphics

enum LauncherDisplayMode {
    case collapsed, calculator, results

    var height: CGFloat {
        switch self {
        case .collapsed: return 56
        case .calculator: return 232
        case .results: return 560
        }
    }
}

struct LauncherPlacement {
    let expandedFrame: CGRect

    init(visibleFrame: CGRect, expandedSize: CGSize) {
        expandedFrame = CGRect(
            x: visibleFrame.midX - expandedSize.width / 2,
            y: visibleFrame.midY - expandedSize.height / 2,
            width: expandedSize.width,
            height: expandedSize.height
        )
    }

    func frame(height: CGFloat) -> CGRect {
        CGRect(x: expandedFrame.minX, y: expandedFrame.maxY - height,
               width: expandedFrame.width, height: height)
    }
}
