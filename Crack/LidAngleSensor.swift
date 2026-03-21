import Foundation
import IOKit
import IOKit.hid

class LidAngleSensor {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private(set) var isAvailable = false

    init() {
        setupHID()
    }

    private func setupHID() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = manager else { return }

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDProductIDKey as String: 0x8104,
            kIOHIDDeviceUsagePageKey as String: 0x0020,
            kIOHIDDeviceUsageKey as String: 0x008A
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { return }

        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let firstDevice = deviceSet.first else { return }

        device = firstDevice
        let openResult = IOHIDDeviceOpen(firstDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        isAvailable = (openResult == kIOReturnSuccess)
    }

    func readAngle() -> Double {
        guard let device = device else { return -1 }

        var report = [UInt8](repeating: 0, count: 8)
        var reportLength = CFIndex(report.count)

        let result = IOHIDDeviceGetReport(
            device,
            kIOHIDReportTypeFeature,
            CFIndex(1),
            &report,
            &reportLength
        )

        guard result == kIOReturnSuccess else { return -1 }

        let rawValue = (UInt16(report[2]) << 8) | UInt16(report[1])
        return Double(rawValue) / 100.0
    }

    deinit {
        if let device = device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let manager = manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
}
