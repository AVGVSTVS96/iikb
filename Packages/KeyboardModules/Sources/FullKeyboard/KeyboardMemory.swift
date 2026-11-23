// WARNING: Swift 6 reads Darwin's C global `mach_task_self_` only through a preconcurrency import.
@preconcurrency import Darwin
import os

/// What iOS lets this keyboard use, which ends it past its limit (177 MB on the Duo, Nov 9; Hex measured 60–90 MB on
/// smaller iPhones).
nonisolated enum KeyboardMemory {
    static let megabyte = 1_048_576

    /// How much more iOS lets the keyboard use, 0 where it doesn't say (the simulator).
    static var available: Int { Int(os_proc_available_memory()) }

    /// The keyboard's footprint, what iOS counts toward its limit.
    static var footprint: Int { info.map { Int($0.phys_footprint) } ?? 0 }

    static var neural: Int {
        info.map { Int($0.ledger_tag_neural_nofootprint + $0.ledger_tag_neural_nofootprint_compressed) } ?? 0
    }

    private static var info: task_vm_info_data_t? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    /// The keyboard's limit, its footprint and what's left, 0 where iOS doesn't say.
    static var limit: Int {
        let available = available
        return available == 0 ? 0 : available + footprint
    }

    /// Whether `megabytes` more fits, true where iOS doesn't say.
    static func fits(_ megabytes: Double) -> Bool {
        let available = available
        return available == 0 || Double(available) >= megabytes * Double(megabyte)
    }
}
