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
    vertex float4 vertex_main(const VertexIn vertex_in [[stage_in]])
    {
        return vertex_in.position;
    }
    fragment float4 fragment_main() 
    {
        return float4(1, 0, 0, 1);
    }
    """
let library = try device.makeLibrary(source: shader, options: nil)
let vertexFunction = library.makeFunction(name: "vertex_main")
let fragmentFunction = library.makeFunction(name: "fragment_main")

print(shader)
