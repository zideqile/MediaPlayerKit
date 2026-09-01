import Foundation
#if canImport(UIKit)
import UIKit
#endif
import Metal
import MetalKit
import CoreVideo

/// 基于 Metal 的高性能零拷贝视频渲染视图
public final class MetalRenderView: MTKView, MTKViewDelegate {
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?
    private var samplerState: MTLSamplerState?
    
    private var currentPixelBuffer: CVPixelBuffer?
    private let renderLock = NSLock()
    
    public init() {
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: device)
        commonInit()
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        self.device = MTLCreateSystemDefaultDevice()
        commonInit()
    }
    
    private func commonInit() {
        guard let device = self.device else { return }
        
        self.delegate = self
        self.isPaused = true
        self.enableSetNeedsDisplay = false
        self.framebufferOnly = true
        self.colorPixelFormat = .bgra8Unorm
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        self.commandQueue = device.makeCommandQueue()
        
        #if !targetEnvironment(simulator)
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        #endif
        
        setupPipeline(device: device)
    }
    
    private func setupPipeline(device: MTLDevice) {
        guard let defaultLibrary = device.makeDefaultLibrary() else { return }
        
        let vertexFunction = defaultLibrary.makeFunction(name: "playerVertexShader")
        let fragmentFunction = defaultLibrary.makeFunction(name: "nv12FragmentShaderBT709")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat
        
        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("[MediaPlayerKit Metal] Failed to create pipeline state: \(error)")
        }
        
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        self.samplerState = device.makeSamplerState(descriptor: samplerDesc)
    }
    
    /// 接收解码器输出的 CVPixelBuffer 并触发 GPU 绘制
    public func render(pixelBuffer: CVPixelBuffer) {
        renderLock.lock()
        self.currentPixelBuffer = pixelBuffer
        renderLock.unlock()
        
        DispatchQueue.main.async { [weak self] in
            self?.draw()
        }
    }
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    public func draw(in view: MTKView) {
        renderLock.lock()
        guard let pixelBuffer = currentPixelBuffer,
              let textureCache = textureCache,
              let pipelineState = pipelineState,
              let commandQueue = commandQueue,
              let currentDrawable = currentDrawable,
              let renderPassDesc = currentRenderPassDescriptor else {
            renderLock.unlock()
            return
        }
        renderLock.unlock()
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // 1. 零拷贝映射 Y 平面 (Luma)
        var yTextureRef: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .r8Unorm,
            width,
            height,
            0,
            &yTextureRef
        )
        
        // 2. 零拷贝映射 UV 平面 (Chroma)
        var uvTextureRef: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .rg8Unorm,
            width / 2,
            height / 2,
            1,
            &uvTextureRef
        )
        
        guard let yCVTexture = yTextureRef,
              let uvCVTexture = uvTextureRef,
              let yMetalTexture = CVMetalTextureGetTexture(yCVTexture),
              let uvMetalTexture = CVMetalTextureGetTexture(uvCVTexture),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
            return
        }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFragmentTexture(yMetalTexture, index: 0)
        renderEncoder.setFragmentTexture(uvMetalTexture, index: 1)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        
        // 绘制四边形
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
    
    public func clean() {
        renderLock.lock()
        self.currentPixelBuffer = nil
        renderLock.unlock()
        if let textureCache = textureCache {
            CVMetalTextureCacheFlush(textureCache, 0)
        }
    }
}
