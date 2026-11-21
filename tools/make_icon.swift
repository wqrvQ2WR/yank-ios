import AppKit
// 보라-자홍-주황 그라디언트 위에 흰 내려받기 화살표. 사용: swift tools/make_icon.swift Yank/Resources/Assets.xcassets/AppIcon.appiconset/icon.png
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let cs = CGColorSpaceCreateDeviceRGB()
let g = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0x6D/255, green: 0x2B/255, blue: 1, alpha: 1),
    CGColor(red: 1, green: 0x2E/255, blue: 0x93/255, alpha: 1),
    CGColor(red: 1, green: 0x8A/255, blue: 0, alpha: 1)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
// 화살표 몸통 + 머리
ctx.fill(CGRect(x: 432, y: 430, width: 160, height: 330))
ctx.move(to: CGPoint(x: 300, y: 450)); ctx.addLine(to: CGPoint(x: 724, y: 450)); ctx.addLine(to: CGPoint(x: 512, y: 240)); ctx.closePath(); ctx.fillPath()
// 받침대
let r = CGRect(x: 280, y: 170, width: 464, height: 64)
ctx.addPath(CGPath(roundedRect: r, cornerWidth: 32, cornerHeight: 32, transform: nil)); ctx.fillPath()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
