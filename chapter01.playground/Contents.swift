import MetalKit
import PlaygroundSupport

// 获取 gpu 设备对象
guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("GPU is not supported")
}

print("device name: " + device.name)

// 定义一个绘画区域 rect
let frame = CGRect(x: 0, y: 0, width: 800, height: 600)

// 通过 rect 定义一个 view，并设置该 view 的 clear color
let view = MTKView(frame: frame, device: device)
view.clearColor = MTLClearColor(red: 1, green: 1, blue: 0.8, alpha: 1)

// 将 view 赋予给 playground 的输出通道
PlaygroundPage.current.liveView = view

// 定义一个 mesh buffer 内存分配器，需要 device
let allocator = MTKMeshBufferAllocator(device: device)

// 通过 modelI/O api 来定义一个参数化模型，这个 API 也用于加载其他的模型资源
let mdlMesh = MDLMesh(
    sphereWithExtent: [0.75, 0.75, 0.75], segments: [100, 100],
    inwardNormals: false, geometryType: .triangles, allocator: allocator
)

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
let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct VertexIn {
        float4 position [[attribute(0)]];
    };
    vertex float4 vert(const VertexIn vertex_in [[stage_in]])
    {
        return vertex_in.position;
    }
    fragment float4 frag() 
    {
        return float4(1, 0, 0, 1);
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

commandBuffer.present(drawable)
commandBuffer.commit()

PlaygroundPage.current.liveView = view
