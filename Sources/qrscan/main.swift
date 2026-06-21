import Foundation
import Vision
import ImageIO

func warn(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

// 识别单张图片里的所有 QR 内容；读图失败则告警并返回空
func detectQRCodes(in path: String) -> [String] {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        warn("warning: 无法读取图片: \(path)")
        return []
    }
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr]
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
        try handler.perform([request])
    } catch {
        warn("warning: 识别失败 \(path): \(error)")
        return []
    }
    let observations = request.results ?? []
    return observations.compactMap { $0.payloadStringValue }
}

let args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else {
    warn("usage: qrscan <image> [<image>...]")
    exit(2)
}

var seen = Set<String>()
var ordered: [String] = []
for path in args {
    for payload in detectQRCodes(in: path) where seen.insert(payload).inserted {
        ordered.append(payload)
    }
}

for line in ordered {
    print(line)
}
exit(ordered.isEmpty ? 1 : 0)
