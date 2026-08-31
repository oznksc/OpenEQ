import SwiftUI

struct GraphWirePath {
    static func bezier(from: CGPoint, to: CGPoint) -> Path {
        var path = Path()
        path.move(to: from)
        let dx = max(36, abs(to.x - from.x) * 0.45)
        let c1 = CGPoint(x: from.x + dx, y: from.y)
        let c2 = CGPoint(x: to.x - dx, y: to.y)
        path.addCurve(to: to, control1: c1, control2: c2)
        return path
    }

    static func hitTest(from: CGPoint, to: CGPoint, point: CGPoint, tolerance: CGFloat = 8) -> Bool {
        let samples = 20
        var previous = from
        for i in 1...samples {
            let t = CGFloat(i) / CGFloat(samples)
            let current = pointOnCurve(from: from, to: to, t: t)
            if distanceToSegment(point, previous, current) <= tolerance {
                return true
            }
            previous = current
        }
        return false
    }

    private static func pointOnCurve(from: CGPoint, to: CGPoint, t: CGFloat) -> CGPoint {
        let dx = max(36, abs(to.x - from.x) * 0.45)
        let c1 = CGPoint(x: from.x + dx, y: from.y)
        let c2 = CGPoint(x: to.x - dx, y: to.y)
        let u = 1 - t
        let x = u * u * u * from.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * to.x
        let y = u * u * u * from.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * to.y
        return CGPoint(x: x, y: y)
    }

    private static func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let apx = p.x - a.x
        let apy = p.y - a.y
        let abLen2 = abx * abx + aby * aby
        guard abLen2 > 0.0001 else { return hypot(apx, apy) }
        let t = max(0, min(1, (apx * abx + apy * aby) / abLen2))
        return hypot(p.x - (a.x + t * abx), p.y - (a.y + t * aby))
    }
}

struct GraphEdgeLayer: View {
    let document: GraphDocument
    let selectedEdgeIDs: Set<UUID>
    let draftFrom: CGPoint?
    let draftTo: CGPoint?
    /// Live node origins while dragging (document space).
    var livePositions: [UUID: CGPoint] = [:]
    let store: GraphStore

    var body: some View {
        Canvas { context, _ in
            for edge in document.edges {
                guard let from = store.portPosition(edge.from, livePositions: livePositions),
                      let to = store.portPosition(edge.to, livePositions: livePositions) else { continue }
                let path = GraphWirePath.bezier(from: from, to: to)
                let selected = selectedEdgeIDs.contains(edge.id)
                context.stroke(
                    path,
                    with: .color(selected ? Color.accentColor : Color.primary.opacity(0.32)),
                    style: StrokeStyle(
                        lineWidth: selected ? GraphTheme.wireWidth + 0.75 : GraphTheme.wireWidth,
                        lineCap: .round
                    )
                )
            }

            if let draftFrom, let draftTo {
                let path = GraphWirePath.bezier(from: draftFrom, to: draftTo)
                context.stroke(
                    path,
                    with: .color(Color.accentColor.opacity(0.85)),
                    style: StrokeStyle(lineWidth: GraphTheme.wireWidth, lineCap: .round, dash: [5, 4])
                )
            }
        }
        .allowsHitTesting(false)
    }
}
