import Foundation
import Vision
import CoreImage
import UIKit

// =====================================================================
//  OCRPipeline：录屏帧 → 屏幕文本解析（会话名 + 她/我消息行）
// =====================================================================
//  移植自 PC 端 app/ocr.py 的判定逻辑（阈值经真实微信截图校准，
//  校准工具 tools/calibrate.py，样本见 2026-10-17 用户提供的 11 张截图）：
//   - who_said()：按 OCR 框内**颜色**分类，不看 x 坐标
//       绿底 → me（自己，实测微信绿 RGB≈(167,229,121)）；
//       近白底（亮度≥200 且通道极差<24）+ 文字对比度 ≥150 → her（对方）；
//       颜色杂（>40 种）且众数占比 <45% → 图片/表情包，丢；
//       其余（红包/转账彩色卡片、深色壁纸上的浅色系统提示）→ image，丢
//   - read_title()：最靠上一行、**水平最接近中线**的文本 = 会话名
//   - parse_time()：时间戳行（带 HH:MM）跳过
//   - _centered()：水平居中的行 = 微信系统提示，跳过
//   - 区域过滤：导航栏（top<0.09）和输入栏/键盘区（top>inputBarTop）不算消息
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

        return analyze(observations: observations, cgImage: cgImage)
    }

    /// 诊断入口：直接解析一张静态图（相册里的微信截图），不做节流。
    /// 主 App「诊断」页用——不开录屏也能验证 OCR 解析 + 颜色分类是否工作。
    func parse(image: CGImage) -> ScreenParse? {
        var observations: [VNRecognizedTextObservation] = []
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([request])
            observations = request.results ?? []
        } catch {
            return nil
        }
        guard !observations.isEmpty else { return nil }
        // 大图先缩到长边 1024 再做颜色采样：照片分辨率比录屏帧高，不缩会吃到几十 MB 内存
        let scaled = downscaledImage(image, maxLongEdge: 1024) ?? image
        return analyze(observations: observations, cgImage: scaled)
    }

    /// Vision 观察结果 + 采样图 → 分类后的行。两条入口（录屏帧 / 静态图）共用。
    private func analyze(observations: [VNRecognizedTextObservation],
                         cgImage: CGImage) -> ScreenParse? {
        // 输入栏/键盘区顶部 y（归一化）。微信布局：有键盘时输入栏在 ~0.79，
        // 无键盘时在 ~0.90。该区域以下是自己的输入内容和键盘，永远不是对话消息。
        let inputBarTop = inputBarTopY(cgImage)

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
        let incoming = tailFromHer(parsed, inputBarTop: inputBarTop)
        return ScreenParse(session: session, lines: parsed, incomingFromHer: incoming)
    }

    // MARK: - 输入栏/键盘区域检测

    /// 键盘是否弹出：看屏幕最底部（y 87%-99%）的浅色密度。
    /// 键盘 = 浅灰按键(≈240) + 深色缝隙 + 字母，近白占比约 40%；
    /// 无键盘时该区域是输入栏的白底，占比 60%+（实测 21928e 有键盘 39%，
    /// 696221/6aef46 无键盘 65%）。
    private func keyboardVisible(_ cgImage: CGImage) -> Bool {
        guard let ratio = paleRatio(cgImage, yFrom: 0.87, yTo: 0.99) else { return false }
        return ratio < 0.5
    }

    /// 输入栏/键盘区顶部的 y（归一化）。消息永远不会进入这个区域。
    private func inputBarTopY(_ cgImage: CGImage) -> Double {
        keyboardVisible(cgImage) ? 0.775 : 0.88
    }

    /// 区域近白像素占比（>235,235,235）。复用 sampleBox 的像素访问方式。
    private func paleRatio(_ cgImage: CGImage, yFrom: Double, yTo: Double) -> Double? {
        let w = cgImage.width, h = cgImage.height
        let y0 = Int((yFrom * Double(h)).rounded()), y1 = Int((yTo * Double(h)).rounded())
        guard y1 > y0, y0 >= 0, y1 <= h, w > 0 else { return nil }
        guard let provider = cgImage.dataProvider,
              let data = provider.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }
        let bpp = cgImage.bitsPerPixel / 8
        let rowBytes = cgImage.bytesPerRow
        guard bpp == 4 else { return nil }
        let littleEndian = cgImage.bitmapInfo.contains(.byteOrder16Little)
            || cgImage.bitmapInfo.contains(.byteOrder32Little)
        let rOff = littleEndian ? 2 : 0
        let bOff = littleEndian ? 0 : 2
        // 每 4 行采 1 行、每行每 4 像素采 1 个，够统计占比
        var pale = 0, total = 0
        var y = y0
        while y < y1 {
            var x = 0
            while x < w {
                let offset = y * rowBytes + x * bpp
                let r = ptr[offset + rOff], g = ptr[offset + 1], b = ptr[offset + bOff]
                if r > 235 && g > 235 && b > 235 { pale += 1 }
                total += 1
                x += 4
            }
            y += 4
        }
        guard total > 0 else { return nil }
        return Double(pale) / Double(total)
    }

    /// 等比缩小图片（长边封顶）。录屏扩展内存上限约 50MB，全屏帧不缩会被系统杀掉。
    private func downscaledImage(_ image: CGImage, maxLongEdge: CGFloat) -> CGImage? {
        let longEdge = CGFloat(max(image.width, image.height))
        guard longEdge > maxLongEdge else { return image }
        let scale = maxLongEdge / longEdge
        let w = Int((CGFloat(image.width) * scale).rounded())
        let h = Int((CGFloat(image.height) * scale).rounded())
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
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
        // 同一行（top 相差 <1.2%）里取**水平最接近屏幕中线**的：
        // 微信导航栏是 [返回|标题(居中)|更多]，取最左会命中返回箭头/未读角标（实测踩过）
        let row = candidates.filter { abs($0.top - first.top) < 0.012 }
        let centered = row.min(by: { abs($0.centerX - 0.5) < abs($1.centerX - 0.5) }) ?? first
        // 群聊 "(422)" / "（422）" 后缀去掉，只留名字当 key
        var name = centered.text
        if let range = name.range(of: #"\s*[（(]\d+[)）]\s*$"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 末尾连续的对方消息（_tail_from_her 移植）

    private func tailFromHer(_ lines: [ParsedLine], inputBarTop: Double) -> String {
        // 先过滤掉非消息行
        let messages = lines.filter { line in
            if line.kind != .her && line.kind != .me { return false }
            if isTimeStamp(line.text) { return false }
            if isUINoise(line.text) { return false }
            // 导航栏（<0.09）：返回箭头 / 会话名 / 更多按钮 / 未读角标
            if line.top < 0.09 { return false }
            // 输入栏+键盘区（>inputBarTop）：自己正在输入的文字、键盘字母、候选词
            if Double(line.top) > inputBarTop { return false }
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

    /// 弹窗按钮字 / 导航栏符号（PC 端 _UI_NOISE + 实测截图补充）
    private func isUINoise(_ text: String) -> Bool {
        let noise: Set<String> = ["開", "X", "×", "✕", "✖", "⊗", "关闭",
                                  "…", "...", "‹", "›", "»", "«", ">", "<"]
        return noise.contains(text.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - 颜色分类（who_said 移植）

    private func classify(cgImage: CGImage, box: CGRect, text: String) -> BubbleKind {
        guard let stats = sampleBox(cgImage: cgImage, box: box) else { return .image }
        let bg = stats.bg
        // 图片/表情包里的字：颜色杂（>40 种）且众数占比 <45% → 丢
        if stats.kinds > 40 && stats.topRatio < 0.45 { return .image }
        // 绿底 → 自己发的（实测微信绿 RGB≈(167,229,121)，g-r=62 g-b=108）
        if bg.g > bg.r + 40 && bg.g > bg.b + 40 { return .me }
        // her 气泡：底色近白（浅色气泡）+ 文字对比度高。
        // 实测白气泡底色 (249,249,249)，深色字对比 172-205。
        // 彩色卡片（红包米黄底 luminance≈174 / 转账卡）和深色壁纸上的
        // 浅色系统提示（实测对比度 136-153，贴线翻车过）都不是近白底 → 归 image 丢弃
        let spread = max(bg.r, bg.g, bg.b) - min(bg.r, bg.g, bg.b)
        let isPaleBubble = bg.luminance >= 200 && spread < 24
        if isPaleBubble {
            return stats.maxContrast >= 150 ? .her : .gray
        }
        return .image
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
        let littleEndian = cgImage.bitmapInfo.contains(.byteOrder16Little)
            || cgImage.bitmapInfo.contains(.byteOrder32Little)
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
        // 缩到长边 ≤1024：颜色采样不需要全分辨率（框是归一化的，缩不缩都能对上），
        // 但全屏帧全尺寸渲染一张就是 12MB+，录屏扩展 50MB 上限扛不住几次
        let longEdge = max(image.extent.width, image.extent.height)
        let maxEdge: CGFloat = 1024
        let scaled = longEdge > maxEdge
            ? image.transformed(by: CGAffineTransform(scaleX: maxEdge / longEdge,
                                                      y: maxEdge / longEdge))
            : image
        return ciContext.createCGImage(scaled, from: scaled.extent)
    }
}
