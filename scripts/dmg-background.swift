import AppKit
import SwiftUI

struct InstallerBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.95, blue: 0.98)
            VStack(spacing: 10) {
                Text("Install Vibote").font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color(white: 0.14))
                Text("Your remote. Your flow.").font(.system(size: 15))
                    .foregroundStyle(Color(white: 0.45))
            }.position(x: 380, y: 75)
            ForEach([190.0, 570.0], id: \.self) { x in
                RoundedRectangle(cornerRadius: 32)
                    .fill(Color(red: 0.91, green: 0.88, blue: 0.96))
                    .frame(width: 192, height: 192).position(x: x, y: 236)
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Color(red: 0.38, green: 0.15, blue: 0.73))
                .position(x: 380, y: 232)
            VStack(spacing: 10) {
                Text("Drag Vibote into Applications")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color(white: 0.2))
                Text("Then eject this disk and open Vibote from Applications.")
                    .font(.system(size: 13)).foregroundStyle(Color(white: 0.45))
            }.position(x: 380, y: 390)
            Text("macOS 14+  ·  Apple silicon & Intel")
                .font(.system(size: 11)).foregroundStyle(Color(white: 0.5))
                .position(x: 380, y: 462)
        }.frame(width: 760, height: 500)
    }
}

try MainActor.assumeIsolated {
    let output = NSImage(size: NSSize(width: 760, height: 500))
    for scale in [1.0, 2.0] {
        let renderer = ImageRenderer(content: InstallerBackground())
        renderer.scale = scale
        guard let image = renderer.cgImage else { fatalError("Could not render installer background") }
        let bitmap = NSBitmapImageRep(cgImage: image)
        bitmap.size = output.size
        output.addRepresentation(bitmap)
    }
    guard let data = output.tiffRepresentation else { fatalError("Could not encode background") }
    try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
