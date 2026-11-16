// WHY: Swift 6 reads Darwin's C global `mach_task_self_` only through a preconcurrency import.
@preconcurrency import Darwin
import os

extension CleanModel.Cost {
    /// `milliseconds`, with the app's memory now: `task_info`'s `phys_footprint` and `ledger_phys_footprint_peak`,
    /// and `os_proc_available_memory`.
    nonisolated init(milliseconds: Int?) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        self.init(
            milliseconds: milliseconds, footprint: Int(info.phys_footprint >> 20),
            peak: Int(info.ledger_phys_footprint_peak >> 20), available: os_proc_available_memory() >> 20)
    }
}
