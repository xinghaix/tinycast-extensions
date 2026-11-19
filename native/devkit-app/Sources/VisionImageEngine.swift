import AppKit
import CoreGraphics
import CoreML
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

// MARK: - 1. Apple Vision Offline OCR & Barcode Scanner

struct OcrLineBlock: Identifiable, Sendable {
    let id: Int
    let text: String
    let confidence: Float
}

struct DetectedBarcode: Identifiable, Sendable {
    let id: Int
    let symbology: String
    let payload: String
}

struct VisionScanResult: Sendable {
    let fullText: String
    let lines: [OcrLineBlock]
    let barcodes: [DetectedBarcode]
    let imageWidth: Int
    let imageHeight: Int
    let elapsedMs: Int
}

enum VisionImageError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}

enum VisionImageEngine {
    static let languagePresets: [(id: String, title: String, codes: [String])] = [
        ("zh-en", "中英混排 (推荐)", ["zh-Hans", "zh-Hant", "en-US"]),
        ("en", "仅英文 / 代码", ["en-US"]),
        ("cjk-en", "简繁日英", ["zh-Hans", "zh-Hant", "ja-JP", "en-US"]),
    ]

    static func scanImageData(
        _ data: Data,
        accurate: Bool = true,
        languages: [String] = ["zh-Hans", "zh-Hant", "en-US"]
    ) async throws -> VisionScanResult {
        try await Task.detached(priority: .userInitiated) {
            try scanImageDataSync(data, accurate: accurate, languages: languages)
        }.value
    }

    static var isVirtualMachine: Bool {
        var v: Int32 = 0
        var sz = MemoryLayout<Int32>.size
        return sysctlbyname("kern.hv_vmm_present", &v, &sz, nil, 0) == 0 && v != 0
    }

    private static func configureCpuCompute(for request: VNRequest, cpuDevice: MLComputeDevice) {
        let stageMap = (try? request.supportedComputeStageDevices) ?? [:]
        if !stageMap.isEmpty {
            for (stage, devices) in stageMap {
                let cpuForStage = devices.first(where: {
                    if case .cpu = $0 { return true }
                    return false
                }) ?? cpuDevice
                request.setComputeDevice(cpuForStage, for: stage)
            }
        } else {
            request.setComputeDevice(cpuDevice, for: .main)
        }
    }

    static func scanImageDataSync(
        _ data: Data,
        accurate: Bool = true,
        languages: [String] = ["zh-Hans", "zh-Hant", "en-US"]
    ) throws -> VisionScanResult {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw VisionImageError.message("无法解码图片数据（支持 PNG / JPEG / HEIC / TIFF / WebP / GIF）")
        }

        let start = DispatchTime.now().uptimeNanoseconds

        func perform(cpuOnly: Bool) throws -> ([VNRecognizedTextObservation], [VNBarcodeObservation]) {
            let textReq = VNRecognizeTextRequest()
            textReq.recognitionLevel = accurate ? .accurate : .fast
            textReq.usesLanguageCorrection = true
            textReq.automaticallyDetectsLanguage = true
            textReq.recognitionLanguages = languages

            let barcodeReq = VNDetectBarcodesRequest()
            if cpuOnly,
               let cpuDevice = MLComputeDevice.allComputeDevices.first(where: {
                   if case .cpu = $0 { return true }
                   return false
               }) {
                configureCpuCompute(for: textReq, cpuDevice: cpuDevice)
                configureCpuCompute(for: barcodeReq, cpuDevice: cpuDevice)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([textReq, barcodeReq])
                return (textReq.results ?? [], barcodeReq.results ?? [])
            } catch {
                // Retry barcode-only if text recognizer fails on minimal headless runner
                let fallbackHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try fallbackHandler.perform([barcodeReq])
                return ([], barcodeReq.results ?? [])
            }
        }

        let textObs: [VNRecognizedTextObservation]
        let barcodeObs: [VNBarcodeObservation]
        if isVirtualMachine {
            (textObs, barcodeObs) = try perform(cpuOnly: true)
        } else {
            do {
                (textObs, barcodeObs) = try perform(cpuOnly: false)
            } catch {
                (textObs, barcodeObs) = try perform(cpuOnly: true)
            }
        }

        // Vision boundingBox origin is bottom-left; sort top-to-bottom, left-to-right.
        let sortedTextObs = textObs.sorted { a, b in
            let ay = a.boundingBox.midY
            let by = b.boundingBox.midY
            if abs(ay - by) > 0.015 {
                return ay > by
            }
            return a.boundingBox.minX < b.boundingBox.minX
        }

        var lines: [OcrLineBlock] = []
        for (idx, obs) in sortedTextObs.enumerated() {
            if let top = obs.topCandidates(1).first, !top.string.isEmpty {
                lines.append(OcrLineBlock(id: idx, text: top.string, confidence: top.confidence))
            }
        }

        var barcodes: [DetectedBarcode] = []
        var seenBarcodes = Set<String>()
        for (idx, obs) in barcodeObs.enumerated() {
            if let payload = obs.payloadStringValue, !payload.isEmpty {
                let sym = obs.symbology.rawValue
                    .replacingOccurrences(of: "VNBarcodeSymbology", with: "")
                let dedupeKey = "\(sym):\(payload)"
                if seenBarcodes.insert(dedupeKey).inserted {
                    barcodes.append(DetectedBarcode(id: idx, symbology: sym, payload: payload))
                }
            }
        }

        let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        return VisionScanResult(
            fullText: lines.map(\.text).joined(separator: "\n"),
            lines: lines,
            barcodes: barcodes,
            imageWidth: cgImage.width,
            imageHeight: cgImage.height,
            elapsedMs: elapsedMs
        )
    }

    static func captureScreenRegion() async -> Data? {
        await Task.detached(priority: .userInitiated) {
            let tmpUrl = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("tinycast-ocr-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: tmpUrl) }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            proc.arguments = ["-i", "-r", tmpUrl.path]
            do {
                try proc.run()
                proc.waitUntilExit()
            } catch {
                return nil
            }
            guard proc.terminationStatus == 0,
                  let data = try? Data(contentsOf: tmpUrl),
                  !data.isEmpty else {
                return nil
            }
            return data
        }.value
    }
}

// MARK: - 2. Image Converter, Resizer, EXIF Stripper & DataURI Engine

enum ImageExportFormat: String, CaseIterable, Identifiable, Sendable {
    case png = "PNG"
    case jpeg = "JPEG"
    case heic = "HEIC"
    case tiff = "TIFF"
    case gif = "GIF"
    case webp = "WebP"

    var id: String { rawValue }

    var mimeType: String {
        switch self {
        case .png: return "image/png"
        case .jpeg: return "image/jpeg"
        case .heic: return "image/heic"
        case .tiff: return "image/tiff"
        case .gif: return "image/gif"
        case .webp: return "image/webp"
        }
    }

    var fileExtension: String {
        rawValue.lowercased()
    }

    var utTypeIdentifier: String {
        switch self {
        case .png: return UTType.png.identifier
        case .jpeg: return UTType.jpeg.identifier
        case .heic: return UTType.heic.identifier
        case .tiff: return UTType.tiff.identifier
        case .gif: return UTType.gif.identifier
        case .webp: return UTType.webP.identifier
        }
    }

    var supportsQualitySlider: Bool {
        self == .jpeg || self == .heic || self == .webp
    }
}

struct ImageMetadataEntry: Identifiable, Sendable {
    let id: Int
    let section: String
    let key: String
    let value: String
}

struct ImageSourceInfo: Sendable {
    let width: Int
    let height: Int
    let byteSize: Int
    let formatName: String
    let colorModel: String
    let bitDepth: Int
    let hasAlpha: Bool
    let hasGpsMetadata: Bool
    let exifCount: Int
    let metadataEntries: [ImageMetadataEntry]
}

struct ImageConvertResult: Sendable {
    let outputData: Data
    let format: ImageExportFormat
    let width: Int
    let height: Int
    let originalBytes: Int
    let outputBytes: Int
    let strippedMetadata: Bool

    var dataUri: String {
        "data:\(format.mimeType);base64,\(outputData.base64EncodedString())"
    }
}

enum ImageToolEngine {
    static var cwebpExecutablePath: String? {
        for candidate in ["/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    static func readClipboardImageData() -> Data? {
        let pb = NSPasteboard.general
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let d = pb.data(forType: type), !d.isEmpty {
                return d
            }
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let firstUrl = urls.first,
           let d = try? Data(contentsOf: firstUrl),
           CGImageSourceCreateWithData(d as CFData, nil) != nil {
            return d
        }
        if let str = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if str.hasPrefix("data:image/"), let comma = str.firstIndex(of: ",") {
                let b64 = String(str[str.index(after: comma)...])
                if let d = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) {
                    return d
                }
            }
        }
        return nil
    }

    static func inspectImageData(_ data: Data) -> ImageSourceInfo? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let srcType = (CGImageSourceGetType(src) as String?) ?? "unknown"
        let fmtName = UTType(srcType)?.preferredFilenameExtension?.uppercased() ?? srcType
        let props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]) ?? [:]

        let cgImg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        let width = (props[kCGImagePropertyPixelWidth as String] as? Int) ?? cgImg?.width ?? 0
        let height = (props[kCGImagePropertyPixelHeight as String] as? Int) ?? cgImg?.height ?? 0
        let depth = (props[kCGImagePropertyDepth as String] as? Int) ?? cgImg?.bitsPerComponent ?? 8
        let colorModel = (props[kCGImagePropertyColorModel as String] as? String) ?? "RGB"
        let hasAlpha = (props[kCGImagePropertyHasAlpha as String] as? Bool) ?? (cgImg.map {
            $0.alphaInfo != CGImageAlphaInfo.none
                && $0.alphaInfo != CGImageAlphaInfo.noneSkipLast
                && $0.alphaInfo != CGImageAlphaInfo.noneSkipFirst
        } ?? false)

        var entries: [ImageMetadataEntry] = []
        var counter = 0
        var hasGps = false
        var exifCount = 0

        let dictMappings: [(key: CFString, label: String)] = [
            (kCGImagePropertyGPSDictionary, "GPS"),
            (kCGImagePropertyExifDictionary, "EXIF"),
            (kCGImagePropertyTIFFDictionary, "TIFF"),
            (kCGImagePropertyIPTCDictionary, "IPTC"),
            (kCGImagePropertyPNGDictionary, "PNG"),
        ]

        for (dictKey, sectionLabel) in dictMappings {
            if let sub = props[dictKey as String] as? [String: Any], !sub.isEmpty {
                if dictKey == kCGImagePropertyGPSDictionary { hasGps = true }
                exifCount += sub.count
                for k in sub.keys.sorted() {
                    entries.append(ImageMetadataEntry(
                        id: counter,
                        section: sectionLabel,
                        key: k,
                        value: "\(sub[k] ?? "")"
                    ))
                    counter += 1
                }
            }
        }

        return ImageSourceInfo(
            width: width,
            height: height,
            byteSize: data.count,
            formatName: fmtName,
            colorModel: colorModel,
            bitDepth: depth,
            hasAlpha: hasAlpha,
            hasGpsMetadata: hasGps,
            exifCount: exifCount,
            metadataEntries: entries
        )
    }

    static func convertImageData(
        _ data: Data,
        format: ImageExportFormat,
        quality: Double,
        maxWidth: Int?,
        scalePercent: Int?,
        stripMetadata: Bool
    ) async throws -> ImageConvertResult {
        try await Task.detached(priority: .userInitiated) {
            try convertImageDataSync(
                data,
                format: format,
                quality: quality,
                maxWidth: maxWidth,
                scalePercent: scalePercent,
                stripMetadata: stripMetadata
            )
        }.value
    }

    static func convertImageDataSync(
        _ data: Data,
        format: ImageExportFormat,
        quality: Double,
        maxWidth: Int?,
        scalePercent: Int?,
        stripMetadata: Bool
    ) throws -> ImageConvertResult {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let originalImg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw VisionImageError.message("无法读取输入图片")
        }

        var targetW = originalImg.width
        var targetH = originalImg.height

        if let pct = scalePercent, pct > 0 && pct < 100 {
            targetW = max(1, Int((Double(originalImg.width) * Double(pct) / 100.0).rounded()))
            targetH = max(1, Int((Double(originalImg.height) * Double(pct) / 100.0).rounded()))
        }
        if let capW = maxWidth, capW > 0, targetW > capW {
            let ratio = Double(capW) / Double(targetW)
            targetW = capW
            targetH = max(1, Int((Double(targetH) * ratio).rounded()))
        }

        let workingImage: CGImage
        let needsOpaque = (format == .jpeg)
        if targetW != originalImg.width || targetH != originalImg.height || stripMetadata || needsOpaque {
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            let bitmapInfo: UInt32 = needsOpaque
                ? CGImageAlphaInfo.noneSkipLast.rawValue
                : CGImageAlphaInfo.premultipliedLast.rawValue
            guard let ctx = CGContext(
                data: nil,
                width: targetW,
                height: targetH,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                throw VisionImageError.message("无法创建 CoreGraphics 画布")
            }
            ctx.interpolationQuality = .high
            if needsOpaque {
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: targetW, height: targetH))
            }
            ctx.draw(originalImg, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
            guard let rendered = ctx.makeImage() else {
                throw VisionImageError.message("图片缩放渲染失败")
            }
            workingImage = rendered
        } else {
            workingImage = originalImg
        }

        if format == .webp {
            let pngData = try encodeWithImageIO(workingImage, uti: UTType.png.identifier, quality: 1.0, preservedProps: nil)
            let webpData = try encodeWebpViaCli(pngData: pngData, quality: quality, stripMetadata: stripMetadata)
            return ImageConvertResult(
                outputData: webpData,
                format: format,
                width: workingImage.width,
                height: workingImage.height,
                originalBytes: data.count,
                outputBytes: webpData.count,
                strippedMetadata: stripMetadata
            )
        }

        var preservedProps: [String: Any]? = nil
        if !stripMetadata, let srcProps = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] {
            var filtered = srcProps
            filtered.removeValue(forKey: kCGImagePropertyPixelWidth as String)
            filtered.removeValue(forKey: kCGImagePropertyPixelHeight as String)
            preservedProps = filtered
        }

        let outData = try encodeWithImageIO(
            workingImage,
            uti: format.utTypeIdentifier,
            quality: quality,
            preservedProps: preservedProps
        )

        return ImageConvertResult(
            outputData: outData,
            format: format,
            width: workingImage.width,
            height: workingImage.height,
            originalBytes: data.count,
            outputBytes: outData.count,
            strippedMetadata: stripMetadata
        )
    }

    private static func encodeWithImageIO(
        _ cgImage: CGImage,
        uti: String,
        quality: Double,
        preservedProps: [String: Any]?
    ) throws -> Data {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, uti as CFString, 1, nil) else {
            throw VisionImageError.message("当前系统不支持编码为 \(uti)")
        }
        var opts: [String: Any] = preservedProps ?? [:]
        opts[kCGImageDestinationLossyCompressionQuality as String] = min(max(quality, 0.1), 1.0)
        CGImageDestinationAddImage(dest, cgImage, opts as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw VisionImageError.message("ImageIO 图片导出失败")
        }
        return out as Data
    }

    private static func encodeWebpViaCli(pngData: Data, quality: Double, stripMetadata: Bool) throws -> Data {
        guard let cwebp = cwebpExecutablePath else {
            throw VisionImageError.message("未检测到 WebP 编码器 `cwebp`，请执行 `brew install webp` 或选择 PNG / JPEG / HEIC")
        }
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let id = UUID().uuidString
        let inUrl = tmpDir.appendingPathComponent("tinycast-in-\(id).png")
        let outUrl = tmpDir.appendingPathComponent("tinycast-out-\(id).webp")
        defer {
            try? FileManager.default.removeItem(at: inUrl)
            try? FileManager.default.removeItem(at: outUrl)
        }
        try pngData.write(to: inUrl, options: .atomic)
        let qInt = max(1, min(100, Int((quality * 100.0).rounded())))

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cwebp)
        var args = ["-quiet", "-q", "\(qInt)"]
        if stripMetadata {
            args.append(contentsOf: ["-metadata", "none"])
        }
        args.append(contentsOf: [inUrl.path, "-o", outUrl.path])
        proc.arguments = args
        try proc.run()
        proc.waitUntilExit()

        guard proc.terminationStatus == 0, let result = try? Data(contentsOf: outUrl), !result.isEmpty else {
            throw VisionImageError.message("cwebp 编码失败 (exit \(proc.terminationStatus))")
        }
        return result
    }

    static func humanByteSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
