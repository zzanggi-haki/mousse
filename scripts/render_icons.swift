import AppKit

// Renders every Mousse brand asset from one shared geometry: the arrow cursor laid on a
// table as a slice of chocolate mousse cake (tip left, tail right), seen from the front
// and a little above, with glaze running down its layered sides.
//
// Outputs:
//   <outDir>/MenuBarIcon.pdf      vector template for the status item
//   <outDir>/menubar_preview.png  enlarged gray preview for review
//   <outDir>/icon_1024.png        app icon master
//
// Usage: swift scripts/render_icons.swift <outDir>
// Requires macOS 14+ (CGPath boolean operations).

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

// MARK: - Helpers

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

/// `v` darkened by factor `k` (wall shading).
func shaded(_ v: UInt32, _ k: CGFloat) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255 * k, green: CGFloat((v >> 8) & 0xFF) / 255 * k,
            blue: CGFloat(v & 0xFF) / 255 * k, alpha: 1)
}

func polygon(_ pts: [CGPoint]) -> CGPath {
    let p = CGMutablePath()
    p.addLines(between: pts)
    p.closeSubpath()
    return p
}

func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2), transform: nil)
}

func expanded(_ path: CGPath, _ by: CGFloat) -> CGPath {
    path.union(path.copy(strokingWithWidth: by * 2, lineCap: .round, lineJoin: .round, miterLimit: 4))
}

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

// MARK: - Shared geometry (design units, y-up)

/// The classic arrow in its own unit space: u to the right, v down, tip at the origin.
let arrowUV: [CGPoint] = [
    CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 0.80), CGPoint(x: 0.22, y: 0.62), CGPoint(x: 0.37, y: 0.94),
    CGPoint(x: 0.50, y: 0.88), CGPoint(x: 0.36, y: 0.57), CGPoint(x: 0.64, y: 0.57),
]

/// Lay the arrow on a table: turn it so the tip→tail axis runs left to right, then view
/// it from the front and a little above (the table plane is squashed vertically).
let axisAngle = atan2(0.91, 0.435)
let squash: CGFloat = 0.64
let length: CGFloat = 70
func place(_ p: CGPoint) -> CGPoint {
    let a = p.x * cos(axisAngle) + p.y * sin(axisAngle)     // along the axis
    let b = -p.x * sin(axisAngle) + p.y * cos(axisAngle)    // across it
    return CGPoint(x: a * length, y: b * length * squash)
}

let pts = arrowUV.map(place)
let topFace = polygon(pts)
/// Cake height: the side walls drop straight down from the top face.
let extrude = CGVector(dx: 0, dy: -15)

func dropped(_ p: CGPoint, _ f: CGFloat) -> CGPoint {
    CGPoint(x: p.x + extrude.dx * f, y: p.y + extrude.dy * f)
}

/// Outward normal of edge i (the polygon may wind either way).
let signedArea = (0..<pts.count).reduce(CGFloat(0)) { acc, i in
    let a = pts[i], b = pts[(i + 1) % pts.count]
    return acc + (a.x * b.y - b.x * a.y)
}
func normal(_ i: Int) -> CGVector {
    let a = pts[i], b = pts[(i + 1) % pts.count]
    let len = hypot(b.x - a.x, b.y - a.y)
    let dx = (b.x - a.x) / len, dy = (b.y - a.y) / len
    return signedArea > 0 ? CGVector(dx: dy, dy: -dx) : CGVector(dx: -dy, dy: dx)
}

/// Walls facing the viewer, far ones first (painter's order).
let visibleEdges: [Int] = (0..<pts.count)
    .filter { let n = normal($0); return n.dx * extrude.dx + n.dy * extrude.dy > 0 }
    .sorted {
        let ma = (pts[$0].y + pts[($0 + 1) % pts.count].y) / 2
        let mb = (pts[$1].y + pts[($1 + 1) % pts.count].y) / 2
        return ma > mb
    }

let walls: CGPath = visibleEdges.reduce(CGMutablePath() as CGPath) { acc, i in
    let a = pts[i], b = pts[(i + 1) % pts.count]
    return acc.union(polygon([a, b, dropped(b, 1), dropped(a, 1)]))
}

/// The monochrome silhouette: top face, then the walls with a gap so the 3D still reads.
/// Slivers of wall left over by the gap near the notch are dropped.
let glyph: CGPath = walls.subtracting(expanded(topFace, 2.8)).union(topFace)
    .componentsSeparated()
    .filter { $0.boundingBoxOfPath.width * $0.boundingBoxOfPath.height > 12 }
    .reduce(CGMutablePath() as CGPath) { $0.union($1) }
let glyphBounds = glyph.boundingBoxOfPath

// MARK: - Menu bar icon (vector template)

/// Point height of the status item image; width follows the glyph's aspect.
let menuBarHeight: CGFloat = 14
let menuBarScale = menuBarHeight / glyphBounds.height
let menuBarSize = CGSize(width: ceil(glyphBounds.width * menuBarScale), height: menuBarHeight)

func drawMenuBar(into ctx: CGContext, fill: CGColor, scale: CGFloat) {
    // Center horizontally (the width was rounded up to whole points).
    let slack = (menuBarSize.width / menuBarScale - glyphBounds.width) / 2
    ctx.saveGState()
    ctx.scaleBy(x: scale * menuBarScale, y: scale * menuBarScale)
    ctx.translateBy(x: slack - glyphBounds.minX, y: -glyphBounds.minY)
    ctx.addPath(glyph)
    ctx.setFillColor(fill)
    ctx.fillPath()
    ctx.restoreGState()
}

let pdfURL = outDir.appendingPathComponent("MenuBarIcon.pdf")
var mediaBox = CGRect(origin: .zero, size: menuBarSize)
let pdf = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil)!
pdf.beginPDFPage(nil)
drawMenuBar(into: pdf, fill: NSColor.black.cgColor, scale: 1)
pdf.endPDFPage()
pdf.closePDF()
print("Wrote \(pdfURL.path) (\(menuBarSize.width)×\(menuBarSize.height) pt)")

let previewScale: CGFloat = 24
let preview = bitmap(Int(menuBarSize.width * previewScale), Int(menuBarSize.height * previewScale)) { ctx in
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: menuBarSize.width * previewScale, height: menuBarSize.height * previewScale))
    drawMenuBar(into: ctx, fill: NSColor(white: 0.45, alpha: 1).cgColor, scale: previewScale)
}
try! preview.write(to: outDir.appendingPathComponent("menubar_preview.png"))
print("Wrote menubar_preview.png")

// MARK: - App icon master (1024)

struct Layer {
    /// Fractions of the cake's height, 0 = top surface.
    var from: CGFloat
    var to: CGFloat
    var color: UInt32
}

let glaze: UInt32 = 0x4A2320
let layers = [
    Layer(from: 0, to: 0.13, color: glaze),          // glaze spilling over the edge
    Layer(from: 0.13, to: 0.4, color: 0x9C6B52),     // mousse
    Layer(from: 0.4, to: 0.48, color: 0x5A2E26),     // ganache
    Layer(from: 0.48, to: 0.78, color: 0xA87657),    // mousse
    Layer(from: 0.78, to: 1, color: 0x5C3328),       // chocolate sponge
]

/// Light from the front left: walls facing it stay bright, the rest darken a little.
func wallShade(_ i: Int) -> CGFloat {
    let n = normal(i)
    return 0.82 + 0.18 * max(0, n.dx * -0.6 + n.dy * -0.8)
}

/// A glaze drip running down from `edge` at fraction `at` along it.
func drip(edge: Int, at: CGFloat, length: CGFloat, width: CGFloat) -> CGPath {
    let a = pts[edge], b = pts[(edge + 1) % pts.count]
    let start = CGPoint(x: a.x + (b.x - a.x) * at, y: a.y + (b.y - a.y) * at)
    let end = dropped(start, length)
    let p = CGMutablePath()
    p.move(to: start)
    p.addLine(to: end)
    return p.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 4)
        .union(circle(end.x, end.y, width * 0.68))
}

/// A topping sitting on the top face at unit position (u, v), drawn upright.
func onTop(_ u: CGFloat, _ v: CGFloat, lift: CGFloat) -> CGPoint {
    let p = place(CGPoint(x: u, y: v))
    return CGPoint(x: p.x, y: p.y + lift)
}

let size: CGFloat = 1024
let icon = bitmap(Int(size), Int(size)) { ctx in
    // Squircle background, caramel gradient.
    let inset: CGFloat = 88
    let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = tile.width * 0.2237
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    NSGradient(colors: [0xFFEBD6, 0xFFCC9E, 0xF2A56E, 0xD98552].map { NSColor(cgColor: hex($0))! },
               atLocations: [0, 0.38, 0.7, 1], colorSpace: .sRGB)!
        .draw(in: tile, angle: -55)
    ctx.restoreGState()

    // The cake, fitted to 74% of the tile and centered.
    let bounds = topFace.union(walls).boundingBoxOfPath
    let k = tile.width * 0.74 / max(bounds.width, bounds.height)
    ctx.saveGState()
    ctx.translateBy(x: size / 2 - bounds.midX * k, y: size / 2 - bounds.midY * k)
    ctx.scaleBy(x: k, y: k)
    ctx.setShadow(offset: CGSize(width: 0, height: -10 / k), blur: 26 / k, color: hex(0x5A2B1A, 0.3))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)

    func fill(_ path: CGPath, _ color: CGColor) {
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
    }
    for i in visibleEdges {
        let a = pts[i], b = pts[(i + 1) % pts.count]
        for layer in layers {
            let band = polygon([dropped(a, layer.from), dropped(b, layer.from), dropped(b, layer.to), dropped(a, layer.to)])
            fill(expanded(band, 0.15), shaded(layer.color, wallShade(i)))
        }
    }
    let dripSpots: [(CGFloat, CGFloat)] = [(0.35, 0.42), (0.6, 0.28), (0.45, 0.5), (0.3, 0.3)]
    for (edge, spot) in zip(visibleEdges.prefix(4), dripSpots) {
        fill(drip(edge: edge, at: spot.0, length: spot.1, width: 4.4), hex(glaze))
    }
    fill(topFace, hex(glaze))

    // Raspberry and a gold pearl on top.
    let berry = onTop(0.2, 0.45, lift: 4.8 * 0.7)
    fill(circle(berry.x, berry.y, 4.8), hex(0xD6304F))
    fill(circle(berry.x - 4.8 * 0.35, berry.y + 4.8 * 0.35, 4.8 * 0.28), hex(0xFFFFFF, 0.7))
    let pearl = onTop(0.34, 0.5, lift: 0)
    fill(CGPath(ellipseIn: CGRect(x: pearl.x - 2.2, y: pearl.y - 2.2 * squash * 1.4,
                                  width: 4.4, height: 4.4 * squash * 1.4), transform: nil), hex(0xF2C14E))

    ctx.endTransparencyLayer()
    ctx.restoreGState()
}
try! icon.write(to: outDir.appendingPathComponent("icon_1024.png"))
print("Wrote icon_1024.png")
