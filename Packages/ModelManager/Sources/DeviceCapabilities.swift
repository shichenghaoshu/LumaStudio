import Foundation
import Metal
import Darwin

public struct DeviceCapabilities: Codable,Sendable {
    public let model: String
    public let physicalMemoryBytes: UInt64
    public let availableMemoryEstimateBytes: UInt64
    public let operatingSystem: String
    public let gpu: String
    public let recommendedGPUWorkingSetBytes: UInt64
    public let neuralEngine: String
    public let memoryPressure: String
    public var supportsNativeAgent: Bool { physicalMemoryBytes>=8*1024*1024*1024 && memoryPressure != "critical" && availableMemoryEstimateBytes>1500*1024*1024 }
}
public final class DeviceCapabilityManager: @unchecked Sendable {
    private let lock=NSLock()
    private var pressure="normal"
    private var source: DispatchSourceMemoryPressure?
    public init() {
        let source=DispatchSource.makeMemoryPressureSource(eventMask:[.normal,.warning,.critical],queue:.global(qos:.utility))
        self.source=source
        source.setEventHandler { [weak self,weak source] in
            guard let self,let flags=source?.data else { return }
            self.lock.lock();self.pressure=flags.contains(.critical) ? "critical" : flags.contains(.warning) ? "warning" : "normal";self.lock.unlock()
        };source.resume()
    }
    deinit { source?.cancel() }
    public func snapshot() -> DeviceCapabilities {
        var size=0;sysctlbyname("hw.model",nil,&size,nil,0);var bytes=[CChar](repeating:0,count:max(1,size));sysctlbyname("hw.model",&bytes,&size,nil,0)
        let gpu=MTLCreateSystemDefaultDevice()
        var statistics=vm_statistics64(),count=mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size/MemoryLayout<integer_t>.size)
        let result=withUnsafeMutablePointer(to:&statistics){ p in p.withMemoryRebound(to:integer_t.self,capacity:Int(count)){host_statistics64(mach_host_self(),HOST_VM_INFO64,$0,&count)} }
        var page: vm_size_t=0;host_page_size(mach_host_self(),&page)
        let available=result==KERN_SUCCESS ? (UInt64(statistics.free_count)+UInt64(statistics.inactive_count)+UInt64(statistics.purgeable_count))*UInt64(page) : 0
        lock.lock();let current=pressure;lock.unlock()
        return DeviceCapabilities(model:String(cString:bytes),physicalMemoryBytes:ProcessInfo.processInfo.physicalMemory,availableMemoryEstimateBytes:available,operatingSystem:ProcessInfo.processInfo.operatingSystemVersionString,gpu:gpu?.name ?? "无 Metal GPU",recommendedGPUWorkingSetBytes:gpu?.recommendedMaxWorkingSetSize ?? 0,neuralEngine:"未独立探测；Core ML 自行调度，不宣称使用 ANE",memoryPressure:current)
    }
}
