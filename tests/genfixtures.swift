import Foundation
import CoreImage
import AppKit

// 用 CIQRCodeGenerator 生成一张包含 payload 的二维码 CIImage（放大 10 倍便于识别）
func qrImage(_ payload: String) -> CIImage {
    let filter = CIFilter(name: "CIQRCodeGenerator")!
    filter.setValue(payload.data(using: .utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    return filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
}

func writePNG(_ image: CIImage, to path: String) {
    let ctx = CIContext()
    guard let cg = ctx.createCGImage(image, from: image.extent) else {
        fatalError("createCGImage failed for \(path)")
    }
    let rep = NSBitmapImageRep(cgImage: cg)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "tests/fixtures"
try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// 单码：URL / 纯文本 / 中文
writePNG(qrImage("https://example.com"), to: "\(outDir)/url.png")
writePNG(qrImage("hello world"), to: "\(outDir)/text.png")
writePNG(qrImage("你好二维码"), to: "\(outDir)/chinese.png")

// 无码：纯白图
let blank = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
writePNG(blank, to: "\(outDir)/blank.png")

// 双码：把两张二维码横向拼到一张白底图上
let a = qrImage("https://first.example")
let b = qrImage("https://second.example")
    .transformed(by: CGAffineTransform(translationX: a.extent.width + 40, y: 0))
let combined = b.composited(over: a)
let bg = CIImage(color: .white).cropped(to: combined.extent.insetBy(dx: -20, dy: -20))
writePNG(combined.composited(over: bg), to: "\(outDir)/multi.png")

print("fixtures written to \(outDir)")
