import Foundation
import Vision
import CoreImage
import UIKit

// =====================================================================
//  OCRPipeline：录屏帧 → 屏幕文本解析（会话名 + 她/我消息行）
// =====================================================================
//  移植自 PC 端 app/ocr.py 的判定逻辑：
//   - who_said()：按 OCR 框内**颜色**分类，不看 x 坐标
//       绿底 → me（自己）；非绿且文字对底色对比度 ≥150 → her（对方）；
//       颜色杂（>40 种）且众数占比 <45% → 图片/表情包里的字，丢；
//       其余灰字（时间戳/系统提示/群昵称）→ gray，丢
//   - read_title()：最靠上的一行、最左的文本 = 会话名（去群人数后缀）
//   - parse_time()：时间戳行（带 HH:MM）跳过
//   - _centered()：水平居中的行 = 微信系统提示，跳过
//   - _tail_from_her()（engine.py）：末尾连续属于对方的消息，\n 连接
// =====================================================================

final class OCRPipeline {
    private let request: VNRecognizeTextRequest
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// 触发解析的节流（秒）：PC 端每帧都解析，iPhone省电优先 1 秒
    var minIntervalSeconds: Int

    private var lastAnalyzedAt: Date = .distantPast
    /// 上次处理过的 (会话, 对方消息) 签名，避免同一条消息反复上传
    private var lastSignature: String?

    init(minIntervalSeconds: Int = 1) {
        self.minIntervalSeconds = max(1, minIntervalSeconds)
        request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        // 自动检测语言候选
        request.customWords = []
        request.minimumTextHeight = 0.008
    }

    // MARK: - 对外入口

    struct ScreenParse {
        var session: String
        var lines: [ParsedLine]
        /// 末尾连续属于对方的消息（\n 连接）；没有则空串
        var incomingFromHer: String
    }

    /// 解析一帧。返回 nil = 不到节流时间 / OCR 无结果。
    func parse(sampleBuffer: CMSampleBuffer) -> ScreenParse? {
        let now = Date()
        guard now.timeIntervalSince(lastAnalyzedAt) >= Double(minIntervalSeconds) else { return nil }
        lastAnalyzedAt = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        var observations: [VNRecognizedTextObservation] = []
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
            observations = request.results ?? []
        } catch {
            return nil
        }
        guard !observations.isEmpty else { return nil }

        // 每帧渲染一次 CGImage，所有框共用（全图渲染一次比逐框裁切更稳）
        guard let cgImage = renderCGImage(pixelBuffer: pixelBuffer) else { return nil }

        var parsed: [ParsedLine] = []
        for obs in observations {
            guard let text = obs.topCandidates(1).first?.string,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let box = obs.boundingBox   // 归一化，原点左下
            let top = 1.0 - box.maxY
            let centerX = box.midX
            let kind = classify(cgImage: cgImage, box: box, text: text)
            parsed.append(ParsedLine(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                     kind: kind, top: CGFloat(top), centerX: CGFloat(centerX)))
        }
        parsed.sort { $0.top < $1.top }

        let session = extractSession(from: parsed)
        let incoming = tailFromHer(parsed)
        return ScreenParse(session: session, lines: parsed, incomingFromHer: incoming)
    }

    /// (会话, 对方消息) 签名：和上次一样就跳过（PC 端 seen 机制的简化版）
    func isNewContent(session: String, incoming: String) -> Bool {
        let sig = "\(session)\u{1}\(incoming)"
        guard sig != lastSignature else { return false }
        lastSignature = sig
        return true
    }

    func resetSignature() { lastSignature = nil }

    // MARK: - 会话名（read_title 移植）

    private func extractSession(from lines: [ParsedLine]) -> String {
        // 状态栏噪声：时间 / 电量 / 纯符号；状态栏约占顶部 4%
        func isStatusBarNoise(_ s: String) -> Bool {
            if s.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil { return true }
            if s.range(of: #"^\d{1,3}%$"#, options: .regularExpression) != nil { return true }
            return false
        }
        let candidates = lines.filter { $0.top >= 0.04 && !isStatusBarNoise($0.text) }
        guard let first = candidates.first else { return "" }
        // 同一行（top 相差 <1.2%）里取最左的
        let row = candidates.filter { abs($0.top - first.top) < 0.012 }
        let leftmost = row.min(by: { $0.centerX < $1.centerX }) ?? first
        // 群聊 "(422)" / "（422）" 后缀去掉，只留名字当 key
        var name = leftmost.text
        if let range = name.range(of: #"\s*[（(]\d+[)）]\s*$"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 末尾连续的对方消息（_tail_from_her 移植）

    private func tailFromHer(_ lines: [ParsedLine]) -> String {
        // 先过滤掉非消息行
        let messages = lines.filter { line in
            if line.kind != .her && line.kind != .me { return false }
            if isTimeStamp(line.text) { return false }
            if isUINoise(line.text) { return false }
            // 水平居中的行 = 微信系统提示（"对方已通过你的朋友验证请求"等）
            if abs(line.centerX - 0.5) <= 0.15 { return false }
            return true
        }
        var parts: [String] = []
        for line in messages.reversed() {
            if line.kind != .her { break }
            if !line.text.isEmpty { parts.append(line.text) }
        }
        parts.reverse()
        return parts.joined(separator: "\n")
    }

    /// 微信时间戳："14:15" / "昨天 14:15" / "星期二 14:15" / "9月20日 14:15" / "2026年9月20日 14:15"
    private func isTimeStamp(_ text: String) -> Bool {
        text.range(of: #"^(.{0,12}?)\s*(\d{1,2}):(\d{2})\s*$"#, options: .regularExpression) != nil
    }

    /// 弹窗按钮字（PC 端 _UI_NOISE）
    private func isUINoise(_ text: String) -> Bool {
        let noise: Set<String> = ["開", "X", "×", "✕", "✖", "⊗", "关闭"]
        return noise.contains(text.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - 颜色分类（who_said 移植）

    private func classify(cgImage: CGImage, box: CGRect, text: String) -> BubbleKind {
        guard let stats = sampleBox(cgImage: cgImage, box: box) else { return .gray }
        let bg = stats.bg
        // 图片/表情包里的字：颜色杂（>40 种）且众数占比 <45% → 丢
        if stats.kinds > 40 && stats.topRatio < 0.45 { return .image }
        // 绿底 → 自己发的
        if bg.g > bg.r + 40 && bg.g > bg.b + 40 { return .me }
        // 非绿且文字对底色对比度 ≥150 → 对方
        if stats.maxContrast >= 150 { return .her }
        return .gray
    }

    private struct BoxStats {
        var bg: RGB
        var kinds: Int
        var topRatio: Double
        var maxContrast: Double
    }

    private struct RGB {
        var r: Double, g: Double, b: Double
        var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }
    }

    /// 从 CGImage 上框内区域采样：量化直方图找主色（众数桶），
    /// 同时统计颜色种类数与文字对比度。对应 PC 端 who_said 的 numpy 统计。
    private func sampleBox(cgImage: CGImage, box: CGRect) -> BoxStats? {
        let w = cgImage.width, h = cgImage.height
        // Vision 框（归一化、左下原点）→ 像素坐标（左上原点）
        let x0 = Int((box.minX * CGFloat(w)).rounded())
        let x1 = Int((box.maxX * CGFloat(w)).rounded())
        let y0 = Int(((1.0 - box.maxY) * CGFloat(h)).rounded())
        let y1 = Int(((1.0 - box.minY) * CGFloat(h)).rounded())
        guard x1 > x0, y1 > y0 else { return nil }
        // 越界框跳过颜色判定
        guard x0 >= 0, y0 >= 0, x1 <= w, y1 <= h else { return nil }

        // 采样步长：框内最多采 ~2000 点，控制耗时
        let step = max(1, Int(sqrt(Double((x1 - x0) * (y1 - y0)) / 2000.0)))

        guard let provider = cgImage.dataProvider,
              let data = provider.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }
        let bpp = cgImage.bitsPerPixel / 8
        let rowBytes = cgImage.bytesPerRow
        guard bpp == 4 else { return nil }

        // 字节序：CIContext 产出通常是 BGRA（小端 32bit）；按 bitmapInfo 判断，别猜
        let littleEndian = cgImage.bitmapInfo.contains(.order16Little)
            || cgImage.bitmapInfo.contains(.order32Little)
        let rOff = littleEndian ? 2 : 0
        let bOff = littleEndian ? 0 : 2

        var buckets: [Int: (count: Int, r: Double, g: Double, b: Double)] = [:]
        buckets.reserveCapacity(256)
        var total = 0

        var y = y0
        while y < y1 {
            var x = x0
            while x < x1 {
                let offset = y * rowBytes + x * bpp
                let r = Double(ptr[offset + rOff])
                let g = Double(ptr[offset + 1])
                let b = Double(ptr[offset + bOff])
                let key = ((Int(r) >> 3) << 10) | ((Int(g) >> 3) << 5) | (Int(b) >> 3)
                var entry = buckets[key] ?? (0, 0, 0, 0)
                entry.count += 1
                entry.r += r; entry.g += g; entry.b += b
                buckets[key] = entry
                total += 1
                x += step
            }
            y += step
        }
        guard total > 0,
              let top = buckets.max(by: { $0.value.count < $1.value.count }) else {
            return nil
        }
        let topCount = top.value.count
        let bg = RGB(r: top.value.r / Double(topCount),
                     g: top.value.g / Double(topCount),
                     b: top.value.b / Double(topCount))

        // 对比度：用「每桶均值与主色亮度的最大差」近似 PC 端的 diff.max()
        // （单色气泡：主桶=底色，其余少量像素=文字，差值足够判 her/gray）
        var maxContrast = 0.0
        for (_, v) in buckets {
            let n = Double(max(v.count, 1))
            let lum = 0.299 * (v.r / n) + 0.587 * (v.g / n) + 0.114 * (v.b / n)
            maxContrast = max(maxContrast, abs(lum - bg.luminance))
        }

        return BoxStats(bg: bg, kinds: buckets.count,
                        topRatio: Double(topCount) / Double(total),
                        maxContrast: maxContrast)
    }

    private func renderCGImage(pixelBuffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        return ciContext.createCGImage(image, from: image.extent)
    }
}
