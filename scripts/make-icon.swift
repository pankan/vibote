// Renders the sketch-inspired Vibote icon. Run ./scripts/make-icon.sh.
import SwiftUI
import AppKit

struct RemoteCross: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = [
            CGPoint(x: 0.33, y: 0), CGPoint(x: 0.67, y: 0),
            CGPoint(x: 0.67, y: 0.33), CGPoint(x: 1, y: 0.33),
            CGPoint(x: 1, y: 0.67), CGPoint(x: 0.67, y: 0.67),
            CGPoint(x: 0.67, y: 1), CGPoint(x: 0.33, y: 1),
            CGPoint(x: 0.33, y: 0.67), CGPoint(x: 0, y: 0.67),
            CGPoint(x: 0, y: 0.33), CGPoint(x: 0.33, y: 0.33)
        ].map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        var path = Path()
        let radius: CGFloat = 11
        for i in points.indices {
            let previous = points[(i + points.count - 1) % points.count]
            let corner = points[i], next = points[(i + 1) % points.count]
            func inset(toward point: CGPoint) -> CGPoint {
                let dx = point.x - corner.x, dy = point.y - corner.y
                let length = hypot(dx, dy)
                return CGPoint(x: corner.x + dx / length * radius, y: corner.y + dy / length * radius)
            }
            let entry = inset(toward: previous), exit = inset(toward: next)
            if i == 0 { path.move(to: entry) } else { path.addLine(to: entry) }
            path.addQuadCurve(to: exit, control: corner)
        }
        path.closeSubpath()
        return path
    }
}

struct AppIcon: View {
    private let purple = Color(red: 0.34, green: 0.08, blue: 0.66)
    private let ink = Color(white: 0.07)
    private let printColor = Color(white: 0.95)

    var body: some View {
        ZStack {
            ZStack {
                Color(red: 0.91, green: 0.88, blue: 0.98)
                remote
                    .scaleEffect(1.3, anchor: .top)
                    .rotationEffect(.degrees(-42), anchor: .top)
                    .position(x: 275, y: 790)
            }
            .frame(width: 824, height: 824)
            .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        }.frame(width: 1024, height: 1024)
    }

    private var remote: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 82, style: .continuous).fill(ink)
            RoundedRectangle(cornerRadius: 74, style: .continuous)
                .fill(Color(white: 0.18))
                .overlay(RoundedRectangle(cornerRadius: 74, style: .continuous).stroke(Color(white: 0.32), lineWidth: 2))
                .padding(9)
            ZStack {
                roundKey("power", purple: true).position(x: 101, y: 94)
                roundKey("computermouse", purple: true).position(x: 269, y: 94)
                Capsule().fill(.black).frame(width: 8, height: 27).position(x: 185, y: 94)
                Circle().fill(.black).frame(width: 8, height: 8).position(x: 185, y: 154)
                dpad.position(x: 185, y: 309)
                roundKey(nil).overlay(assistantDots).position(x: 101, y: 522)
                roundKey("house").position(x: 269, y: 522)
            }
        }.frame(width: 370, height: 1250)
    }

    private var dpad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 70, style: .continuous).fill(purple)
                .overlay(RoundedRectangle(cornerRadius: 70, style: .continuous).stroke(ink, lineWidth: 4))
            RemoteCross().stroke(printColor, style: StrokeStyle(lineWidth: 4, lineJoin: .round)).padding(17)
            RoundedRectangle(cornerRadius: 27).fill(purple)
                .overlay(RoundedRectangle(cornerRadius: 27).stroke(ink, lineWidth: 4))
                .frame(width: 90, height: 90)
            Text("OK").font(.system(size: 33, weight: .medium, design: .monospaced)).foregroundStyle(printColor)
            ForEach([("arrowtriangle.up", 0.0, -88.0), ("arrowtriangle.down", 0, 88), ("arrowtriangle.left", -88, 0), ("arrowtriangle.right", 88, 0)], id: \.0) { symbol, x, y in
                Image(systemName: symbol).font(.system(size: 29, weight: .medium)).foregroundStyle(printColor).offset(x: x, y: y)
            }
        }.frame(width: 282, height: 278)
    }

    private func roundKey(_ symbol: String?, purple isPurple: Bool = false) -> some View {
        Circle().fill(isPurple ? purple : Color(white: 0.23))
            .overlay(Circle().stroke(ink, lineWidth: 3))
            .overlay {
                if let symbol { Image(systemName: symbol).font(.system(size: 43, weight: .regular)).foregroundStyle(printColor) }
            }.frame(width: 96, height: 96)
    }

    private var assistantDots: some View {
        ZStack {
            Circle().fill(printColor).frame(width: 23, height: 23).offset(x: -11, y: -7)
            Circle().fill(printColor).frame(width: 11, height: 11).offset(x: 8, y: 0)
            Circle().fill(printColor).frame(width: 13, height: 13).offset(x: 8, y: 15)
            Circle().fill(printColor).frame(width: 6, height: 6).offset(x: 17, y: -9)
        }
    }
}

@MainActor func write(size: Int, to url: URL) {
    let renderer = ImageRenderer(content: AppIcon().frame(width: 1024, height: 1024))
    renderer.scale = CGFloat(size) / 1024
    guard let image = renderer.cgImage else { fatalError("render failed") }
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
MainActor.assumeIsolated {
    for base in [16, 32, 128, 256, 512] {
        write(size: base, to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
        write(size: base * 2, to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
    }
}
