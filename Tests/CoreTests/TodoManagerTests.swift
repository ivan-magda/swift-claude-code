import Testing

@testable import Core

@Suite("TodoManager")
struct TodoManagerTests {
  @Test func updateStoresItems() throws {
    let manager = TodoManager()
    let items = [
      TodoItem(id: "1", text: "First task", status: .pending),
      TodoItem(id: "2", text: "Second task", status: .inProgress)
    ]
    try manager.update(items: items)
    #expect(manager.items == items)
  }

  @Test func renderFormatsItems() throws {
    let manager = TodoManager()
    try manager.update(items: [
      TodoItem(id: "1", text: "Do thing", status: .pending),
      TodoItem(id: "2", text: "Doing thing", status: .inProgress),
      TodoItem(id: "3", text: "Done thing", status: .completed)
    ])
    let output = manager.render()
    #expect(output.contains("[ ] Do thing"))
    #expect(output.contains("[>] Doing thing"))
    #expect(output.contains("[x] Done thing"))
    #expect(output.contains("(1/3 completed)"))
  }

  @Test func rejectsExceedingMaxItems() {
    let manager = TodoManager()
    let items = (0...TodoManager.maxItems).map {
      TodoItem(id: "\($0)", text: "Task \($0)", status: .pending)
    }
    #expect(throws: TodoManager.ValidationError.tooManyItems) {
      try manager.update(items: items)
    }
  }

  @Test func rejectsEmptyText() {
    let manager = TodoManager()
    let items = [TodoItem(id: "1", text: "  ", status: .pending)]
    #expect(throws: TodoManager.ValidationError.emptyText("1")) {
      try manager.update(items: items)
    }
  }

  @Test func rejectsMultipleInProgress() {
    let manager = TodoManager()
    let items = [
      TodoItem(id: "1", text: "Task A", status: .inProgress),
      TodoItem(id: "2", text: "Task B", status: .inProgress)
    ]
    #expect(throws: TodoManager.ValidationError.multipleInProgress) {
      try manager.update(items: items)
    }
  }

  @Test(arguments: [TodoStatus.pending, .inProgress])
  func hasOpenItemsReturnsTrueForNonCompleted(status: TodoStatus) throws {
    let manager = TodoManager()
    try manager.update(items: [
      TodoItem(id: "1", text: "Task", status: status)
    ])
    #expect(manager.hasOpenItems())
  }

  @Test func hasOpenItemsReturnsFalseWhenAllCompleted() throws {
    let manager = TodoManager()
    try manager.update(items: [
      TodoItem(id: "1", text: "Done", status: .completed)
    ])
    #expect(!manager.hasOpenItems())
  }

  @Test func renderReturnsNoTodosWhenEmpty() {
    let manager = TodoManager()
    #expect(manager.render() == "No todos.")
  }
}
