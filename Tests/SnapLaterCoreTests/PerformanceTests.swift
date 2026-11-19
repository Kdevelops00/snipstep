import Foundation
import Testing
import Darwin
@testable import SnapLaterCore

@Test(.enabled(if: ProcessInfo.processInfo.environment["SNAPLATER_PERFORMANCE_CHECK"] == "1"))
@MainActor func syntheticThousandTaskLibrary() async throws {
    let h = try Harness(persistent: true); defer { h.cleanup() }
    let clock = ContinuousClock()
    let writeStart = clock.now
    for i in 0..<1_000 {
        let task = SavedTask(title: "Synthetic idea \(i)")
        task.details = String(repeating: "Public synthetic notes. ", count: 20)
        task.ocrText = String(repeating: "Synthetic OCR text. ", count: 100)
        h.store.context.insert(task)
    }
    try h.store.commit()
    let writeTime = writeStart.duration(to: clock.now)
    let readStart = clock.now
    let tasks = try h.store.all()
    let matches = tasks.filter { $0.title.localizedStandardContains("idea 99") || $0.ocrText.localizedStandardContains("idea 99") }
    let readTime = readStart.duration(to: clock.now)
    #expect(tasks.count == 1_000)
    #expect(matches.count == 11)
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    print("SYNTHETIC_BENCHMARK tasks=1000 write=\(writeTime) fetch_and_search=\(readTime) resident_MiB=\(status == KERN_SUCCESS ? info.resident_size / 1_048_576 : 0)")
}
