import Metal
import MetalKit
import CoreVideo
import WindowCRTLensCore

struct MetalSourceFrame {
    let texture: MTLTexture
    let lifetimeAnchor: CVMetalTexture
}

private struct LensUniforms {
    var outputSize: SIMD2<Float>
    var curvature: Float
    var scanlineStrength: Float
    var maskStrength: Float
    var glowStrength: Float
    var vignetteStrength: Float
    var time: Float
    var screenCornerRadius: Float
    var shellCornerRadius: Float
    var edgeSoftness: Float
    var zoom: Float
}

final class CRTRenderer: NSObject, MTKViewDelegate {
    var preset: LensPreset = .glassy
    var appearance: LensAppearance = .default

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let textureLock = NSLock()
    private var sourceFrame: MetalSourceFrame?
    private let startedAt = ProcessInfo.processInfo.systemUptime

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.commandQueueUnavailable
        }
        self.commandQueue = commandQueue

        let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        guard let vertex = library.makeFunction(name: "lens_vertex"),
              let fragment = library.makeFunction(name: "lens_fragment") else {
            throw RendererError.shaderFunctionsUnavailable
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = pixelFormat
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw RendererError.samplerUnavailable
        }
        self.sampler = sampler
        super.init()
    }

    func update(frame: MetalSourceFrame) {
        textureLock.lock()
        sourceFrame = frame
        textureLock.unlock()
    }

    func draw(in view: MTKView) {
        textureLock.lock()
        let frame = sourceFrame
        textureLock.unlock()

        guard let frame,
              let drawable = view.currentDrawable,
              let renderPass = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return }

        let drawableSize = view.drawableSize
        let appearanceMetrics = appearance.renderMetrics(
            drawableSize: drawableSize,
            viewSize: view.bounds.size
        )
        var uniforms = LensUniforms(
            outputSize: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
            curvature: preset.curvature,
            scanlineStrength: preset.scanlineStrength,
            maskStrength: preset.maskStrength,
            glowStrength: preset.glowStrength,
            vignetteStrength: preset.vignetteStrength,
            time: Float(ProcessInfo.processInfo.systemUptime - startedAt),
            screenCornerRadius: appearanceMetrics.screenCornerRadiusPixels,
            shellCornerRadius: appearanceMetrics.shellCornerRadiusPixels,
            edgeSoftness: appearanceMetrics.edgeSoftnessPixels,
            zoom: appearanceMetrics.zoomScale
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(frame.texture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<LensUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.addCompletedHandler { [frame] _ in
            withExtendedLifetime(frame.lifetimeAnchor) {}
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    enum RendererError: LocalizedError {
        case commandQueueUnavailable
        case shaderFunctionsUnavailable
        case samplerUnavailable

        var errorDescription: String? {
            switch self {
            case .commandQueueUnavailable: "Metal could not create a command queue."
            case .shaderFunctionsUnavailable: "The CRT shader could not be compiled."
            case .samplerUnavailable: "Metal could not create a texture sampler."
            }
        }
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    struct LensUniforms {
        float2 outputSize;
        float curvature;
        float scanlineStrength;
        float maskStrength;
        float glowStrength;
        float vignetteStrength;
        float time;
        float screenCornerRadius;
        float shellCornerRadius;
        float edgeSoftness;
        float zoom;
    };

    float rounded_rect_distance(float2 point, float2 halfSize, float radius) {
        radius = clamp(radius, 0.0, min(halfSize.x, halfSize.y));
        float2 q = abs(point) - max(halfSize - radius, float2(0.0));
        return length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    }

    vertex VertexOut lens_vertex(uint vertexID [[vertex_id]]) {
        constexpr float2 positions[4] = {
            float2(-1.0, -1.0), float2(1.0, -1.0),
            float2(-1.0,  1.0), float2(1.0,  1.0)
        };
        constexpr float2 texcoords[4] = {
            float2(0.0, 1.0), float2(1.0, 1.0),
            float2(0.0, 0.0), float2(1.0, 0.0)
        };
        VertexOut out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = texcoords[vertexID];
        return out;
    }

    fragment float4 lens_fragment(
        VertexOut in [[stage_in]],
        texture2d<float> source [[texture(0)]],
        sampler sourceSampler [[sampler(0)]],
        constant LensUniforms& u [[buffer(0)]]
    ) {
        float2 outputPoint = in.uv * u.outputSize - u.outputSize * 0.5;
        float2 outputHalfSize = max(u.outputSize * 0.5 - 0.5, float2(0.5));
        float outerDistance = rounded_rect_distance(
            outputPoint,
            outputHalfSize,
            u.shellCornerRadius
        );
        float outerAA = max(fwidth(outerDistance), u.edgeSoftness);
        float outerCoverage = 1.0 - smoothstep(-outerAA, outerAA, outerDistance);

        float2 lensPosition = in.uv * 2.0 - 1.0;
        float radius2 = dot(lensPosition, lensPosition);
        float2 centered = lensPosition / max(u.zoom, 0.001);
        centered *= 1.0 + u.curvature * radius2;
        float2 uv = centered * 0.5 + 0.5;

        float shellLift = 0.008 + 0.008 * smoothstep(0.8, 1.4, radius2);
        float3 shellColor = float3(shellLift, shellLift * 1.05, shellLift * 1.15);
        float2 sourceSize = float2(source.get_width(), source.get_height());
        float sourceScale = min(sourceSize.x / u.outputSize.x, sourceSize.y / u.outputSize.y);
        float2 sourcePoint = uv * sourceSize - sourceSize * 0.5;
        float2 sourceHalfSize = max(sourceSize * 0.5 - 0.5, float2(0.5));
        float sourceDistance = rounded_rect_distance(
            sourcePoint,
            sourceHalfSize,
            u.screenCornerRadius * sourceScale
        );
        float sourceAA = max(fwidth(sourceDistance), u.edgeSoftness * sourceScale);
        float screenCoverage = 1.0 - smoothstep(-sourceAA, sourceAA, sourceDistance);
        float2 sampleUV = clamp(uv, float2(0.0), float2(1.0));

        float aberration = (0.00035 + u.curvature * 0.0025) * radius2;
        float3 color;
        color.r = source.sample(sourceSampler, sampleUV + float2(aberration, 0.0)).r;
        color.g = source.sample(sourceSampler, sampleUV).g;
        color.b = source.sample(sourceSampler, sampleUV - float2(aberration, 0.0)).b;

        float scan = 0.5 + 0.5 * sin(uv.y * u.outputSize.y * 3.14159265);
        color *= 1.0 - u.scanlineStrength * (1.0 - scan);

        float phase = fmod(floor(uv.x * u.outputSize.x), 3.0);
        float3 mask = phase < 1.0 ? float3(1.0, 0.84, 0.84)
                    : phase < 2.0 ? float3(0.84, 1.0, 0.84)
                                  : float3(0.84, 0.84, 1.0);
        color *= mix(float3(1.0), mask, u.maskStrength);

        float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
        color += color * luminance * u.glowStrength;

        float edge = smoothstep(0.32, 1.18, radius2);
        color *= 1.0 - edge * u.vignetteStrength;

        float diagonal = smoothstep(0.66, 0.98, 1.0 - abs((uv.x * 0.72 + uv.y) - 0.43));
        float edgeGlass = pow(saturate(radius2 * 0.62), 3.0);
        float reflection = (diagonal * 0.022 + edgeGlass * 0.045) * (0.5 + u.glowStrength * 2.0);
        color += float3(reflection * 0.72, reflection * 0.88, reflection);

        float breathingNoise = 1.0 + 0.002 * sin(u.time * 1.7 + uv.y * 19.0);
        color *= breathingNoise;
        color = mix(shellColor, saturate(color), screenCoverage);
        return float4(color, outerCoverage);
    }
    """
}
