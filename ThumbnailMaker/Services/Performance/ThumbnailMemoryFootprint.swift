//
//  ThumbnailMemoryFootprint.swift
//  ThumbnailMaker
//
//  APP-09: the process footprint as Xcode's memory gauge and jetsam see it.
//

import Darwin
import Foundation

enum ThumbnailMemoryFootprint {
    /// `phys_footprint` from TASK_VM_INFO, or nil when the kernel call fails.
    static func currentBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }

    /// Largest footprint seen in `samples`, or nil when none carried one.
    static func peak(in samples: [ThumbnailPerformanceSample]) -> UInt64? {
        samples.compactMap(\.footprintBytes).max()
    }
}
