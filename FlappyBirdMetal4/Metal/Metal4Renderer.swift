import Foundation
import Metal
import MetalKit
import simd
import QuartzCore

/// GPU vertex layout matching `VertexIn` in Shaders.metal
struct MeshVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var color: SIMD4<Float>
}

struct FrameUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var _pad0: Float = 0
    var viewProj: simd_float4x4
    var lightDir: SIMD3<Float>
    var _pad1: Float = 0
    var lightColor: SIMD3<Float>
    var ambient: Float
    var eyePos: SIMD3<Float>
    var _pad2: Float = 0
}

/// Primary renderer.
/// - **Mac + iPhone device:** full **Metal 4** path.
/// - **iOS Simulator:** classic Metal path (Metal 4 stubs).
/// Geometry is true 3D meshes (extruded pipes, low-poly bird character, coins, particles).
@MainActor
final class Metal4Renderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice

    #if !targetEnvironment(simulator)
    private let mtl4Queue: any MTL4CommandQueue
    private let commandAllocator: any MTL4CommandAllocator
    private let commandBuffer: any MTL4CommandBuffer
    private let compiler: any MTL4Compiler
    private let residencySet: any MTLResidencySet
    private var vertexArgumentTable: (any MTL4ArgumentTable)!
    private var skyArgumentTable: (any MTL4ArgumentTable)!
    #else
    private let classicQueue: any MTLCommandQueue
    #endif

    private var pipelineState: (any MTLRenderPipelineState)!
    private var skyPipelineState: (any MTLRenderPipelineState)!
    private var depthState: (any MTLDepthStencilState)!
    private var dynamicVertexBuffer: (any MTLBuffer)!
    private var uniformsBuffer: (any MTLBuffer)!
    private var depthTexture: (any MTLTexture)?

    private let maxVertices = 24000
    private var vertexCapacity: Int { maxVertices }

    let game = GameState()

    var onScoreChange: ((Int) -> Void)?
    var onPhaseChange: ((GamePhase) -> Void)?
    var onCoinsChange: ((Int) -> Void)?

    private var lastScore = -1
    private var lastCoins = -1
    private var lastPhase: GamePhase?
    private var lastFrameTime: CFTimeInterval = CACurrentMediaTime()
    private var lastDepthSize: (Int, Int) = (0, 0)

    init?(metalKitView: MTKView) {
        guard let device = metalKitView.device ?? MTLCreateSystemDefaultDevice() else {
            return nil
        }
        self.device = device
        metalKitView.device = device

        #if !targetEnvironment(simulator)
        guard let queue = device.makeMTL4CommandQueue() else {
            print("Metal 4 command queue unavailable — requires Apple silicon + Metal 4 OS.")
            return nil
        }
        guard let allocator = device.makeCommandAllocator() else { return nil }
        guard let cmdBuffer = device.makeCommandBuffer() else { return nil }

        let compilerDesc = MTL4CompilerDescriptor()
        guard let compiler = try? device.makeCompiler(descriptor: compilerDesc) else { return nil }

        let residencyDesc = MTLResidencySetDescriptor()
        residencyDesc.label = "FlappyBirdResidency"
        guard let residency = try? device.makeResidencySet(descriptor: residencyDesc) else { return nil }

        self.mtl4Queue = queue
        self.commandAllocator = allocator
        self.commandBuffer = cmdBuffer
        self.compiler = compiler
        self.residencySet = residency
        #else
        guard let queue = device.makeCommandQueue() else { return nil }
        self.classicQueue = queue
        #endif

        super.init()

        metalKitView.colorPixelFormat = .bgra8Unorm
        metalKitView.depthStencilPixelFormat = .depth32Float
        metalKitView.framebufferOnly = true
        metalKitView.clearColor = MTLClearColor(red: 0.45, green: 0.75, blue: 0.95, alpha: 1)
        metalKitView.preferredFramesPerSecond = 60
        metalKitView.isPaused = false
        metalKitView.enableSetNeedsDisplay = false
        #if os(macOS)
        metalKitView.layer?.isOpaque = true
        #endif

        do {
            try buildPipelines(colorFormat: metalKitView.colorPixelFormat)
            try buildBuffersAndTables()
            buildDepthState()
        } catch {
            print("Metal setup failed: \(error)")
            return nil
        }

        game.resetToReady()
        publishUI()
    }

    // MARK: - Setup

    private func buildPipelines(colorFormat: MTLPixelFormat) throws {
        #if !targetEnvironment(simulator)
        try buildMetal4Pipelines(colorFormat: colorFormat)
        #else
        try buildClassicPipelines(colorFormat: colorFormat)
        #endif
    }

    #if !targetEnvironment(simulator)
    private func buildMetal4Pipelines(colorFormat: MTLPixelFormat) throws {
        let libDesc = MTL4LibraryDescriptor()
        libDesc.source = Self.shaderSource
        libDesc.name = "FlappyShaders"

        let library = try compiler.makeLibrary(descriptor: libDesc)

        let vDesc = MTL4LibraryFunctionDescriptor()
        vDesc.name = "vertex_main"
        vDesc.library = library

        let fDesc = MTL4LibraryFunctionDescriptor()
        fDesc.name = "fragment_main"
        fDesc.library = library

        let pipeDesc = MTL4RenderPipelineDescriptor()
        pipeDesc.vertexFunctionDescriptor = vDesc
        pipeDesc.fragmentFunctionDescriptor = fDesc
        pipeDesc.rasterSampleCount = 1
        pipeDesc.colorAttachments[0].pixelFormat = colorFormat
        pipeDesc.colorAttachments[0].blendingState = .enabled
        pipeDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipeDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipeDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipeDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        // Metal 4 pipelines do not declare depth formats on the descriptor;
        // depth is configured on the render pass + depth-stencil state.

        pipelineState = try compiler.makeRenderPipelineState(descriptor: pipeDesc)

        let skyV = MTL4LibraryFunctionDescriptor()
        skyV.name = "sky_vertex"
        skyV.library = library

        let skyF = MTL4LibraryFunctionDescriptor()
        skyF.name = "sky_fragment"
        skyF.library = library

        let skyDesc = MTL4RenderPipelineDescriptor()
        skyDesc.vertexFunctionDescriptor = skyV
        skyDesc.fragmentFunctionDescriptor = skyF
        skyDesc.rasterSampleCount = 1
        skyDesc.colorAttachments[0].pixelFormat = colorFormat

        skyPipelineState = try compiler.makeRenderPipelineState(descriptor: skyDesc)
    }
    #endif

    #if targetEnvironment(simulator)
    private func buildClassicPipelines(colorFormat: MTLPixelFormat) throws {
        let library = try device.makeLibrary(source: Self.shaderSource, options: nil)

        let pipeDesc = MTLRenderPipelineDescriptor()
        pipeDesc.vertexFunction = library.makeFunction(name: "vertex_main")
        pipeDesc.fragmentFunction = library.makeFunction(name: "fragment_main")
        pipeDesc.colorAttachments[0].pixelFormat = colorFormat
        pipeDesc.colorAttachments[0].isBlendingEnabled = true
        pipeDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipeDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipeDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipeDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeDesc.depthAttachmentPixelFormat = .depth32Float
        pipelineState = try device.makeRenderPipelineState(descriptor: pipeDesc)

        let skyDesc = MTLRenderPipelineDescriptor()
        skyDesc.vertexFunction = library.makeFunction(name: "sky_vertex")
        skyDesc.fragmentFunction = library.makeFunction(name: "sky_fragment")
        skyDesc.colorAttachments[0].pixelFormat = colorFormat
        skyDesc.depthAttachmentPixelFormat = .depth32Float
        skyPipelineState = try device.makeRenderPipelineState(descriptor: skyDesc)
    }
    #endif

    private func buildDepthState() {
        let desc = MTLDepthStencilDescriptor()
        desc.depthCompareFunction = .less
        desc.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: desc)
    }

    private func buildBuffersAndTables() throws {
        let vertexBytes = vertexCapacity * MemoryLayout<MeshVertex>.stride
        guard let vbuf = device.makeBuffer(length: vertexBytes, options: .storageModeShared) else {
            throw RendererError.bufferAllocation
        }
        vbuf.label = "DynamicVertices"
        dynamicVertexBuffer = vbuf

        guard let ubuf = device.makeBuffer(length: MemoryLayout<FrameUniforms>.stride, options: .storageModeShared) else {
            throw RendererError.bufferAllocation
        }
        ubuf.label = "FrameUniforms"
        uniformsBuffer = ubuf

        #if !targetEnvironment(simulator)
        let tableDesc = MTL4ArgumentTableDescriptor()
        tableDesc.maxBufferBindCount = 4
        tableDesc.maxTextureBindCount = 0
        tableDesc.maxSamplerStateBindCount = 0
        tableDesc.initializeBindings = true

        guard let vTable = try? device.makeArgumentTable(descriptor: tableDesc) else {
            throw RendererError.argumentTable
        }
        guard let sTable = try? device.makeArgumentTable(descriptor: tableDesc) else {
            throw RendererError.argumentTable
        }
        vertexArgumentTable = vTable
        skyArgumentTable = sTable

        residencySet.addAllocation(dynamicVertexBuffer)
        residencySet.addAllocation(uniformsBuffer)
        residencySet.commit()
        mtl4Queue.addResidencySet(residencySet)
        #endif
    }

    private func ensureDepthTexture(width: Int, height: Int) {
        if depthTexture != nil, lastDepthSize == (width, height) { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: max(width, 1),
            height: max(height, 1),
            mipmapped: false
        )
        desc.usage = .renderTarget
        desc.storageMode = .private
        depthTexture = device.makeTexture(descriptor: desc)
        lastDepthSize = (width, height)

        #if !targetEnvironment(simulator)
        if let depthTexture {
            residencySet.addAllocation(depthTexture)
            residencySet.commit()
        }
        #endif
    }

    enum RendererError: Error {
        case bufferAllocation
        case argumentTable
    }

    // MARK: - Input

    func handleTap() {
        game.flap()
        publishUI()
    }

    // MARK: - Frame

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        ensureDepthTexture(width: Int(size.width), height: Int(size.height))
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = Float(now - lastFrameTime)
        lastFrameTime = now

        game.update(dt: dt)
        publishUI()

        guard let drawable = view.currentDrawable else { return }
        let drawableTexture = drawable.texture

        let size = view.drawableSize
        let width = Float(size.width)
        let height = Float(size.height)
        guard width > 1, height > 1 else { return }

        ensureDepthTexture(width: Int(size.width), height: Int(size.height))
        guard let depthTexture else { return }

        let viewProj = makeViewProjection(
            drawableWidth: width,
            drawableHeight: height
        )
        let eye = SIMD3<Float>(GameState.worldWidth * 0.5 - 0.6, GameState.worldHeight * 0.52, 14.5)

        var uniforms = FrameUniforms(
            resolution: SIMD2<Float>(width, height),
            time: game.backgroundTime,
            viewProj: viewProj,
            lightDir: simd_normalize(SIMD3<Float>(-0.45, -0.85, -0.35)),
            lightColor: SIMD3<Float>(1.05, 0.98, 0.88),
            ambient: 0.38,
            eyePos: eye
        )
        memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<FrameUniforms>.stride)

        let vertexCount = writeSceneVertices()

        #if !targetEnvironment(simulator)
        drawMetal4(
            drawable: drawable,
            drawableTexture: drawableTexture,
            depthTexture: depthTexture,
            width: width,
            height: height,
            vertexCount: vertexCount
        )
        #else
        drawClassic(
            view: view,
            drawable: drawable,
            depthTexture: depthTexture,
            width: width,
            height: height,
            vertexCount: vertexCount
        )
        #endif
    }

    #if !targetEnvironment(simulator)
    private func drawMetal4(
        drawable: CAMetalDrawable,
        drawableTexture: MTLTexture,
        depthTexture: MTLTexture,
        width: Float,
        height: Float,
        vertexCount: Int
    ) {
        residencySet.addAllocation(drawableTexture)
        residencySet.commit()

        vertexArgumentTable.setAddress(dynamicVertexBuffer.gpuAddress, index: 0)
        vertexArgumentTable.setAddress(uniformsBuffer.gpuAddress, index: 1)
        skyArgumentTable.setAddress(uniformsBuffer.gpuAddress, index: 0)

        mtl4Queue.waitForDrawable(drawable)

        commandAllocator.reset()
        commandBuffer.beginCommandBuffer(allocator: commandAllocator)
        commandBuffer.useResidencySet(residencySet)

        let pass = MTL4RenderPassDescriptor()
        pass.colorAttachments[0].texture = drawableTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.45, green: 0.75, blue: 0.95, alpha: 1)
        pass.depthAttachment.texture = depthTexture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1.0
        pass.renderTargetWidth = drawableTexture.width
        pass.renderTargetHeight = drawableTexture.height

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            commandBuffer.endCommandBuffer()
            return
        }

        encoder.setViewport(MTLViewport(
            originX: 0, originY: 0,
            width: Double(width), height: Double(height),
            znear: 0, zfar: 1
        ))

        // Sky without depth write
        encoder.setRenderPipelineState(skyPipelineState)
        encoder.setArgumentTable(skyArgumentTable, stages: [.vertex, .fragment])
        encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)

        if vertexCount > 0 {
            encoder.setRenderPipelineState(pipelineState)
            encoder.setDepthStencilState(depthState)
            encoder.setArgumentTable(vertexArgumentTable, stages: [.vertex, .fragment])
            encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: vertexCount)
        }

        encoder.endEncoding()
        commandBuffer.endCommandBuffer()

        mtl4Queue.commit([commandBuffer])
        mtl4Queue.signalDrawable(drawable)
        drawable.present()

        residencySet.removeAllocation(drawableTexture)
        residencySet.commit()
    }
    #endif

    #if targetEnvironment(simulator)
    private func drawClassic(
        view: MTKView,
        drawable: CAMetalDrawable,
        depthTexture: MTLTexture,
        width: Float,
        height: Float,
        vertexCount: Int
    ) {
        guard let descriptor = view.currentRenderPassDescriptor else { return }
        descriptor.depthAttachment.texture = depthTexture
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.storeAction = .dontCare
        descriptor.depthAttachment.clearDepth = 1.0

        guard let cmd = classicQueue.makeCommandBuffer() else { return }
        guard let encoder = cmd.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        encoder.setViewport(MTLViewport(
            originX: 0, originY: 0,
            width: Double(width), height: Double(height),
            znear: 0, zfar: 1
        ))

        encoder.setRenderPipelineState(skyPipelineState)
        encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        if vertexCount > 0 {
            encoder.setRenderPipelineState(pipelineState)
            encoder.setDepthStencilState(depthState)
            encoder.setVertexBuffer(dynamicVertexBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 1)
            encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        }

        encoder.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
    #endif

    private func publishUI() {
        if game.score != lastScore {
            lastScore = game.score
            onScoreChange?(game.score)
        }
        if game.coinsCollected != lastCoins {
            lastCoins = game.coinsCollected
            onCoinsChange?(game.coinsCollected)
        }
        if game.phase != lastPhase {
            lastPhase = game.phase
            onPhaseChange?(game.phase)
        }
    }

    // MARK: - Camera

    private func makeViewProjection(drawableWidth: Float, drawableHeight: Float) -> simd_float4x4 {
        let worldW = GameState.worldWidth
        let worldH = GameState.worldHeight
        let worldAspect = worldW / worldH
        let viewAspect = drawableWidth / drawableHeight

        // Eye slightly offset for 3D pop while keeping gameplay readable
        let eye = SIMD3<Float>(worldW * 0.5 - 0.55, worldH * 0.52, 14.5)
        let center = SIMD3<Float>(worldW * 0.5, worldH * 0.5, 0)
        let up = SIMD3<Float>(0, 1, 0)
        let view = lookAt(eye: eye, center: center, up: up)

        // Perspective FOV tuned so world roughly fills the screen
        var fovy: Float = 0.62
        if viewAspect > worldAspect {
            // wider screen — reduce FOV effect via aspect
        } else {
            fovy *= worldAspect / max(viewAspect, 0.01)
        }
        let proj = perspective(fovy: fovy, aspect: viewAspect, near: 0.1, far: 80)
        return proj * view
    }

    private func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = simd_normalize(eye - center)
        let x = simd_normalize(simd_cross(up, z))
        let y = simd_cross(z, x)
        let t = SIMD3<Float>(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye))
        return simd_float4x4(columns: (
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(t.x, t.y, t.z, 1)
        ))
    }

    private func perspective(fovy: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let ys = 1 / tanf(fovy * 0.5)
        let xs = ys / aspect
        let zs = far / (near - far)
        return simd_float4x4(columns: (
            SIMD4<Float>(xs, 0, 0, 0),
            SIMD4<Float>(0, ys, 0, 0),
            SIMD4<Float>(0, 0, zs, -1),
            SIMD4<Float>(0, 0, near * zs, 0)
        ))
    }

    // MARK: - Geometry (CPU → dynamic buffer)

    @discardableResult
    private func writeSceneVertices() -> Int {
        let ptr = dynamicVertexBuffer.contents().bindMemory(to: MeshVertex.self, capacity: vertexCapacity)
        var count = 0

        func appendTri(
            _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>,
            n: SIMD3<Float>, color: SIMD4<Float>
        ) {
            guard count + 3 <= vertexCapacity else { return }
            let nn = simd_normalize(n)
            ptr[count] = MeshVertex(position: a, normal: nn, color: color); count += 1
            ptr[count] = MeshVertex(position: b, normal: nn, color: color); count += 1
            ptr[count] = MeshVertex(position: c, normal: nn, color: color); count += 1
        }

        func appendTriSmooth(
            _ a: SIMD3<Float>, _ na: SIMD3<Float>,
            _ b: SIMD3<Float>, _ nb: SIMD3<Float>,
            _ c: SIMD3<Float>, _ nc: SIMD3<Float>,
            color: SIMD4<Float>
        ) {
            guard count + 3 <= vertexCapacity else { return }
            ptr[count] = MeshVertex(position: a, normal: simd_normalize(na), color: color); count += 1
            ptr[count] = MeshVertex(position: b, normal: simd_normalize(nb), color: color); count += 1
            ptr[count] = MeshVertex(position: c, normal: simd_normalize(nc), color: color); count += 1
        }

        /// Axis-aligned box centered at origin, then transformed by center + size.
        func appendBox(
            center: SIMD3<Float>,
            half: SIMD3<Float>,
            color: SIMD4<Float>,
            colorTop: SIMD4<Float>? = nil,
            colorSide: SIMD4<Float>? = nil
        ) {
            let c = center
            let h = half
            let topC = colorTop ?? color
            let sideC = colorSide ?? SIMD4<Float>(color.x * 0.75, color.y * 0.75, color.z * 0.75, color.w)
            let botC = SIMD4<Float>(color.x * 0.55, color.y * 0.55, color.z * 0.55, color.w)

            // Front (+Z)
            appendTri(
                SIMD3(c.x - h.x, c.y - h.y, c.z + h.z),
                SIMD3(c.x + h.x, c.y - h.y, c.z + h.z),
                SIMD3(c.x + h.x, c.y + h.y, c.z + h.z),
                n: SIMD3(0, 0, 1), color: color
            )
            appendTri(
                SIMD3(c.x - h.x, c.y - h.y, c.z + h.z),
                SIMD3(c.x + h.x, c.y + h.y, c.z + h.z),
                SIMD3(c.x - h.x, c.y + h.y, c.z + h.z),
                n: SIMD3(0, 0, 1), color: color
            )
            // Back (-Z)
            appendTri(
                SIMD3(c.x + h.x, c.y - h.y, c.z - h.z),
                SIMD3(c.x - h.x, c.y - h.y, c.z - h.z),
                SIMD3(c.x - h.x, c.y + h.y, c.z - h.z),
                n: SIMD3(0, 0, -1), color: sideC
            )
            appendTri(
                SIMD3(c.x + h.x, c.y - h.y, c.z - h.z),
                SIMD3(c.x - h.x, c.y + h.y, c.z - h.z),
                SIMD3(c.x + h.x, c.y + h.y, c.z - h.z),
                n: SIMD3(0, 0, -1), color: sideC
            )
            // Right (+X)
            appendTri(
                SIMD3(c.x + h.x, c.y - h.y, c.z + h.z),
                SIMD3(c.x + h.x, c.y - h.y, c.z - h.z),
                SIMD3(c.x + h.x, c.y + h.y, c.z - h.z),
                n: SIMD3(1, 0, 0), color: sideC
            )
            appendTri(
                SIMD3(c.x + h.x, c.y - h.y, c.z + h.z),
                SIMD3(c.x + h.x, c.y + h.y, c.z - h.z),
                SIMD3(c.x + h.x, c.y + h.y, c.z + h.z),
                n: SIMD3(1, 0, 0), color: sideC
            )
            // Left (-X)
            appendTri(
                SIMD3(c.x - h.x, c.y - h.y, c.z - h.z),
                SIMD3(c.x - h.x, c.y - h.y, c.z + h.z),
                SIMD3(c.x - h.x, c.y + h.y, c.z + h.z),
                n: SIMD3(-1, 0, 0), color: sideC
            )
            appendTri(
                SIMD3(c.x - h.x, c.y - h.y, c.z - h.z),
                SIMD3(c.x - h.x, c.y + h.y, c.z + h.z),
                SIMD3(c.x - h.x, c.y + h.y, c.z - h.z),
                n: SIMD3(-1, 0, 0), color: sideC
            )
            // Top (+Y)
            appendTri(
                SIMD3(c.x - h.x, c.y + h.y, c.z + h.z),
                SIMD3(c.x + h.x, c.y + h.y, c.z + h.z),
                SIMD3(c.x + h.x, c.y + h.y, c.z - h.z),
                n: SIMD3(0, 1, 0), color: topC
            )
            appendTri(
                SIMD3(c.x - h.x, c.y + h.y, c.z + h.z),
                SIMD3(c.x + h.x, c.y + h.y, c.z - h.z),
                SIMD3(c.x - h.x, c.y + h.y, c.z - h.z),
                n: SIMD3(0, 1, 0), color: topC
            )
            // Bottom (-Y)
            appendTri(
                SIMD3(c.x - h.x, c.y - h.y, c.z - h.z),
                SIMD3(c.x + h.x, c.y - h.y, c.z - h.z),
                SIMD3(c.x + h.x, c.y - h.y, c.z + h.z),
                n: SIMD3(0, -1, 0), color: botC
            )
            appendTri(
                SIMD3(c.x - h.x, c.y - h.y, c.z - h.z),
                SIMD3(c.x + h.x, c.y - h.y, c.z + h.z),
                SIMD3(c.x - h.x, c.y - h.y, c.z + h.z),
                n: SIMD3(0, -1, 0), color: botC
            )
        }

        /// Low-poly sphere (latitude/longitude) for bird body / coins
        func appendSphere(
            center: SIMD3<Float>,
            radius: Float,
            color: SIMD4<Float>,
            segments: Int = 10,
            rings: Int = 6,
            scale: SIMD3<Float> = SIMD3(1, 1, 1)
        ) {
            for ring in 0..<rings {
                let v0 = Float(ring) / Float(rings)
                let v1 = Float(ring + 1) / Float(rings)
                let theta0 = v0 * Float.pi
                let theta1 = v1 * Float.pi
                for seg in 0..<segments {
                    let u0 = Float(seg) / Float(segments)
                    let u1 = Float(seg + 1) / Float(segments)
                    let phi0 = u0 * Float.pi * 2
                    let phi1 = u1 * Float.pi * 2

                    func point(_ th: Float, _ ph: Float) -> (SIMD3<Float>, SIMD3<Float>) {
                        let n = SIMD3(
                            sinf(th) * cosf(ph),
                            cosf(th),
                            sinf(th) * sinf(ph)
                        )
                        let p = center + n * radius * scale
                        return (p, n)
                    }

                    let (p00, n00) = point(theta0, phi0)
                    let (p10, n10) = point(theta0, phi1)
                    let (p01, n01) = point(theta1, phi0)
                    let (p11, n11) = point(theta1, phi1)

                    if ring != 0 {
                        appendTriSmooth(p00, n00, p10, n10, p11, n11, color: color)
                        appendTriSmooth(p00, n00, p11, n11, p01, n01, color: color)
                    } else {
                        appendTriSmooth(p00, n00, p11, n11, p01, n01, color: color)
                    }
                }
            }
        }

        /// Cylinder along Y for pipe bodies
        func appendCylinderY(
            cx: Float, z: Float,
            y0: Float, y1: Float,
            radius: Float,
            color: SIMD4<Float>,
            segments: Int = 12
        ) {
            let sideC = SIMD4<Float>(color.x * 0.72, color.y * 0.72, color.z * 0.72, color.w)
            for i in 0..<segments {
                let a0 = Float(i) / Float(segments) * Float.pi * 2
                let a1 = Float(i + 1) / Float(segments) * Float.pi * 2
                let n0 = SIMD3(cosf(a0), 0, sinf(a0))
                let n1 = SIMD3(cosf(a1), 0, sinf(a1))
                let p0b = SIMD3(cx + n0.x * radius, y0, z + n0.z * radius)
                let p1b = SIMD3(cx + n1.x * radius, y0, z + n1.z * radius)
                let p0t = SIMD3(cx + n0.x * radius, y1, z + n0.z * radius)
                let p1t = SIMD3(cx + n1.x * radius, y1, z + n1.z * radius)
                appendTriSmooth(p0b, n0, p1b, n1, p1t, n1, color: sideC)
                appendTriSmooth(p0b, n0, p1t, n1, p0t, n0, color: color)
            }
        }

        func appendTorusRing(
            center: SIMD3<Float>,
            majorR: Float,
            minorR: Float,
            color: SIMD4<Float>,
            spin: Float,
            majorSeg: Int = 16,
            minorSeg: Int = 8
        ) {
            let cosS = cosf(spin)
            let sinS = sinf(spin)
            // Spin around Y then slight tilt
            func rot(_ p: SIMD3<Float>) -> SIMD3<Float> {
                let x = p.x * cosS - p.z * sinS
                let z = p.x * sinS + p.z * cosS
                // tilt 20° around X for 3D readability
                let tilt: Float = 0.45
                let y = p.y * cosf(tilt) - z * sinf(tilt)
                let z2 = p.y * sinf(tilt) + z * cosf(tilt)
                return center + SIMD3(x, y, z2)
            }
            func rotN(_ n: SIMD3<Float>) -> SIMD3<Float> {
                let x = n.x * cosS - n.z * sinS
                let z = n.x * sinS + n.z * cosS
                let tilt: Float = 0.45
                let y = n.y * cosf(tilt) - z * sinf(tilt)
                let z2 = n.y * sinf(tilt) + z * cosf(tilt)
                return SIMD3(x, y, z2)
            }

            for i in 0..<majorSeg {
                let u0 = Float(i) / Float(majorSeg) * Float.pi * 2
                let u1 = Float(i + 1) / Float(majorSeg) * Float.pi * 2
                for j in 0..<minorSeg {
                    let v0 = Float(j) / Float(minorSeg) * Float.pi * 2
                    let v1 = Float(j + 1) / Float(minorSeg) * Float.pi * 2

                    func pt(_ u: Float, _ v: Float) -> (SIMD3<Float>, SIMD3<Float>) {
                        let cx = (majorR + minorR * cosf(v)) * cosf(u)
                        let cy = minorR * sinf(v)
                        let cz = (majorR + minorR * cosf(v)) * sinf(u)
                        let n = SIMD3(cosf(v) * cosf(u), sinf(v), cosf(v) * sinf(u))
                        return (rot(SIMD3(cx, cy, cz)), rotN(n))
                    }
                    let (p00, n00) = pt(u0, v0)
                    let (p10, n10) = pt(u1, v0)
                    let (p01, n01) = pt(u0, v1)
                    let (p11, n11) = pt(u1, v1)
                    appendTriSmooth(p00, n00, p10, n10, p11, n11, color: color)
                    appendTriSmooth(p00, n00, p11, n11, p01, n01, color: color)
                }
            }
        }

        let worldW = GameState.worldWidth
        let worldH = GameState.worldHeight
        let groundY = GameState.groundHeight

        // ---- Far hills (parallax layers) ----
        let hillColors: [(SIMD4<Float>, Float)] = [
            (SIMD4(0.28, 0.52, 0.36, 1), -2.8),
            (SIMD4(0.34, 0.62, 0.32, 1), -1.6),
            (SIMD4(0.40, 0.70, 0.34, 1), -0.7)
        ]
        for (ci, pair) in hillColors.enumerated() {
            let (col, z) = pair
            let scroll = fmodf(game.backgroundTime * (0.25 + Float(ci) * 0.12), 4.0)
            for i in 0..<5 {
                let cx = Float(i) * 2.4 - scroll + Float(ci) * 0.5
                let h: Float = 1.4 + Float((i + ci) % 3) * 0.55
                let w: Float = 1.5 + Float(i % 2) * 0.4
                appendBox(
                    center: SIMD3(cx, groundY + h * 0.5, z),
                    half: SIMD3(w * 0.5, h * 0.5, 0.35 + Float(ci) * 0.1),
                    color: col,
                    colorTop: SIMD4(col.x + 0.08, col.y + 0.1, col.z + 0.05, 1)
                )
            }
        }

        // ---- Pipes (3D cylinders + lips) ----
        let pipeGreen = SIMD4<Float>(0.18, 0.78, 0.32, 1)
        let lipColor = SIMD4<Float>(0.28, 0.92, 0.40, 1)
        let pipeR = GameState.pipeWidth * 0.42
        let gap = GameState.pipeGap

        for pipe in game.pipes {
            let gapBottom = pipe.gapY - gap * 0.5
            let gapTop = pipe.gapY + gap * 0.5
            let z: Float = 0

            // Bottom pipe
            appendCylinderY(cx: pipe.x, z: z, y0: groundY, y1: gapBottom - 0.02, radius: pipeR, color: pipeGreen)
            // Bottom lip (thicker torus-like box ring)
            appendBox(
                center: SIMD3(pipe.x, gapBottom - 0.18, z),
                half: SIMD3(pipeR + 0.14, 0.18, pipeR + 0.14),
                color: lipColor,
                colorTop: SIMD4(0.45, 1.0, 0.5, 1)
            )

            // Top pipe
            appendCylinderY(cx: pipe.x, z: z, y0: gapTop + 0.02, y1: worldH + 0.3, radius: pipeR, color: pipeGreen)
            appendBox(
                center: SIMD3(pipe.x, gapTop + 0.18, z),
                half: SIMD3(pipeR + 0.14, 0.18, pipeR + 0.14),
                color: lipColor,
                colorTop: SIMD4(0.45, 1.0, 0.5, 1)
            )

            // Gold coin ring in gap
            if pipe.hasCoin && !pipe.coinCollected {
                let spin = game.backgroundTime * 3.5 + pipe.x
                appendTorusRing(
                    center: SIMD3(pipe.x, pipe.gapY, 0.15),
                    majorR: 0.22,
                    minorR: 0.07,
                    color: SIMD4(1.0, 0.82, 0.15, 1),
                    spin: spin
                )
                // Inner disc highlight
                appendSphere(
                    center: SIMD3(pipe.x, pipe.gapY, 0.15),
                    radius: 0.12,
                    color: SIMD4(1.0, 0.92, 0.35, 1),
                    segments: 8,
                    rings: 4,
                    scale: SIMD3(1, 1, 0.35)
                )
            }
        }

        // ---- Ground platform (thick 3D slab) ----
        let dirt = SIMD4<Float>(0.68, 0.48, 0.26, 1)
        let grass = SIMD4<Float>(0.32, 0.78, 0.28, 1)
        appendBox(
            center: SIMD3(worldW * 0.5, groundY * 0.5 - 0.15, 0.2),
            half: SIMD3(worldW * 0.55 + 1.5, groundY * 0.5 + 0.15, 1.4),
            color: dirt,
            colorTop: grass,
            colorSide: SIMD4(0.52, 0.36, 0.18, 1)
        )

        // Grass ridge blocks scrolling
        var sx = -game.groundOffset
        let stripe = SIMD4<Float>(0.26, 0.68, 0.22, 1)
        while sx < worldW + 1 {
            appendBox(
                center: SIMD3(sx + 0.28, groundY + 0.06, 0.85),
                half: SIMD3(0.28, 0.08, 0.35),
                color: stripe,
                colorTop: SIMD4(0.4, 0.9, 0.35, 1)
            )
            sx += 1.2
        }

        // ---- Bird character (3D) ----
        let bx = GameState.birdX
        let by = game.birdY
        let rot = game.birdRotation
        let cosR = cosf(rot)
        let sinR = sinf(rot)
        let wingAngle = sinf(game.wingPhase) * 0.75

        func birdLocal(_ p: SIMD3<Float>) -> SIMD3<Float> {
            // rotate around Z (pitch) for flap direction in 2D plane
            let x = p.x * cosR - p.y * sinR
            let y = p.x * sinR + p.y * cosR
            return SIMD3(bx + x, by + y, p.z)
        }

        func birdLocalN(_ n: SIMD3<Float>) -> SIMD3<Float> {
            let x = n.x * cosR - n.y * sinR
            let y = n.x * sinR + n.y * cosR
            return SIMD3(x, y, n.z)
        }

        // Shadow under bird
        appendBox(
            center: SIMD3(bx, groundY + 0.04, 0.9),
            half: SIMD3(0.35, 0.02, 0.22),
            color: SIMD4(0, 0, 0, 0.35),
            colorTop: SIMD4(0, 0, 0, 0.28)
        )

        // Body
        let bodyColor = SIMD4<Float>(1.0, 0.84, 0.12, 1)
        let belly = SIMD4<Float>(1.0, 0.95, 0.65, 1)
        appendSphere(
            center: birdLocal(SIMD3(0, 0, 0)),
            radius: 0.36,
            color: bodyColor,
            segments: 12,
            rings: 8,
            scale: SIMD3(1.05, 0.9, 0.95)
        )
        // Belly patch
        appendSphere(
            center: birdLocal(SIMD3(0.02, -0.12, 0.18)),
            radius: 0.22,
            color: belly,
            segments: 8,
            rings: 5,
            scale: SIMD3(0.9, 0.7, 0.5)
        )

        // Head
        appendSphere(
            center: birdLocal(SIMD3(0.22, 0.12, 0.05)),
            radius: 0.22,
            color: bodyColor,
            segments: 10,
            rings: 6
        )

        // Beak (pyramid-ish via box)
        do {
            let beakC = birdLocal(SIMD3(0.48, 0.05, 0.08))
            appendBox(
                center: beakC,
                half: SIMD3(0.14, 0.06, 0.07),
                color: SIMD4(1.0, 0.45, 0.1, 1),
                colorTop: SIMD4(1.0, 0.6, 0.2, 1)
            )
        }

        // Eyes
        let eyeWhite = birdLocal(SIMD3(0.32, 0.2, 0.18))
        appendSphere(center: eyeWhite, radius: 0.09, color: SIMD4(1, 1, 1, 1), segments: 8, rings: 4)
        appendSphere(
            center: birdLocal(SIMD3(0.36, 0.21, 0.24)),
            radius: 0.045,
            color: SIMD4(0.08, 0.08, 0.1, 1),
            segments: 6,
            rings: 4
        )

        // Crest feathers
        appendBox(
            center: birdLocal(SIMD3(0.08, 0.32, 0)),
            half: SIMD3(0.06, 0.1, 0.04),
            color: SIMD4(1.0, 0.55, 0.1, 1)
        )
        appendBox(
            center: birdLocal(SIMD3(0.0, 0.36, -0.04)),
            half: SIMD3(0.05, 0.09, 0.03),
            color: SIMD4(1.0, 0.4, 0.08, 1)
        )

        // Wings (animated flap)
        let wingColor = SIMD4<Float>(1.0, 0.92, 0.45, 1)
        let wingDark = SIMD4<Float>(0.95, 0.7, 0.15, 1)
        let wingLift = wingAngle * 0.35
        // Left wing
        appendBox(
            center: birdLocal(SIMD3(-0.08, wingLift * 0.3, 0.28)),
            half: SIMD3(0.22, 0.04 + abs(wingAngle) * 0.02, 0.18),
            color: wingColor,
            colorTop: wingDark
        )
        // Right wing (behind)
        appendBox(
            center: birdLocal(SIMD3(-0.05, -wingLift * 0.15, -0.28)),
            half: SIMD3(0.2, 0.035, 0.15),
            color: wingDark
        )

        // Tail
        appendBox(
            center: birdLocal(SIMD3(-0.38, 0.0, 0)),
            half: SIMD3(0.12, 0.08, 0.05),
            color: SIMD4(1.0, 0.55, 0.12, 1)
        )

        // ---- Particles (feathers / sparkles) ----
        for p in game.particles {
            let lifeT = p.life / max(p.maxLife, 0.001)
            let alpha = lifeT
            let gold = p.hue < 0.15 && p.hue > 0.1 && p.maxLife <= 0.55
            let col: SIMD4<Float> = gold
                ? SIMD4(1.0, 0.85, 0.2, alpha)
                : SIMD4(1.0, 0.9 - p.hue, 0.2 + p.hue, alpha)
            appendBox(
                center: SIMD3(p.x, p.y, 0.4),
                half: SIMD3(p.size, p.size * 0.45, p.size * 0.3),
                color: col
            )
        }

        // Decorative floating clouds (soft boxes far back)
        for i in 0..<4 {
            let cx = fmodf(Float(i) * 3.2 + game.backgroundTime * 0.35, worldW + 2) - 1
            let cy = 11.5 + Float(i % 2) * 1.4
            let cloud = SIMD4<Float>(1, 1, 1, 0.85)
            appendSphere(
                center: SIMD3(cx, cy, -3.5),
                radius: 0.55,
                color: cloud,
                segments: 8,
                rings: 4,
                scale: SIMD3(1.6, 0.7, 0.8)
            )
            appendSphere(
                center: SIMD3(cx + 0.45, cy + 0.1, -3.5),
                radius: 0.4,
                color: cloud,
                segments: 8,
                rings: 4,
                scale: SIMD3(1.3, 0.7, 0.7)
            )
        }

        return count
    }

    // Embedded shader source (compiled via MTL4Compiler / classic makeLibrary)
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexIn {
        float3 position;
        float3 normal;
        float4 color;
    };

    struct VertexOut {
        float4 position [[position]];
        float3 worldPos;
        float3 normal;
        float4 color;
    };

    struct FrameUniforms {
        float2 resolution;
        float time;
        float _pad0;
        float4x4 viewProj;
        float3 lightDir;
        float _pad1;
        float3 lightColor;
        float ambient;
        float3 eyePos;
        float _pad2;
    };

    vertex VertexOut vertex_main(
        uint vid [[vertex_id]],
        constant VertexIn *vertices [[buffer(0)]],
        constant FrameUniforms &uniforms [[buffer(1)]]
    ) {
        VertexIn vin = vertices[vid];
        VertexOut out;
        float4 wp = float4(vin.position, 1.0);
        out.position = uniforms.viewProj * wp;
        out.worldPos = vin.position;
        out.normal = vin.normal;
        out.color = vin.color;
        return out;
    }

    fragment float4 fragment_main(
        VertexOut in [[stage_in]],
        constant FrameUniforms &uniforms [[buffer(1)]]
    ) {
        float3 N = normalize(in.normal);
        float3 L = normalize(-uniforms.lightDir);
        float3 V = normalize(uniforms.eyePos - in.worldPos);
        float3 H = normalize(L + V);

        float ndl = saturate(dot(N, L));
        float spec = pow(saturate(dot(N, H)), 48.0) * 0.45;
        float rim = pow(1.0 - saturate(dot(N, V)), 2.5) * 0.22;

        float3 base = in.color.rgb;
        float3 lit = base * (uniforms.ambient + ndl * uniforms.lightColor)
                   + uniforms.lightColor * spec * (0.35 + base.r * 0.4)
                   + float3(0.55, 0.75, 1.0) * rim;

        float fog = saturate((in.worldPos.z + 1.2) * 0.12);
        lit = mix(lit, float3(0.55, 0.78, 0.95), fog * 0.15);

        return float4(lit, in.color.a);
    }

    struct SkyVertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex SkyVertexOut sky_vertex(uint vid [[vertex_id]]) {
        float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        SkyVertexOut out;
        out.position = float4(positions[vid], 0.0, 1.0);
        out.uv = positions[vid] * 0.5 + 0.5;
        return out;
    }

    fragment float4 sky_fragment(
        SkyVertexOut in [[stage_in]],
        constant FrameUniforms &uniforms [[buffer(0)]]
    ) {
        float t = saturate(in.uv.y);
        float3 top = float3(0.22, 0.48, 0.92);
        float3 mid = float3(0.48, 0.76, 0.98);
        float3 bottom = float3(0.82, 0.90, 0.78);

        float3 col = mix(bottom, mid, smoothstep(0.0, 0.5, t));
        col = mix(col, top, smoothstep(0.4, 1.0, t));

        float2 sunPos = float2(0.78, 0.82);
        float d = distance(in.uv, sunPos);
        col += float3(1.0, 0.95, 0.7) * exp(-d * 22.0) * 0.55;
        col += float3(1.0, 0.75, 0.35) * exp(-d * 8.0) * 0.25;

        float time = uniforms.time;
        for (int i = 0; i < 3; i++) {
            float fi = float(i);
            float2 p = in.uv * float2(3.5 + fi, 2.2 + fi * 0.3);
            p.x += time * (0.04 + fi * 0.015);
            float n = sin(p.x * 2.1 + p.y * 1.3) * cos(p.y * 2.4 - p.x * 0.7);
            n = n * 0.5 + 0.5;
            float band = smoothstep(0.45, 0.85, in.uv.y) * smoothstep(1.0, 0.55, in.uv.y);
            col = mix(col, float3(1.0, 1.0, 0.98), n * n * band * (0.08 + fi * 0.03));
        }

        col = mix(col, float3(0.95, 0.88, 0.75), exp(-in.uv.y * 6.0) * 0.18);
        return float4(col, 1.0);
    }
    """
}
