import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvasSize = 1024
let outputPath = CommandLine.arguments.dropFirst().first
    ?? "STEWUniversity/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

guard let context = CGContext(
    data: nil,
    width: canvasSize,
    height: canvasSize,
    bitsPerComponent: 8,
    bytesPerRow: canvasSize * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fatalError("Unable to create icon drawing context.")
}

context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

// Draw using the SVG's top-left coordinate system.
context.translateBy(x: 0, y: CGFloat(canvasSize))
context.scaleBy(x: 1, y: -1)
context.setFillColor(
    CGColor(
        red: 230.0 / 255.0,
        green: 168.0 / 255.0,
        blue: 23.0 / 255.0,
        alpha: 1
    )
)

let bars: [CGRect] = [
    CGRect(x: 220, y: 376, width: 52, height: 92),
    CGRect(x: 314, y: 310, width: 56, height: 178),
    CGRect(x: 410, y: 238, width: 58, height: 272),
    CGRect(x: 482, y: 138, width: 60, height: 392),
    CGRect(x: 556, y: 238, width: 58, height: 272),
    CGRect(x: 654, y: 310, width: 56, height: 178),
    CGRect(x: 752, y: 376, width: 52, height: 92),
]

for bar in bars {
    let radius = bar.width / 2
    context.addPath(CGPath(roundedRect: bar, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
}

let bowl = CGMutablePath()
bowl.move(to: CGPoint(x: 148, y: 496))
bowl.addCurve(
    to: CGPoint(x: 512, y: 620),
    control1: CGPoint(x: 244, y: 574),
    control2: CGPoint(x: 369, y: 620)
)
bowl.addCurve(
    to: CGPoint(x: 876, y: 496),
    control1: CGPoint(x: 655, y: 620),
    control2: CGPoint(x: 780, y: 574)
)
bowl.addCurve(
    to: CGPoint(x: 904, y: 512),
    control1: CGPoint(x: 888, y: 486),
    control2: CGPoint(x: 906, y: 495)
)
bowl.addCurve(
    to: CGPoint(x: 512, y: 842),
    control1: CGPoint(x: 889, y: 694),
    control2: CGPoint(x: 732, y: 842)
)
bowl.addCurve(
    to: CGPoint(x: 120, y: 512),
    control1: CGPoint(x: 292, y: 842),
    control2: CGPoint(x: 135, y: 694)
)
bowl.addCurve(
    to: CGPoint(x: 148, y: 496),
    control1: CGPoint(x: 118, y: 495),
    control2: CGPoint(x: 136, y: 486)
)
bowl.closeSubpath()
context.addPath(bowl)
context.fillPath()

guard
    let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: outputPath) as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    )
else {
    fatalError("Unable to prepare the app icon PNG.")
}

CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Unable to write the app icon PNG.")
}

print(outputPath)
