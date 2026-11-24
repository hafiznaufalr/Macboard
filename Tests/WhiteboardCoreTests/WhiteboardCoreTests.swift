import CoreGraphics
import Foundation
import Testing
@testable import WhiteboardCore

@Test func test_addFolder_rejectsBlankName() {
    var library = Library()
    #expect(throws: LibraryError.emptyName) {
        try library.addFolder(name: "  ")
    }
}

@Test func test_folderAndBoard_crud() throws {
    var library = Library()
    let folderID = try library.addFolder(name: "Brain", id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    let boardID = try library.addBoard(folderID: folderID, name: "Dump", id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
    #expect(library.folders.map(\.name) == ["Brain"])
    #expect(library.folders[0].boards.map(\.name) == ["Dump"])

    try library.renameFolder(id: folderID, name: "Work")
    try library.renameBoard(folderID: folderID, boardID: boardID, name: "Today")
    #expect(library.folders[0].name == "Work")
    #expect(library.folders[0].boards[0].name == "Today")

    try library.deleteBoard(folderID: folderID, boardID: boardID)
    #expect(library.folders[0].boards.isEmpty)
    try library.deleteFolder(id: folderID)
    #expect(library.folders.isEmpty)
}

@Test func test_elements_addMoveDelete_andTopmostHit() throws {
    var library = Library()
    let folderID = try library.addFolder(name: "F")
    let boardID = try library.addBoard(folderID: folderID, name: "B")
    let note = Note(id: UUID(), origin: CGPoint(x: 10, y: 10), text: "idea", width: 100)
    let image = PlacedImage(id: UUID(), origin: CGPoint(x: 10, y: 10), width: 40, height: 40, fileName: "a.png")
    try library.addElement(folderID: folderID, boardID: boardID, element: .note(note))
    try library.addElement(folderID: folderID, boardID: boardID, element: .image(image))

    let hit = HitTest.element(at: CGPoint(x: 20, y: 20), in: library.board(folderID: folderID, boardID: boardID)!.elements)
    #expect(hit == image.id)

    try library.updateElement(folderID: folderID, boardID: boardID, elementID: note.id) {
        $0 = $0.moved(by: CGSize(width: 5, height: -2))
    }
    let moved = library.board(folderID: folderID, boardID: boardID)!.elements[0]
    #expect(moved == .note(Note(id: note.id, origin: CGPoint(x: 15, y: 8), text: "idea", width: 100)))

    let stroke = Stroke(id: UUID(), points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)], colorHex: "000000", width: 2)
    try library.addElement(folderID: folderID, boardID: boardID, element: .stroke(stroke))
    let near = HitTest.element(at: CGPoint(x: 5, y: 2), in: [BoardElement.stroke(stroke)])
    let far = HitTest.element(at: CGPoint(x: 5, y: 40), in: [BoardElement.stroke(stroke)])
    #expect(near == stroke.id)
    #expect(far == nil)

    try library.deleteElement(folderID: folderID, boardID: boardID, elementID: image.id)
    #expect(library.board(folderID: folderID, boardID: boardID)!.elements.contains(where: { $0.id == image.id }) == false)
}

@Test func test_camera_screenWorld_roundTrip() {
    var camera = Camera(offset: CGPoint(x: 100, y: -20), scale: 2)
    let view = CGSize(width: 800, height: 600)
    let world = CGPoint(x: 130, y: 15)
    let screen = camera.screenPoint(fromWorld: world, viewSize: view)
    #expect(camera.worldPoint(fromScreen: screen, viewSize: view) == world)
    camera.pan(screenDelta: CGSize(width: 20, height: -10))
    #expect(camera.offset == CGPoint(x: 90, y: -15))
    camera.zoom(by: 10)
    #expect(camera.scale == 4)
}

@Test func test_history_commitUndoRedo_andLimit() {
    var history = History(present: "a", limit: 1)
    history.commit("b")
    history.commit("c")
    #expect(history.present == "c")
    history.undo()
    #expect(history.present == "b")
    history.undo()
    #expect(history.present == "b")
    history.redo()
    #expect(history.present == "c")
    #expect(history.retained() == ["b", "c"])
}

@Test func test_disk_roundTrip_andImageBytes() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = DiskStore(root: root)
    #expect(try store.load() == nil)
    var library = Library.seed()
    let folderID = library.folders[0].id
    let boardID = library.folders[0].boards[0].id
    let fileName = try store.importImage(data: Data([9, 8, 7]), fileExtension: "jpg")
    #expect(fileName.hasSuffix(".jpg"))
    try library.addElement(
        folderID: folderID,
        boardID: boardID,
        element: .image(PlacedImage(id: UUID(), origin: .zero, width: 10, height: 12, fileName: fileName))
    )
    try store.save(library)
    let loaded = try #require(try store.load())
    #expect(loaded == library)
    #expect(try store.imageData(fileName: fileName) == Data([9, 8, 7]))
    let weird = try store.importImage(data: Data([1]), fileExtension: "exe")
    #expect(weird.hasSuffix(".png"))
}

@Test func test_imageGC_listsFilesOutsideReferencedSet() {
    #expect(ImageGC.unreferenced(onDisk: ["a.png", "b.png"], keeping: ["a.png"]) == ["b.png"])
}

@Test @MainActor func test_appModel_persistsStroke_andKeepsImageUntilHistoryDropsIt() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let model = try AppModel(root: root, historyLimit: 1)
    let folderID = try #require(model.library.folders.first?.id)
    let boardID = try #require(model.library.folders.first?.boards.first?.id)
    model.selection = BoardSelection(folderID: folderID, boardID: boardID)

    let strokeID = UUID()
    try model.change { library in
        try library.addElement(
            folderID: folderID,
            boardID: boardID,
            element: .stroke(Stroke(id: strokeID, points: [CGPoint(x: 1, y: 2)], colorHex: "112233", width: 4))
        )
    }
    let reloaded = try AppModel(root: root, historyLimit: 1)
    #expect(reloaded.library.board(folderID: folderID, boardID: boardID)?.elements.first?.id == strokeID)

    let fileName = try model.store.importImage(data: Data([4, 5, 6]), fileExtension: "png")
    let imageID = UUID()
    try model.change { library in
        try library.addElement(
            folderID: folderID,
            boardID: boardID,
            element: .image(PlacedImage(id: imageID, origin: CGPoint(x: 3, y: 4), width: 20, height: 20, fileName: fileName))
        )
    }
    try model.change { library in
        try library.deleteElement(folderID: folderID, boardID: boardID, elementID: imageID)
    }
    #expect(try model.store.imageData(fileName: fileName) == Data([4, 5, 6]))
    try model.change { library in
        try library.renameBoard(folderID: folderID, boardID: boardID, name: "Renamed")
    }
    #expect(throws: CocoaError.self) {
        try model.store.imageData(fileName: fileName)
    }
}

@Test func test_board_missingStyle_decodesClean() throws {
    let json = """
    {"id":"00000000-0000-0000-0000-00000000000A","name":"Scratch","elements":[]}
    """.data(using: .utf8)!
    let board = try JSONDecoder().decode(Board.self, from: json)
    #expect(board.style == .clean)
}

@Test func test_sketchPasses_stayPut_andLeaveTheLine() {
    let points = [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0), CGPoint(x: 80, y: 10)]
    let once = SketchLook.passes(points: points, seed: 42)
    let twice = SketchLook.passes(points: points, seed: 42)
    #expect(once == twice)
    #expect(once.count == 2)
    #expect(once[0] != points)
    #expect(SketchLook.passes(points: points, seed: 7)[0] != once[0])
}

@Test func test_removeClickMarks_dropsDot_keepsDrawing() throws {
    var library = Library()
    let folderID = try library.addFolder(name: "F")
    let boardID = try library.addBoard(folderID: folderID, name: "B")
    let dot = Stroke(id: UUID(), points: [CGPoint(x: 4, y: 4)], colorHex: "000000", width: 3)
    let drawing = Stroke(id: UUID(), points: [CGPoint(x: 4, y: 4), CGPoint(x: 80, y: 40)], colorHex: "000000", width: 3)
    try library.addElement(folderID: folderID, boardID: boardID, element: .stroke(dot))
    try library.addElement(folderID: folderID, boardID: boardID, element: .stroke(drawing))
    let removed = library.removeClickMarks(folderID: folderID, boardID: boardID, near: CGPoint(x: 5, y: 5))
    let left = library.board(folderID: folderID, boardID: boardID)?.elements.map(\.id)
    #expect(removed)
    #expect(left == [drawing.id])
}

@Test func test_connector_followsBoxes_andOldArrowDecodes() throws {
    let left = Diagram(id: UUID(), kind: .rectangle, start: .zero, end: CGPoint(x: 40, y: 40), colorHex: "111111", width: 2)
    let right = Diagram(id: UUID(), kind: .rectangle, start: CGPoint(x: 120, y: 10), end: CGPoint(x: 160, y: 50), colorHex: "111111", width: 2)
    let arrow = Diagram(
        id: UUID(),
        kind: .arrow,
        start: CGPoint(x: 20, y: 20),
        end: CGPoint(x: 140, y: 30),
        colorHex: "111111",
        width: 2,
        startBind: left.id,
        endBind: right.id
    )
    let route = ConnectorRoute.points(for: arrow, among: [.diagram(left), .diagram(right), .diagram(arrow)])
    #expect(route.first == CGPoint(x: 40, y: 30))
    #expect(route.last == CGPoint(x: 120, y: 20))
    #expect(HitTest.element(at: CGPoint(x: 80, y: 25), in: [.diagram(left), .diagram(right), .diagram(arrow)]) == arrow.id)

    var moved = left
    moved.start.x += 10
    moved.end.x += 10
    let followed = ConnectorRoute.points(for: arrow, among: [.diagram(moved), .diagram(right), .diagram(arrow)])
    #expect(followed.first?.x == 50)

    let json = """
    {"colorHex":"111111","end":[10,0],"id":"00000000-0000-0000-0000-00000000000B","kind":"arrow","start":[0,0],"width":2}
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(Diagram.self, from: json)
    #expect(decoded.startBind == nil)
    #expect(decoded.endBind == nil)
}

@Test func test_roughEdges_bowTwice_andStayStable() {
    let rect = SketchLook.roughEdges(kind: .rectangle, from: .zero, to: CGPoint(x: 80, y: 50), seed: 9)
    let again = SketchLook.roughEdges(kind: .rectangle, from: .zero, to: CGPoint(x: 80, y: 50), seed: 9)
    #expect(rect == again)
    #expect(rect.count == 4)
    #expect(rect.allSatisfy { $0.count == 2 })
    let curve = rect[0][0]
    let mid = CGPoint(x: (curve.start.x + curve.end.x) / 2, y: (curve.start.y + curve.end.y) / 2)
    let bow = hypot(curve.control.x - mid.x, curve.control.y - mid.y)
    #expect(bow > 0.4)
    #expect(bow < 18)
    let ellipse = SketchLook.roughEdges(kind: .ellipse, from: .zero, to: CGPoint(x: 60, y: 40), seed: 3)
    #expect(ellipse.count >= 4)
    let arrow = SketchLook.roughEdges(kind: .arrow, from: .zero, to: CGPoint(x: 40, y: 0), seed: 2)
    #expect(arrow.count == 3)
    let hatch = SketchLook.hachure(from: .zero, to: CGPoint(x: 80, y: 50), seed: 4)
    #expect(hatch.count >= 3)
}

@Test func test_keys_deleteUndoAndTools_skipTextEditing() {
    #expect(CanvasKeys.action(keyCode: 51, characters: "", command: false, shift: false, option: false, control: false, editingText: false) == .deleteSelection)
    #expect(CanvasKeys.action(keyCode: 51, characters: "", command: false, shift: false, option: false, control: false, editingText: true) == nil)
    #expect(CanvasKeys.action(keyCode: 6, characters: "z", command: true, shift: false, option: false, control: false, editingText: false) == .undo)
    #expect(CanvasKeys.action(keyCode: 6, characters: "z", command: true, shift: true, option: false, control: false, editingText: false) == .redo)
    #expect(CanvasKeys.action(keyCode: 15, characters: "r", command: false, shift: false, option: false, control: false, editingText: false) == .tool(.rectangle))
    #expect(CanvasKeys.action(keyCode: 9, characters: "v", command: false, shift: false, option: false, control: false, editingText: false) == .tool(.select))
}

@Test func test_diagram_outlineMoveAndHit() throws {
    let box = Diagram(id: UUID(), kind: .rectangle, start: .zero, end: CGPoint(x: 40, y: 30), colorHex: "111111", width: 2)
    #expect(HitTest.element(at: CGPoint(x: -6, y: 12), in: [.diagram(box)]) == box.id)
    #expect(HitTest.element(at: CGPoint(x: -30, y: 12), in: [.diagram(box)]) == nil)
    let shrunk = box.resized(.topLeft, to: CGPoint(x: 4, y: 6))
    #expect(shrunk.start == CGPoint(x: 4, y: 6))
    #expect(shrunk.end == CGPoint(x: 40, y: 30))

    var library = Library()
    let folderID = try library.addFolder(name: "F")
    let boardID = try library.addBoard(folderID: folderID, name: "B")
    let diagram = Diagram(
        id: UUID(),
        kind: .arrow,
        start: .zero,
        end: CGPoint(x: 30, y: 0),
        colorHex: "111111",
        width: 2
    )
    try library.addElement(folderID: folderID, boardID: boardID, element: .diagram(diagram))
    let near = HitTest.element(at: CGPoint(x: 15, y: 2), in: library.board(folderID: folderID, boardID: boardID)!.elements)
    let far = HitTest.element(at: CGPoint(x: 15, y: 40), in: library.board(folderID: folderID, boardID: boardID)!.elements)
    #expect(near == diagram.id)
    #expect(far == nil)
    try library.updateElement(folderID: folderID, boardID: boardID, elementID: diagram.id) {
        $0 = $0.moved(by: CGSize(width: 5, height: 4))
    }
    let moved = library.board(folderID: folderID, boardID: boardID)!.elements[0]
    #expect(moved == .diagram(Diagram(id: diagram.id, kind: .arrow, start: CGPoint(x: 5, y: 4), end: CGPoint(x: 35, y: 4), colorHex: "111111", width: 2)))

    try library.setStyle(folderID: folderID, boardID: boardID, style: .sketch)
    #expect(library.board(folderID: folderID, boardID: boardID)?.style == .sketch)
}

@Test @MainActor func test_createBoard_selectsIt_andUndoRestoresImageElement() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let model = try AppModel(root: root)
    try model.change { $0.folders.removeAll() }
    let boardID = try model.createBoard(name: "Map")
    #expect(model.selection?.boardID == boardID)
    #expect(model.library.folders.count == 1)

    let folderID = try #require(model.selection?.folderID)
    let fileName = try model.store.importImage(data: Data([1, 1, 1]), fileExtension: "png")
    let imageID = UUID()
    try model.change { library in
        try library.addElement(
            folderID: folderID,
            boardID: boardID,
            element: .image(PlacedImage(id: imageID, origin: .zero, width: 8, height: 8, fileName: fileName))
        )
    }
    try model.change { library in
        try library.deleteElement(folderID: folderID, boardID: boardID, elementID: imageID)
    }
    try model.undo()
    #expect(model.library.board(folderID: folderID, boardID: boardID)?.elements.contains(where: { $0.id == imageID }) == true)
    #expect(try model.store.imageData(fileName: fileName) == Data([1, 1, 1]))
}
