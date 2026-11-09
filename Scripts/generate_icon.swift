import Foundation
import AppKit
import CoreGraphics

enum IconTheme: String, CaseIterable {
    case obsidian = "1_Obsidian_Shield_Vault"
    case emerald = "2_Emerald_Matrix_Vault"
    case titanium = "3_Titanium_Minimal_Vault"
}

func hexColor(_ hex: String, alpha: CGFloat = 1.0) -> NSColor {
    var str = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if str.hasPrefix("#") { str.removeFirst() }
    guard str.count == 6, let rgb = UInt64(str, radix: 16) else {
        return NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: alpha)
    }
    let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
    let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
    let b = CGFloat(rgb & 0x0000FF) / 255.0
    return NSColor(calibratedRed: r, green: g, blue: b, alpha: alpha)
}

func renderIcon(theme: IconTheme, size: CGFloat = 1024) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    ctx.saveGState()
    let scale = size / 1024.0
    ctx.scaleBy(x: scale, y: scale)

    // 1. Base Squircle Dimensions according to Apple HIG
    // 864x864 squircle centered in 1024x1024 (inset 80px), corner radius 195
    let squircleRect = CGRect(x: 80, y: 80, width: 864, height: 864)
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: 195, cornerHeight: 195, transform: nil)

    // Outer Drop Shadow for macOS app icon depth
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -22),
        blur: 36,
        color: NSColor(calibratedWhite: 0.0, alpha: 0.48).cgColor
    )
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.addPath(squirclePath)
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to squircle for icon content
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // 2. Background Gradient & Texture
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    var bgColors: [CGColor] = []
    switch theme {
    case .obsidian:
        bgColors = [
            hexColor("#1B375E").cgColor,
            hexColor("#122340").cgColor,
            hexColor("#0A101D").cgColor
        ]
    case .emerald:
        bgColors = [
            hexColor("#0E3321").cgColor,
            hexColor("#091F14").cgColor,
            hexColor("#050E09").cgColor
        ]
    case .titanium:
        bgColors = [
            hexColor("#EAEFF5").cgColor,
            hexColor("#D5DCE4").cgColor,
            hexColor("#B8C2CE").cgColor
        ]
    }

    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors as CFArray, locations: [0.0, 0.45, 1.0]) {
        // Diagonal gradient from top-left to bottom-right
        ctx.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: 180, y: 920),
            end: CGPoint(x: 840, y: 100),
            options: []
        )
    }

    // Radial central highlight/glow
    let radialCenter = CGPoint(x: 512, y: 560)
    var glowColor: NSColor
    switch theme {
    case .obsidian:
        glowColor = hexColor("#00F2FE", alpha: 0.22)
    case .emerald:
        glowColor = hexColor("#00FF87", alpha: 0.20)
    case .titanium:
        glowColor = hexColor("#FFFFFF", alpha: 0.65)
    }
    if let radialGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [glowColor.cgColor, glowColor.withAlphaComponent(0.0).cgColor] as CFArray,
        locations: [0.0, 1.0]
    ) {
        ctx.drawRadialGradient(
            radialGrad,
            startCenter: radialCenter,
            startRadius: 20,
            endCenter: radialCenter,
            endRadius: 420,
            options: []
        )
    }

    // Subtle background micro-grid or security pattern
    ctx.saveGState()
    ctx.setLineWidth(1.0)
    ctx.setStrokeColor(NSColor(calibratedWhite: theme == .titanium ? 0.0 : 1.0, alpha: 0.035).cgColor)
    for x in stride(from: 100, through: 924, by: 48) {
        ctx.move(to: CGPoint(x: CGFloat(x), y: 80))
        ctx.addLine(to: CGPoint(x: CGFloat(x), y: 944))
    }
    for y in stride(from: 100, through: 944, by: 48) {
        ctx.move(to: CGPoint(x: 80, y: CGFloat(y)))
        ctx.addLine(to: CGPoint(x: 944, y: CGFloat(y)))
    }
    ctx.strokePath()
    ctx.restoreGState()

    // 3. Central Composition: Clipboard Slate (Планшет буфера обмена)
    let slateRect = CGRect(x: 242, y: 170, width: 540, height: 630)
    let slatePath = CGPath(roundedRect: slateRect, cornerWidth: 38, cornerHeight: 38, transform: nil)

    // Slate drop shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -14),
        blur: 28,
        color: NSColor(calibratedWhite: 0.0, alpha: theme == .titanium ? 0.28 : 0.55).cgColor
    )
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.addPath(slatePath)
    ctx.fillPath()
    ctx.restoreGState()

    // Slate body
    ctx.saveGState()
    ctx.addPath(slatePath)
    ctx.clip()

    var slateColors: [CGColor] = []
    switch theme {
    case .obsidian:
        slateColors = [hexColor("#1B263D").cgColor, hexColor("#101726").cgColor]
    case .emerald:
        slateColors = [hexColor("#16261E").cgColor, hexColor("#0B150F").cgColor]
    case .titanium:
        slateColors = [hexColor("#FFFFFF").cgColor, hexColor("#E2E7ED").cgColor]
    }
    if let slateGrad = CGGradient(colorsSpace: colorSpace, colors: slateColors as CFArray, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(slateGrad, start: CGPoint(x: 512, y: 800), end: CGPoint(x: 512, y: 170), options: [])
    }

    // Clipboard text lines (simulating saved paste items)
    let lineAlpha: CGFloat = theme == .titanium ? 0.22 : 0.12
    let lineColor = theme == .titanium ? NSColor.black.withAlphaComponent(lineAlpha) : NSColor.white.withAlphaComponent(lineAlpha)
    ctx.setFillColor(lineColor.cgColor)
    let textLineY: [CGFloat] = [700, 660, 620, 260, 220]
    for y in textLineY {
        let lineWidth: CGFloat = y == 700 ? 260 : (y == 660 ? 340 : (y == 620 ? 180 : 320))
        let lineX = 512 - (lineWidth / 2)
        let lineRect = CGRect(x: lineX, y: y, width: lineWidth, height: 8)
        let linePath = CGPath(roundedRect: lineRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(linePath)
        ctx.fillPath()
    }

    ctx.restoreGState() // unclip slate

    // Slate rim stroke
    ctx.saveGState()
    ctx.setLineWidth(2.0)
    let slateRimColor: NSColor
    switch theme {
    case .obsidian: slateRimColor = hexColor("#38BDF8", alpha: 0.35)
    case .emerald: slateRimColor = hexColor("#10B981", alpha: 0.38)
    case .titanium: slateRimColor = NSColor.white.withAlphaComponent(0.85)
    }
    ctx.setStrokeColor(slateRimColor.cgColor)
    ctx.addPath(slatePath)
    ctx.strokePath()
    ctx.restoreGState()

    // 4. Top Metallic Clip (Металлический зажим)
    let clipRect = CGRect(x: 397, y: 755, width: 230, height: 68)
    let clipPath = CGPath(roundedRect: clipRect, cornerWidth: 16, cornerHeight: 16, transform: nil)

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -6),
        blur: 14,
        color: NSColor(calibratedWhite: 0.0, alpha: 0.45).cgColor
    )
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.addPath(clipPath)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(clipPath)
    ctx.clip()

    let clipColors = [
        hexColor("#FFFFFF").cgColor,
        hexColor("#C8D1DC").cgColor,
        hexColor("#8E9AA8").cgColor,
        hexColor("#C8D1DC").cgColor
    ]
    if let clipGrad = CGGradient(colorsSpace: colorSpace, colors: clipColors as CFArray, locations: [0.0, 0.35, 0.7, 1.0]) {
        ctx.drawLinearGradient(clipGrad, start: CGPoint(x: 397, y: 823), end: CGPoint(x: 627, y: 755), options: [])
    }

    // Clip center rivet / hole
    let holeRect = CGRect(x: 472, y: 775, width: 80, height: 26)
    let holePath = CGPath(roundedRect: holeRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
    ctx.setFillColor(NSColor(calibratedWhite: 0.12, alpha: 0.85).cgColor)
    ctx.addPath(holePath)
    ctx.fillPath()

    ctx.restoreGState() // unclip clip

    // Clip border highlight
    ctx.saveGState()
    ctx.setLineWidth(1.5)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
    ctx.addPath(clipPath)
    ctx.strokePath()
    ctx.restoreGState()

    // 5. Central 3D Faceted Vault Shield (Объёмный гранёный щит)
    // Shield points
    let topCenter = CGPoint(x: 512, y: 640)
    let topLeft = CGPoint(x: 348, y: 615)
    let topLeftCurve = CGPoint(x: 348, y: 480)
    let bottomTip = CGPoint(x: 512, y: 285)
    let topRight = CGPoint(x: 676, y: 615)
    let topRightCurve = CGPoint(x: 676, y: 480)

    // Full shield path for shadow & glow
    let fullShieldPath = CGMutablePath()
    fullShieldPath.move(to: topCenter)
    fullShieldPath.addLine(to: topLeft)
    fullShieldPath.addLine(to: topLeftCurve)
    fullShieldPath.addQuadCurve(to: bottomTip, control: CGPoint(x: 360, y: 350))
    fullShieldPath.addQuadCurve(to: topRightCurve, control: CGPoint(x: 664, y: 350))
    fullShieldPath.addLine(to: topRight)
    fullShieldPath.closeSubpath()

    // Shield outer glow & drop shadow
    ctx.saveGState()
    var shieldGlowColor: NSColor
    switch theme {
    case .obsidian: shieldGlowColor = hexColor("#00F2FE", alpha: 0.45)
    case .emerald: shieldGlowColor = hexColor("#00FF87", alpha: 0.45)
    case .titanium: shieldGlowColor = hexColor("#007AFF", alpha: 0.40)
    }
    ctx.setShadow(
        offset: CGSize(width: 0, height: -12),
        blur: 32,
        color: shieldGlowColor.cgColor
    )
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.addPath(fullShieldPath)
    ctx.fillPath()
    ctx.restoreGState()

    // Left Facet (Light side)
    let leftFacetPath = CGMutablePath()
    leftFacetPath.move(to: topCenter)
    leftFacetPath.addLine(to: topLeft)
    leftFacetPath.addLine(to: topLeftCurve)
    leftFacetPath.addQuadCurve(to: bottomTip, control: CGPoint(x: 360, y: 350))
    leftFacetPath.closeSubpath()

    ctx.saveGState()
    ctx.addPath(leftFacetPath)
    ctx.clip()

    var leftColors: [CGColor] = []
    switch theme {
    case .obsidian:
        leftColors = [hexColor("#43E97B").cgColor, hexColor("#00F2FE").cgColor, hexColor("#38BDF8").cgColor]
        leftColors = [hexColor("#67E8F9").cgColor, hexColor("#00F2FE").cgColor, hexColor("#0284C7").cgColor]
    case .emerald:
        leftColors = [hexColor("#6EE7B7").cgColor, hexColor("#00FF87").cgColor, hexColor("#059669").cgColor]
    case .titanium:
        leftColors = [hexColor("#93C5FD").cgColor, hexColor("#3B82F6").cgColor, hexColor("#1D4ED8").cgColor]
    }
    if let leftGrad = CGGradient(colorsSpace: colorSpace, colors: leftColors as CFArray, locations: [0.0, 0.5, 1.0]) {
        ctx.drawLinearGradient(leftGrad, start: CGPoint(x: 348, y: 640), end: CGPoint(x: 512, y: 285), options: [])
    }
    ctx.restoreGState()

    // Right Facet (Shaded side for 3D volume)
    let rightFacetPath = CGMutablePath()
    rightFacetPath.move(to: topCenter)
    rightFacetPath.addLine(to: topRight)
    rightFacetPath.addLine(to: topRightCurve)
    rightFacetPath.addQuadCurve(to: bottomTip, control: CGPoint(x: 664, y: 350))
    rightFacetPath.closeSubpath()

    ctx.saveGState()
    ctx.addPath(rightFacetPath)
    ctx.clip()

    var rightColors: [CGColor] = []
    switch theme {
    case .obsidian:
        rightColors = [hexColor("#0284C7").cgColor, hexColor("#0369A1").cgColor, hexColor("#075985").cgColor]
    case .emerald:
        rightColors = [hexColor("#059669").cgColor, hexColor("#047857").cgColor, hexColor("#064E3B").cgColor]
    case .titanium:
        rightColors = [hexColor("#1D4ED8").cgColor, hexColor("#1E40AF").cgColor, hexColor("#172554").cgColor]
    }
    if let rightGrad = CGGradient(colorsSpace: colorSpace, colors: rightColors as CFArray, locations: [0.0, 0.5, 1.0]) {
        ctx.drawLinearGradient(rightGrad, start: CGPoint(x: 512, y: 640), end: CGPoint(x: 676, y: 285), options: [])
    }
    ctx.restoreGState()

    // Shield Center Crease & Outer Contour Stroke
    ctx.saveGState()
    ctx.setLineWidth(2.5)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.65).cgColor)
    ctx.addPath(fullShieldPath)
    ctx.strokePath()

    // Center crease highlight line
    ctx.setLineWidth(1.8)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
    ctx.move(to: topCenter)
    ctx.addLine(to: bottomTip)
    ctx.strokePath()
    ctx.restoreGState()

    // 6. Emblem inside Shield: Vault Dial Ring + Lightning / Paste Arrow
    // Circular dial rim
    let dialCenter = CGPoint(x: 512, y: 470)
    let dialRadius: CGFloat = 68.0
    let dialRect = CGRect(x: dialCenter.x - dialRadius, y: dialCenter.y - dialRadius, width: dialRadius * 2, height: dialRadius * 2)

    // Dial background
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -4),
        blur: 12,
        color: NSColor(calibratedWhite: 0.0, alpha: 0.45).cgColor
    )
    ctx.setFillColor(NSColor(calibratedWhite: 0.08, alpha: 0.88).cgColor)
    ctx.fillEllipse(in: dialRect)
    ctx.restoreGState()

    // Dial outer ring border
    ctx.saveGState()
    ctx.setLineWidth(3.0)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
    ctx.strokeEllipse(in: dialRect)
    ctx.restoreGState()

    // Dial tick marks (vault combination lock notches)
    ctx.saveGState()
    ctx.setLineWidth(2.0)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
    for angle in stride(from: 0.0, to: 360.0, by: 45.0) {
        let rad = angle * .pi / 180.0
        let innerR: CGFloat = dialRadius - 9.0
        let outerR: CGFloat = dialRadius - 3.0
        let p1 = CGPoint(x: dialCenter.x + cos(rad) * innerR, y: dialCenter.y + sin(rad) * innerR)
        let p2 = CGPoint(x: dialCenter.x + cos(rad) * outerR, y: dialCenter.y + sin(rad) * outerR)
        ctx.move(to: p1)
        ctx.addLine(to: p2)
    }
    ctx.strokePath()
    ctx.restoreGState()

    // Lightning / Fast-Paste Arrow in the heart of the vault dial
    // Symbolizes instant pasting and secure injection into apps
    let lightningPath = CGMutablePath()
    lightningPath.move(to: CGPoint(x: 518, y: 510))
    lightningPath.addLine(to: CGPoint(x: 494, y: 474))
    lightningPath.addLine(to: CGPoint(x: 510, y: 474))
    lightningPath.addLine(to: CGPoint(x: 504, y: 432))
    lightningPath.addLine(to: CGPoint(x: 532, y: 466))
    lightningPath.addLine(to: CGPoint(x: 516, y: 466))
    lightningPath.closeSubpath()

    // Lightning glow
    ctx.saveGState()
    var boltGlow: NSColor
    switch theme {
    case .obsidian: boltGlow = hexColor("#00F2FE", alpha: 0.9)
    case .emerald: boltGlow = hexColor("#00FF87", alpha: 0.9)
    case .titanium: boltGlow = hexColor("#38BDF8", alpha: 0.9)
    }
    ctx.setShadow(
        offset: .zero,
        blur: 16,
        color: boltGlow.cgColor
    )
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(lightningPath)
    ctx.fillPath()
    ctx.restoreGState()

    // 7. Outer Glass/Metal Rim on the Squircle (macOS HIG signature polish)
    ctx.restoreGState() // unclip squircle

    ctx.saveGState()
    ctx.setLineWidth(2.5)
    // Draw subtle gradient rim
    let rimColors = [
        NSColor.white.withAlphaComponent(theme == .titanium ? 0.75 : 0.45).cgColor,
        NSColor.white.withAlphaComponent(0.05).cgColor,
        NSColor.black.withAlphaComponent(0.35).cgColor
    ]
    if let rimGrad = CGGradient(colorsSpace: colorSpace, colors: rimColors as CFArray, locations: [0.0, 0.4, 1.0]) {
        ctx.addPath(squirclePath)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(rimGrad, start: CGPoint(x: 512, y: 944), end: CGPoint(x: 512, y: 80), options: [])
    }
    ctx.restoreGState()

    ctx.restoreGState() // restore initial state

    image.unlockFocus()
    return image
}

func savePNG(image: NSImage, to url: URL) throws {
    guard let tiffData = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiffData),
          let pngData = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ImageExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to PNG"])
    }
    try pngData.write(to: url)
}

// Resizes NSImage with high quality interpolation
func resize(image: NSImage, to newSize: CGFloat) -> NSImage {
    let newImage = NSImage(size: NSSize(width: newSize, height: newSize))
    newImage.lockFocus()
    guard let ctx = NSGraphicsContext.current else {
        newImage.unlockFocus()
        return newImage
    }
    ctx.imageInterpolation = .high
    image.draw(
        in: NSRect(x: 0, y: 0, width: newSize, height: newSize),
        from: NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height),
        operation: .copy,
        fraction: 1.0
    )
    newImage.unlockFocus()
    return newImage
}

// MAIN EXECUTION
let fileManager = FileManager.default
let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let variantsDir = currentDir.appendingPathComponent("Logo_Variants")
try? fileManager.createDirectory(at: variantsDir, withIntermediateDirectories: true)

print("🎨 [1/3] Generating 3 high-resolution 1024x1024 Logo Variants...")
for theme in IconTheme.allCases {
    let img = renderIcon(theme: theme, size: 1024)
    let fileURL = variantsDir.appendingPathComponent("\(theme.rawValue).png")
    try savePNG(image: img, to: fileURL)
    print("   ✓ Saved \(theme.rawValue).png")
}

print("📦 [2/3] Building AppIcon.iconset from Main Variant (Obsidian Shield Vault)...")
let mainImage = renderIcon(theme: .obsidian, size: 1024)
let iconsetDir = currentDir.appendingPathComponent("AppIcon.iconset")
try? fileManager.removeItem(at: iconsetDir)
try fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let iconSizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in iconSizes {
    let resized = resize(image: mainImage, to: size)
    let destURL = iconsetDir.appendingPathComponent(name)
    try savePNG(image: resized, to: destURL)
    print("   ✓ Generated \(name) (\(Int(size))x\(Int(size)))")
}

print("✨ [3/3] Done generating iconset!")
