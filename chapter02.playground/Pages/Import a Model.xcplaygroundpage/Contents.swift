import MetalKit
import PlaygroundSupport

// 获取 gpu 设备对象
guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("GPU is not supported")
}

print("device name: " + device.name)

// 定义一个绘画区域 rect
let frame = CGRect(x: 0, y: 0, width: 512, height: 512)

// 通过 rect 定义一个 view，并设置该 view 的 clear color
let view = MTKView(frame: frame, device: device)
view.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)

// 将 view 赋予给 playground 的输出通道
//PlaygroundPage.current.liveView = view

// 定义一个 mesh buffer 内存分配器，需要 device
let allocator = MTKMeshBufferAllocator(device: device)

/*
 从 resource 加载 train.usdz 模型，并渲染出来
*/
// 定义模型的所在位置 url
guard
    let assetURL = Bundle.main.url(forResource: "train", withExtension: "usdz")
else {
    fatalError()
}
// 定义一个 vertex descriptor，使得 gpu 能够正确读取顶点数据
let vertexDescriptor = MTLVertexDescriptor()
vertexDescriptor.attributes[0].format = .float3  // for position
vertexDescriptor.attributes[0].offset = 0
vertexDescriptor.attributes[0].bufferIndex = 0  // 因为我们 setVertexBuffer 时，index 是 0
// 设置顶点的 stride，已正确从一个顶点数据找到下一个顶点数据
vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride

// 构建 meshdescriptor 用于兼容 modelIO 和 metal 的 vertexDescriptor
let meshDescriptor = MTKModelIOVertexDescriptorFromMetal(vertexDescriptor)
(meshDescriptor.attributes[0] as! MDLVertexAttribute).name =
    MDLVertexAttributePosition

let asset = MDLAsset(
    url: assetURL, vertexDescriptor: meshDescriptor, bufferAllocator: allocator)

let mdlMesh = asset.childObjects(of: MDLMesh.self).first as! MDLMesh

// 定义一个 mtkmesh，这个对象用于将 mdl 对象转换成可以被提交到 gpu 的网格资源
let mesh = try MTKMesh(mesh: mdlMesh, device: device)

// 只需创建一次的 commandqueue，用于组织和管理多个 command buffers
guard let commandQueue = device.makeCommandQueue() else {
    fatalError("could not create a command queue")
}

/*
 以上都属于初始化阶段，程序开始时执行；以下都属于执行阶段，每一帧都会执行一次，根据需要调整
*/

// 通过文本定义一个 shader 源文件
// 其中 [[attribute(0)]] 用于定义 vertex shader 输入属性的索引，本质上是一个地址索引，表示从第 0 个属性获取定点位置数据
// 由于这里的顶点位置完全没有经过任何变换，所以默认情况下，顶点位置会被视为 NDC 空间位置
let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct VertexIn {
        float4 position [[attribute(0)]];
    };
    vertex float4 vert(const VertexIn vertex_in [[stage_in]])
    {
        float4 position = vertex_in.position;
        position.y -= 1.0;
        return position;
    }
    fragment float4 frag() 
    {
        return float4(0.7, 0.4, 0.5, 1);
    }
    """

// 从文本中创建 vertex shader 和 fragment shader
let library = try device.makeLibrary(source: shader, options: nil)
let vertexFunction = library.makeFunction(name: "vert")
let fragmentFunction = library.makeFunction(name: "frag")

//print(shader)

// 定义 pso descriptor 用于后面创建 pso 对象，包含默认的设置
let pipelineDescriptor = MTLRenderPipelineDescriptor()
// pixelformat 是 pso 中重要参数，需要手动指定，可以查看 mtlpixelformat 枚举的具体数值
pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
// 另外两个重要的参数就是要指定
pipelineDescriptor.vertexFunction = vertexFunction
pipelineDescriptor.fragmentFunction = fragmentFunction

// 定义 vertex layout，这样 gpu 才能正确读取顶点数据，由于我们是通过 modelI/O 生成的模型，所以布局很好获得
pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(
    mesh.vertexDescriptor)

// 通过 pipelineDescriptor 来生成 pso 对象，这一步的性能十分敏感
let pipelineState = try device.makeRenderPipelineState(
    descriptor: pipelineDescriptor)

// 通过 "," 符号来简写，将多个定义和合并到一个 guard 语句中
// 定义 commandbuffer
guard let commandBuffer = commandQueue.makeCommandBuffer(),
    // 定义 renderpass descriptor，需要通过 mtkview 对象
    let renderPassDescriptor = view.currentRenderPassDescriptor,
    // 定义 commandbuffer 的 renderer encoder，用于记录渲染命令
    let renderEncoder = commandBuffer.makeRenderCommandEncoder(
        descriptor: renderPassDescriptor)
else { fatalError("error") }

// 记录渲染命令前需要设置 pso
renderEncoder.setRenderPipelineState(pipelineState)

// 设置 vertex buffer
renderEncoder.setVertexBuffer(mesh.vertexBuffers[0].buffer, offset: 0, index: 0)

renderEncoder.setTriangleFillMode(.lines)

// 绘制命令需要顶点索引的数量与类型，这些信息通过 mesh 的 submesh 来提供
guard let submesh = mesh.submeshes.first else {
    fatalError("submesh error")
}

// 向 render encoder 里记录一条绘制命令，同时记录绘制参数
renderEncoder.drawIndexedPrimitives(
    type: .triangle, indexCount: submesh.indexCount,
    indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer,
    indexBufferOffset: 0)

// encoder 命令记录完成后需要通过 endEncoding API 来关闭，重要！！！
renderEncoder.endEncoding()

// 从 MTKView 中获得窗口的 drawable，这是一个 CAMetalDrawable 内置类，用语言将绘制结果提交给显示设备
guard let drawable = view.currentDrawable else {
    fatalError()
}

// commandbuffer 的内容提交到 drawable，提交到 drawable 就可以显示到屏幕
commandBuffer.present(drawable)
// 提交命令并执行
commandBuffer.commit()

// 将 MTKView 赋予 playground 以便显示出来
PlaygroundPage.current.liveView = view
