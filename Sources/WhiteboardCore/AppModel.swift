import Foundation
import Observation

public enum CanvasTool: String, CaseIterable, Identifiable, Sendable {
    case select, hand, pen, text, rectangle, ellipse, diamond, arrow
    public var id: String { rawValue }

    public var diagramKind: DiagramKind? {
        switch self {
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .diamond: .diamond
        case .arrow: .arrow
        default: nil
        }
    }
}

public enum CanvasKey: Equatable, Sendable {
    case deleteSelection
    case undo
    case redo
    case tool(CanvasTool)
}

public enum CanvasKeys {
    public static func action(
        keyCode: UInt16,
        characters: String,
        command: Bool,
        shift: Bool,
        option: Bool,
        control: Bool,
        editingText: Bool
    ) -> CanvasKey? {
        if editingText { return nil }
        if keyCode == 51 || keyCode == 117 { return .deleteSelection }
        let chars = characters.lowercased()
        if command, chars == "z" { return shift ? .redo : .undo }
        if command || option || control { return nil }
        switch chars {
        case "v": return .tool(.select)
        case "h": return .tool(.hand)
        case "p": return .tool(.pen)
        case "t": return .tool(.text)
        case "r": return .tool(.rectangle)
        case "o": return .tool(.ellipse)
        case "d": return .tool(.diamond)
        case "a": return .tool(.arrow)
        default: return nil
        }
    }
}

public struct BoardSelection: Hashable, Sendable {
    public var folderID: UUID
    public var boardID: UUID

    public init(folderID: UUID, boardID: UUID) {
        self.folderID = folderID
        self.boardID = boardID
    }
}

@MainActor
@Observable
public final class AppModel {
    public private(set) var history: History<Library>
    public var selection: BoardSelection?
    public var tool: CanvasTool = .pen
    public var colorHex: String = "1F2328"
    public var strokeWidth: Double = 3
    public let store: DiskStore

    // ponytail: undo keeps whole-library copies, cap historyLimit. Image files stay while any copy still points at them.
    // Nested folders omitted. Upgrade path: op-log history, then folder tree.
    private let historyLimit: Int
    private var gestureBaseline: Library?

    public var library: Library { history.present }
    public var canUndo: Bool { history.canUndo }
    public var canRedo: Bool { history.canRedo }

    public init(root: URL, historyLimit: Int = 50) throws {
        self.store = DiskStore(root: root)
        self.historyLimit = historyLimit
        if let loaded = try store.load() {
            history = History(present: loaded, limit: historyLimit)
        } else {
            let seeded = Library.seed()
            history = History(present: seeded, limit: historyLimit)
            try store.save(seeded)
        }
    }

    public static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("MacWhiteboard", isDirectory: true)
    }

    public func change(_ body: (inout Library) throws -> Void) throws {
        try commitGesture()
        var next = history.present
        try body(&next)
        history.commit(next)
        try persist()
    }

    public func preview(_ body: (inout Library) throws -> Void) throws {
        if gestureBaseline == nil { gestureBaseline = history.present }
        var next = history.present
        try body(&next)
        history.setPresent(next)
    }

    public func cancelGesture() {
        guard let baseline = gestureBaseline else { return }
        history.setPresent(baseline)
        gestureBaseline = nil
    }

    public func commitGesture() throws {
        guard let baseline = gestureBaseline else { return }
        let result = history.present
        gestureBaseline = nil
        history.setPresent(baseline)
        history.commit(result)
        try persist()
    }

    public func undo() throws {
        try commitGesture()
        history.undo()
        try persist()
    }

    public func redo() throws {
        try commitGesture()
        history.redo()
        try persist()
    }

    @discardableResult
    public func createFolder(name: String = "Folder") throws -> UUID {
        let id = UUID()
        try change { _ = try $0.addFolder(name: name, id: id) }
        return id
    }

    @discardableResult
    public func createBoard(in folderID: UUID? = nil, name: String = "Board") throws -> UUID {
        if library.folders.isEmpty {
            _ = try createFolder()
        }
        let preferred = folderID ?? selection?.folderID
        let folderID = library.folders.first { $0.id == preferred }?.id ?? library.folders[0].id
        let boardID = UUID()
        try change { _ = try $0.addBoard(folderID: folderID, name: name, id: boardID) }
        selection = BoardSelection(folderID: folderID, boardID: boardID)
        return boardID
    }

    public func addImage(data: Data, fileExtension: String, origin: CGPoint, size: CGSize) throws {
        guard let selection else { throw LibraryError.missingBoard }
        let fileName = try store.importImage(data: data, fileExtension: fileExtension)
        let image = PlacedImage(
            id: UUID(),
            origin: origin,
            width: size.width,
            height: size.height,
            fileName: fileName
        )
        try change { library in
            try library.addElement(folderID: selection.folderID, boardID: selection.boardID, element: .image(image))
        }
    }

    private func persist() throws {
        try store.save(history.present)
        let keeping = Set(history.retained().flatMap(\.allImageFileNames))
        try store.purgeImages(keeping: keeping)
    }
}
