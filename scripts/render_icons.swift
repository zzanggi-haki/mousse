import AppKit

// Renders every Mousse brand asset from one shared geometry: a mousse dome on a plate,
// a berry on top, and a cursor arrow carved into the dome.
//
// Outputs:
//   <outDir>/MenuBarIcon.pdf      vector template for the status item (30×24 pt)
//   <outDir>/menubar_preview.png  enlarged gray preview for review
//   <outDir>/icon_1024.png        app icon master ("Berry Mousse" squircle)
//
// Usage: swift scripts/render_icons.swift <outDir>
// Requires macOS 14+ (CGPath boolean operations).

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

// MARK: - Shared geometry (30×24 unit box, y-up)

let W: CGFloat = 30
let H: CGFloat = 24

func pill(_ r: CGRect) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil)
}

/// Classic arrow cursor, tip at `tip`, pointing up-left.
func arrowPath(tip: CGPoint, height h: CGFloat) -> CGPath {
    let unit: [(CGFloat, CGFloat)] = [
        (0, 0), (0, 0.80), (0.22, 0.62), (0.37, 0.94), (0.50, 0.88), (0.36, 0.57), (0.64, 0.57),
    ]
    let p = CGMutablePath()
    for (i, (u, v)) in unit.enumerated() {
        let pt = CGPoint(x: tip.x + u * h, y: tip.y - v * h)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

struct Mark {
    let plate: CGPath
    let dome: CGPath      // dome with the arrow and berry (plus a gap) carved out
    let arrow: CGPath
    let berry: CGPath
}

func makeMark(gap: CGFloat) -> Mark {
    let plate = pill(CGRect(x: 2.5, y: 1.4, width: 25, height: 2.2))

    // Dome sitting on the plate.
    let rimY: CGFloat = 5.6
    let t = CGAffineTransform(translationX: 15, y: rimY).scaledBy(x: 11, y: 11.8)
    let dome = CGMutablePath()
    dome.addArc(center: .zero, radius: 1, startAngle: 0, endAngle: .pi, clockwise: false, transform: t)
    dome.closeSubpath()

    let arrow = arrowPath(tip: CGPoint(x: 12.8, y: 14.8), height: 8.2)
    let cut = arrow.union(arrow.copy(strokingWithWidth: gap, lineCap: .round, lineJoin: .round, miterLimit: 4))
    let carved = dome.subtracting(cut)

    // Berry resting on the dome's crown (overlapping it, so it reads as a garnish
    // rather than a cloche handle).
    let berry = CGPath(ellipseIn: CGRect(x: 15.8, y: 15.4, width: 4.6, height: 4.6), transform: nil)
    return Mark(plate: plate, dome: carved.subtracting(berry.copy(strokingWithWidth: gap, lineCap: .round, lineJoin: .round, miterLimit: 4)), arrow: arrow, berry: berry)
}

// MARK: - Menu bar icon (vector template)

func drawMenuBar(into ctx: CGContext, fill: CGColor) {
    let mark = makeMark(gap: 2.2)
    ctx.setFillColor(fill)
    for path in [mark.plate, mark.dome, mark.arrow, mark.berry] {
        ctx.addPath(path)
        ctx.fillPath()
    }
}

let pdfURL = outDir.appendingPathComponent("MenuBarIcon.pdf")
var mediaBox = CGRect(x: 0, y: 0, width: W, height: H)
let pdf = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil)!
pdf.beginPDFPage(nil)
drawMenuBar(into: pdf, fill: NSColor.black.cgColor)
pdf.endPDFPage()
pdf.closePDF()
print("Wrote \(pdfURL.path)")

func bitmap(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let previewScale: CGFloat = 24
let preview = bitmap(Int(W * previewScale), Int(H * previewScale)) { ctx in
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: W * previewScale, height: H * previewScale))
    ctx.scaleBy(x: previewScale, y: previewScale)
    drawMenuBar(into: ctx, fill: NSColor(white: 0.45, alpha: 1).cgColor)
}
try! preview.write(to: outDir.appendingPathComponent("menubar_preview.png"))
print("Wrote menubar_preview.png")

// MARK: - App icon master (1024)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let size: CGFloat = 1024
let icon = bitmap(Int(size), Int(size)) { ctx in
    // Squircle background with the "Berry Mousse" gradient.
    let inset: CGFloat = 88
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = (size - inset * 2) * 0.2237
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    ctx.saveGState()
    squircle.addClip()
    let gradient = NSGradient(colors: [
        color(255, 205, 222),  // strawberry cream
        color(255, 143, 177),  // pink mousse
        color(235, 94, 150),   // raspberry
        color(176, 86, 214),   // blackcurrant
    ], atLocations: [0.0, 0.38, 0.7, 1.0], colorSpace: .sRGB)!
    gradient.draw(in: rect, angle: -55)
    ctx.restoreGState()

    // Mark, scaled from the 30×24 unit box and centered.
    let k: CGFloat = 22
    let mark = makeMark(gap: 1.5)
    ctx.saveGState()
    ctx.translateBy(x: (size - W * k) / 2, y: (size - H * k) / 2 - 8)
    ctx.scaleBy(x: k, y: k)
    ctx.setShadow(offset: CGSize(width: 0, height: -10 / k), blur: 26 / k,
                  color: color(110, 30, 80, 0.30).cgColor)
    ctx.setFillColor(color(255, 255, 255, 0.96).cgColor)
    for path in [mark.plate, mark.dome, mark.arrow] {
        ctx.addPath(path)
        ctx.fillPath()
    }
    ctx.setFillColor(color(196, 34, 98).cgColor)
    ctx.addPath(mark.berry)
    ctx.fillPath()
    ctx.restoreGState()
}
try! icon.write(to: outDir.appendingPathComponent("icon_1024.png"))
print("Wrote icon_1024.png")
