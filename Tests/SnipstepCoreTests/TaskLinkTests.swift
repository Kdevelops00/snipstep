import Foundation
import Testing
@testable import SnipstepCore

@Test func widgetTaskLinksRoundTripAndRejectUnrelatedInput() {
    let id = UUID()
    #expect(TaskLink(url: TaskLink.newTask.url) == .newTask)
    #expect(TaskLink(url: TaskLink.detail(id).url) == .detail(id))
    #expect(TaskLink.newTask.url.scheme == "snipstep")
    #expect(TaskLink(url: URL(string: "snaplater://task/\(id.uuidString)")!) == .detail(id))
    for value in ["https://new-task", "snaplater://new-task/extra", "snaplater://new-task?title=unexpected", "snaplater://task/not-a-uuid", "snaplater://user@new-task", "snaplater://new-task#unexpected"] {
        #expect(TaskLink(url: URL(string: value)!) == nil)
    }
}
