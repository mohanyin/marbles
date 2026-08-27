import AppKit
import Metal
import MetalKit
import simd

struct MarbleGPUInstance {
    var center: SIMD2<Float>
    var radius: Float
    var time: Float
    var colorCount: Float
    var innerDistortion: Float
    var size: Float
    var angle: Float
    var colorBack: SIMD4<Float>
    var colorInner: SIMD4<Float>
    var color0: SIMD4<Float>
    var color1: SIMD4<Float>
    var color2: SIMD4<Float>
    var color3: SIMD4<Float>
    var color4: SIMD4<Float>
}

struct MarbleFrameConstants {
    var viewport: SIMD2<Float>
    var pointsPerPixel: Float
    var pad: SIMD2<Float> = .zero
}

struct MarbleSheetSection {
    var title: String
    var seeds: [UInt64]
}

struct MarbleDrawItem {
    var agent: Agent
    var frame: MarbleFrame
    var now: Date
    var reducedMotion: Bool
}

final class MarbleRenderer: NSObject, MTKViewDelegate {
    private(set) var isReady = false
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private var pipeline: MTLRenderPipelineState?
    private var instanceBuffer: MTLBuffer?
    private var instances: [MarbleGPUInstance] = []
    private var constants = MarbleFrameConstants(
        viewport: SIMD2<Float>(1, 1),
        pointsPerPixel: 1
    )

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        super.init()
        precondition(MemoryLayout<MarbleGPUInstance>.stride == 144)
        pipeline = Self.makePipeline(device: device)
        isReady = pipeline != nil
    }

    func submit(items: [MarbleDrawItem], viewport: CGSize, scale: CGFloat) {
        let width = max(viewport.width * scale, 1)
        let height = max(viewport.height * scale, 1)
        constants = MarbleFrameConstants(
            viewport: SIMD2<Float>(Float(width), Float(height)),
            pointsPerPixel: Float(1 / max(scale, 0.01))
        )
        instances = items
            .sorted { $0.frame.z < $1.frame.z }
            .map { item in
                Self.gpuInstance(
                    agent: item.agent,
                    center: item.frame.center,
                    size: item.frame.size,
                    dim: item.frame.dim,
                    now: item.now,
                    reducedMotion: item.reducedMotion,
                    scale: scale
                )
            }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        constants.viewport = SIMD2<Float>(Float(max(size.width, 1)), Float(max(size.height, 1)))
        constants.pointsPerPixel = Float(1 / max(view.window?.backingScaleFactor ?? view.layer?.contentsScale ?? 2, 0.01))
    }

    func draw(in view: MTKView) {
        guard isReady, let descriptor = view.currentRenderPassDescriptor, let drawable = view.currentDrawable else {
            return
        }
        constants.viewport = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        encode(descriptor: descriptor, wait: false) { drawable.present() }
    }

    func renderSheet(sections: [MarbleSheetSection], tilePoints: CGFloat, columns: Int, background: NSColor, scale: CGFloat) -> NSImage? {
        let gutter: CGFloat = max(8, tilePoints * 0.18)
        let labelH = max(16, tilePoints * 0.32)
        let sectionGap = gutter * 1.4
        let cols = max(columns, 1)
        var blockHeights: [CGFloat] = []
        var totalH = gutter
        for section in sections {
            let rows = Int(ceil(Double(section.seeds.count) / Double(cols)))
            let block = labelH + gutter * 0.4 + CGFloat(rows) * tilePoints + CGFloat(max(rows - 1, 0)) * gutter
            blockHeights.append(block)
            totalH += block + sectionGap
        }
        totalH += gutter - sectionGap
        let widthPts = CGFloat(cols) * tilePoints + CGFloat(cols + 1) * gutter
        let heightPts = totalH
        let pixelW = Int(widthPts * scale)
        let pixelH = Int(heightPts * scale)
        guard pixelW > 0, pixelH > 0 else { return nil }

        var items: [MarbleGPUInstance] = []
        var labels: [(title: String, rect: NSRect)] = []
        let now = Date()
        var yFromTop = gutter
        for (sectionIndex, section) in sections.enumerated() {
            let labelRect = NSRect(
                x: gutter,
                y: heightPts - yFromTop - labelH,
                width: widthPts - gutter * 2,
                height: labelH
            )
            labels.append((section.title, labelRect))
            yFromTop += labelH + gutter * 0.4
            for (index, seed) in section.seeds.enumerated() {
                let col = index % cols
                let row = index / cols
                let cx = gutter + tilePoints / 2 + CGFloat(col) * (tilePoints + gutter)
                let cyFromTop = yFromTop + tilePoints / 2 + CGFloat(row) * (tilePoints + gutter)
                let cy = heightPts - cyFromTop
                var agent = Agent.make(id: "sheet-\(sectionIndex)-\(index)", source: .demo, seed: seed)
                agent.status = .idle
                items.append(
                    Self.gpuInstance(
                        agent: agent,
                        center: CGPoint(x: cx, y: cy),
                        size: tilePoints,
                        dim: 0,
                        now: now,
                        reducedMotion: true,
                        scale: scale
                    )
                )
            }
            yFromTop += blockHeights[sectionIndex] - labelH - gutter * 0.4 + sectionGap
        }

        let previous = instances
        let previousConstants = constants
        instances = items
        constants = MarbleFrameConstants(
            viewport: SIMD2<Float>(Float(pixelW), Float(pixelH)),
            pointsPerPixel: Float(1 / scale)
        )
        defer {
            instances = previous
            constants = previousConstants
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: pixelW,
            height: pixelH,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        let converted = background.usingColorSpace(.deviceRGB) ?? background
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        converted.getRed(&r, green: &g, blue: &b, alpha: &a)
        pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
        pass.colorAttachments[0].storeAction = .store

        encode(descriptor: pass, wait: true, onCompleted: {})
        guard let marbles = image(from: texture) else { return nil }
        return Self.labeledSheet(
            marbles: marbles,
            size: NSSize(width: widthPts, height: heightPts),
            background: background,
            labels: labels
        )
    }

    private static func labeledSheet(
        marbles: NSImage,
        size: NSSize,
        background: NSColor,
        labels: [(title: String, rect: NSRect)]
    ) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        background.setFill()
        NSRect(origin: .zero, size: size).fill()
        marbles.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        (background.usingColorSpace(.deviceRGB) ?? background).getRed(&r, green: &g, blue: &b, alpha: &a)
        let light = 0.299 * r + 0.587 * g + 0.114 * b > 0.55
        let color = light ? NSColor.black : NSColor.white
        for label in labels {
            let fontSize = max(13, label.rect.height * 0.72)
            (label.title as NSString).draw(in: label.rect, withAttributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: color,
            ])
        }
        image.unlockFocus()
        return image
    }

    private func encode(descriptor: MTLRenderPassDescriptor, wait: Bool, onCompleted: @escaping () -> Void) {
        guard let pipeline, let commandBuffer = queue.makeCommandBuffer() else {
            onCompleted()
            return
        }
        let byteCount = max(instances.count, 1) * MemoryLayout<MarbleGPUInstance>.stride
        if instanceBuffer == nil || instanceBuffer!.length < byteCount {
            instanceBuffer = device.makeBuffer(length: byteCount, options: .storageModeShared)
        }
        if !instances.isEmpty, let instanceBuffer {
            instances.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    instanceBuffer.contents().copyMemory(from: base, byteCount: raw.count)
                }
            }
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            onCompleted()
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(instanceBuffer, offset: 0, index: 0)
        var frame = constants
        encoder.setVertexBytes(&frame, length: MemoryLayout<MarbleFrameConstants>.stride, index: 1)
        encoder.setFragmentBytes(&frame, length: MemoryLayout<MarbleFrameConstants>.stride, index: 1)
        if !instances.isEmpty {
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instances.count)
        }
        encoder.endEncoding()
        if wait {
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            onCompleted()
        } else {
            commandBuffer.addCompletedHandler { _ in
                onCompleted()
            }
            commandBuffer.commit()
        }
    }

    private func image(from texture: MTLTexture) -> NSImage? {
        let width = texture.width
        let height = texture.height
        let rowBytes = width * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * height)
        texture.getBytes(
            &pixels,
            bytesPerRow: rowBytes,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: rowBytes,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ), let cg = context.makeImage() else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }

    static func gpuInstance(
        agent: Agent,
        center: CGPoint,
        size: CGFloat,
        dim: CGFloat,
        now: Date,
        reducedMotion: Bool,
        scale: CGFloat
    ) -> MarbleGPUInstance {
        let params = Identity.params(seed: agent.seed)
        let uniforms = MotionEngine.uniforms(for: agent, now: now, reducedMotion: reducedMotion, dim: dim)
        var packed = [SIMD4<Float>](repeating: params.colors.last ?? SIMD4<Float>(1, 1, 1, 1), count: 5)
        for (index, color) in params.colors.prefix(5).enumerated() {
            packed[index] = color
        }
        return MarbleGPUInstance(
            center: SIMD2<Float>(Float(center.x * scale), Float(center.y * scale)),
            radius: Float(size / 2 * scale),
            time: uniforms.time,
            colorCount: Float(params.colors.count),
            innerDistortion: params.innerDistortion,
            size: params.size,
            angle: params.angle,
            colorBack: params.colorBack,
            colorInner: params.colorInner,
            color0: packed[0],
            color1: packed[1],
            color2: packed[2],
            color3: packed[3],
            color4: packed[4]
        )
    }

    private static func makePipeline(device: MTLDevice) -> MTLRenderPipelineState? {
        guard let library = loadLibrary(device: device) else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "marble_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "marble_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func loadLibrary(device: MTLDevice) -> MTLLibrary? {
        if let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
           let library = try? device.makeLibrary(URL: url)
        {
            return library
        }
        if let source = metalSource() {
            return try? device.makeLibrary(source: source, options: nil)
        }
        return nil
    }

    private static func metalSource() -> String? {
        if let url = Bundle.main.url(forResource: "Marble", withExtension: "metal"),
           let source = try? String(contentsOf: url, encoding: .utf8)
        {
            return source
        }
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = directory.appendingPathComponent("Resources/Shaders/Marble.metal")
            if let source = try? String(contentsOf: candidate, encoding: .utf8) {
                return source
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }
}

final class MarbleMetalView: MTKView {
    let marbleRenderer: MarbleRenderer

    init(renderer: MarbleRenderer) {
        self.marbleRenderer = renderer
        super.init(frame: .zero, device: renderer.device)
        delegate = renderer
        colorPixelFormat = .bgra8Unorm_srgb
        colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        isOpaque = false
        layer?.isOpaque = false
        enableSetNeedsDisplay = true
        isPaused = true
        autoResizeDrawable = true
        framebufferOnly = false
        sampleCount = 1
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool {
        get { false }
        set {}
    }
}
