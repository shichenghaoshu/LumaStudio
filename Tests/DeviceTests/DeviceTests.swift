import XCTest
import PhotoCore
final class DeviceTests: XCTestCase {
    func testCapabilitiesReportObservedResourcesAndDoNotClaimANEUsage() throws {
        let c=DeviceCapabilityManager().snapshot()
        XCTAssertEqual(c.physicalMemoryBytes,ProcessInfo.processInfo.physicalMemory)
        XCTAssertFalse(c.model.isEmpty);XCTAssertFalse(c.gpu.isEmpty);XCTAssertTrue(c.neuralEngine.contains("不宣称"))
        XCTAssertTrue(["normal","warning","critical"].contains(c.memoryPressure))
    }
}
