import AppKit
import CoreGraphics

// Icone de Creneau : un cadran dont un secteur est verrouille.
// Fond ardoise nuit, secteur ambre, aiguille claire.

let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a)
}

let ardoiseHaut = rgb(30, 41, 59)
let ardoiseBas  = rgb(15, 23, 42)
let ambre       = rgb(245, 158, 11)
let ambreSombre = rgb(180, 83, 9)
let clair       = rgb(226, 232, 240)

let s = CGFloat(size)
let c = CGPoint(x: s/2, y: s/2)

// Fond en degrade vertical.
let fond = CGGradient(colorsSpace: cs, colors: [ardoiseHaut, ardoiseBas] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(fond, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

// Anneau du cadran.
let rayon = s * 0.33
ctx.setLineWidth(s * 0.055)
ctx.setStrokeColor(rgb(71, 85, 105))
ctx.addArc(center: c, radius: rayon, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.strokePath()

// Secteur bloque : de 10h a 2h sur le cadran, en ambre.
// Angles CoreGraphics : 0 = 3h, sens antihoraire.
let debut: CGFloat = .pi * 0.5   // 12h
let fin: CGFloat   = -.pi * 0.17 // un peu apres 3h
ctx.setLineWidth(s * 0.055)
ctx.setStrokeColor(ambre)
ctx.setLineCap(.round)
ctx.addArc(center: c, radius: rayon, startAngle: debut, endAngle: fin, clockwise: true)
ctx.strokePath()

// Remplissage doux du secteur.
ctx.saveGState()
ctx.move(to: c)
ctx.addArc(center: c, radius: rayon - s * 0.03, startAngle: debut, endAngle: fin, clockwise: true)
ctx.closePath()
ctx.setFillColor(ambre.copy(alpha: 0.10)!)
ctx.fillPath()
ctx.restoreGState()

// Graduations aux quarts.
ctx.setLineCap(.butt)
ctx.setLineWidth(s * 0.018)
ctx.setStrokeColor(rgb(100, 116, 139))
for i in 0..<12 {
    let angle = CGFloat(i) * .pi / 6
    let interieur = rayon - s * 0.085
    let exterieur = rayon - s * 0.05
    ctx.move(to: CGPoint(x: c.x + cos(angle) * interieur, y: c.y + sin(angle) * interieur))
    ctx.addLine(to: CGPoint(x: c.x + cos(angle) * exterieur, y: c.y + sin(angle) * exterieur))
}
ctx.strokePath()

// Aiguille pointant dans le secteur bloque.
ctx.setLineCap(.round)
ctx.setLineWidth(s * 0.032)
ctx.setStrokeColor(clair)
let aiguille: CGFloat = .pi * 0.28
ctx.move(to: c)
ctx.addLine(to: CGPoint(x: c.x + cos(aiguille) * rayon * 0.62,
                        y: c.y + sin(aiguille) * rayon * 0.62))
ctx.strokePath()

// Petite aiguille des heures.
ctx.setLineWidth(s * 0.038)
let heures: CGFloat = .pi * 0.05
ctx.move(to: c)
ctx.addLine(to: CGPoint(x: c.x + cos(heures) * rayon * 0.4,
                        y: c.y + sin(heures) * rayon * 0.4))
ctx.strokePath()

// Moyeu.
ctx.setFillColor(ambreSombre)
ctx.addArc(center: c, radius: s * 0.035, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.fillPath()

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try! png.write(to: URL(fileURLWithPath: out))
print("ecrit: \(out)")
