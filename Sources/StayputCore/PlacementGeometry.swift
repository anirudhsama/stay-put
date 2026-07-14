import CoreGraphics

public enum PlacementGeometry {
    public static func frame(
        for placement: WindowPlacement,
        visibleFrame: CGRect,
        centeredSize: CGSize
    ) -> CGRect {
        let width = min(max(centeredSize.width, 240), visibleFrame.width)
        let height = min(max(centeredSize.height, 160), visibleFrame.height)

        switch placement {
        case .leftHalf:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: visibleFrame.width / 2,
                height: visibleFrame.height
            ).integral
        case .rightHalf:
            return CGRect(
                x: visibleFrame.midX,
                y: visibleFrame.minY,
                width: visibleFrame.width / 2,
                height: visibleFrame.height
            ).integral
        case .center:
            return CGRect(
                x: visibleFrame.midX - width / 2,
                y: visibleFrame.midY - height / 2,
                width: width,
                height: height
            ).integral
        }
    }
}
