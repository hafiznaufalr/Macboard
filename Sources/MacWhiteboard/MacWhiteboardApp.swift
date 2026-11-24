import AppKit
import SwiftUI
import WhiteboardCore

@main
struct MacWhiteboardApp: App {
    @State private var model: AppModel?
    @State private var bootError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if let model {
                    RootView(model: model)
                } else if let bootError {
                    Text(bootError).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                }
            }
            .frame(minWidth: 900, minHeight: 600)
            .task {
                guard model == nil else { return }
                do {
                    model = try AppModel(root: AppModel.defaultRoot())
                } catch {
                    bootError = error.localizedDescription
                }
            }
        }
        .defaultSize(width: 1200, height: 800)
    }
}

struct RootView: View {
    @Bindable var model: AppModel
    @State private var expanded: Set<UUID> = []
    @State private var rename: RenameTarget?
    @State private var pendingDelete: DeleteTarget?
    @State private var renameText = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                ForEach(model.library.folders) { folder in
                    DisclosureGroup(isExpanded: expandedBinding(folder.id)) {
                        ForEach(folder.boards) { board in
                            Text(board.name)
                                .tag(BoardSelection(folderID: folder.id, boardID: board.id))
                                .contextMenu {
                                    Button("Rename") { beginRename(.board(folder.id, board.id), current: board.name) }
                                    Button("Delete", role: .destructive) {
                                        pendingDelete = .board(folder.id, board.id)
                                    }
                                }
                        }
                    } label: {
                        Label(folder.name, systemImage: "folder")
                            .contextMenu {
                                Button("New Board") { newBoard(in: folder.id) }
                                Button("Rename") { beginRename(.folder(folder.id), current: folder.name) }
                                Button("Delete", role: .destructive) { pendingDelete = .folder(folder.id) }
                            }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .toolbar {
                Button {
                    if let id = try? model.createFolder() { expanded.insert(id) }
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                Button { _ = try? model.createBoard(in: model.selection?.folderID) } label: {
                    Label("New Board", systemImage: "plus.rectangle")
                }
            }
        } detail: {
            if let selection = model.selection,
               model.library.board(folderID: selection.folderID, boardID: selection.boardID) != nil {
                CanvasScreen(model: model)
            } else {
                ContentUnavailableView(
                    "No board open",
                    systemImage: "scribble.variable",
                    description: Text("Make a folder, then a board. Everything stays on this Mac.")
                )
            }
        }
        .onAppear {
            expanded.formUnion(model.library.folders.map(\.id))
            if model.selection == nil,
               let folder = model.library.folders.first,
               let board = folder.boards.first {
                model.selection = BoardSelection(folderID: folder.id, boardID: board.id)
            }
        }
        .sheet(item: $rename) { target in
            VStack(alignment: .leading, spacing: 12) {
                Text(target.title).font(.headline)
                TextField("Name", text: $renameText)
                    .onSubmit { applyRename(target) }
                HStack {
                    Spacer()
                    Button("Cancel") { rename = nil }
                    Button("Save") { applyRename(target) }
                        .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(width: 280)
        }
        .alert(pendingDelete?.title ?? "Delete?", isPresented: deletePresented) {
            Button("Delete", role: .destructive) { applyDelete() }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(pendingDelete?.message ?? "")
        }
    }

    private var deletePresented: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func expandedBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isExpanded in
                if isExpanded { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }

    private func newBoard(in folderID: UUID) {
        _ = try? model.createBoard(in: folderID)
        expanded.insert(folderID)
    }

    private func beginRename(_ target: RenameTarget, current: String) {
        renameText = current
        rename = target
    }

    private func applyRename(_ target: RenameTarget) {
        switch target {
        case .folder(let id):
            try? model.change { try $0.renameFolder(id: id, name: renameText) }
        case .board(let folderID, let boardID):
            try? model.change { try $0.renameBoard(folderID: folderID, boardID: boardID, name: renameText) }
        }
        rename = nil
    }

    private func applyDelete() {
        switch pendingDelete {
        case .folder(let id):
            try? model.change { try $0.deleteFolder(id: id) }
            if model.selection?.folderID == id { model.selection = nil }
        case .board(let folderID, let boardID):
            try? model.change { try $0.deleteBoard(folderID: folderID, boardID: boardID) }
            if model.selection?.boardID == boardID { model.selection = nil }
        case nil:
            break
        }
        pendingDelete = nil
    }
}

private enum RenameTarget: Identifiable {
    case folder(UUID)
    case board(UUID, UUID)

    var id: String {
        switch self {
        case .folder(let id): "f-\(id)"
        case .board(let folder, let board): "b-\(folder)-\(board)"
        }
    }

    var title: String {
        switch self {
        case .folder: "Rename folder"
        case .board: "Rename board"
        }
    }
}

private enum DeleteTarget {
    case folder(UUID)
    case board(UUID, UUID)

    var title: String {
        switch self {
        case .folder: "Delete folder?"
        case .board: "Delete board?"
        }
    }

    var message: String {
        switch self {
        case .folder: "Boards inside this folder go too. Stays on this Mac only."
        case .board: "This board and its drawing go. Stays on this Mac only."
        }
    }
}

private struct CanvasScreen: View {
    @Bindable var model: AppModel
    @State private var camera = Camera()
    @State private var viewSize: CGSize = .zero
    @State private var selectedID: UUID?
    @State private var dragMode: DragMode?
    @State private var lastTranslation: CGSize = .zero
    @State private var lastWorld: CGPoint = .zero
    @State private var pinchBase: CGFloat?
    @State private var importing = false
    @State private var imageCache: [String: NSImage] = [:]
    @State private var noteDraft = ""
    @State private var lastBoardTap: (Date, CGPoint)?
    @State private var typingNoteID: UUID?
    @FocusState private var noteFocused: Bool

    private let colors = ["1F2328", "E03131", "F08C00", "2F9E44", "1971C2", "9C36B5"]

    private var selection: BoardSelection? { model.selection }

    private var elements: [BoardElement] {
        guard let selection else { return [] }
        return model.library.board(folderID: selection.folderID, boardID: selection.boardID)?.elements ?? []
    }

    private var sketching: Bool {
        guard let selection else { return false }
        return model.library.board(folderID: selection.folderID, boardID: selection.boardID)?.style == .sketch
    }

    private var selectedNote: Note? {
        guard let selectedID, case .note(let note) = elements.first(where: { $0.id == selectedID }) else { return nil }
        return note
    }

    var body: some View {
        VStack(spacing: 0) {
            toolBar
            canvas
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { importImage(url) }
        }
        .onChange(of: selectedID) { _, id in
            if typingNoteID != nil, id != typingNoteID {
                typingNoteID = nil
                noteFocused = false
            }
            try? model.commitGesture()
            noteDraft = selectedNote?.text ?? ""
        }
        .onChange(of: elements.map(\.id)) { _, _ in
            loadImages()
        }
        .onAppear {
            loadImages()
            noteDraft = selectedNote?.text ?? ""
        }
        .onDisappear { try? model.commitGesture() }
        .task(id: noteDraft) {
            guard selectedNote != nil else { return }
            try? await Task.sleep(for: .milliseconds(400))
            try? model.commitGesture()
        }
    }

    private var toolBar: some View {
        HStack(spacing: 8) {
            toolButton(.select, "cursorarrow", "Select")
            toolButton(.hand, "hand.raised", "Hand")
            toolButton(.pen, "pencil.tip", "Pen")
            toolButton(.text, "textformat", "Note")
            toolButton(.rectangle, "rectangle", "Rectangle")
            toolButton(.ellipse, "circle", "Ellipse")
            toolButton(.diamond, "diamond", "Diamond")
            toolButton(.arrow, "arrow.up.right", "Arrow")
            Button { toggleSketch() } label: {
                Text("Sketch")
                    .font(sketching ? .custom("Bradley Hand", size: 16) : .body)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 6).fill(sketching ? Color.accentColor.opacity(0.22) : .clear))
            }
            .buttonStyle(.plain)
            .help("Handwriting diagram style")
            Button { importing = true } label: { Image(systemName: "photo") }
                .help("Add image")
            Divider().frame(height: 18)
            ForEach(colors, id: \.self) { hex in
                Button {
                    model.colorHex = hex
                    if model.tool.diagramKind == nil, model.tool != .pen, model.tool != .text {
                        model.tool = .pen
                    }
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.primary.opacity(model.colorHex == hex ? 0.8 : 0.15), lineWidth: model.colorHex == hex ? 2 : 1))
                }
                .buttonStyle(.plain)
            }
            Slider(value: $model.strokeWidth, in: 1...16, step: 1).frame(width: 90)
            Spacer()
            Button { try? model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
                .help("Undo (⌘Z)")
            Button { try? model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo)
                .help("Redo (⇧⌘Z)")
            Button { camera.zoom(by: 1 / 1.1) } label: { Image(systemName: "minus.magnifyingglass") }
            Text("\(Int((camera.scale * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .frame(width: 42)
            Button { camera.zoom(by: 1.1) } label: { Image(systemName: "plus.magnifyingglass") }
            Button(role: .destructive) { deleteSelected() } label: { Image(systemName: "trash") }
                .disabled(selectedID == nil)
                .help("Delete")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var canvas: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Color(red: 0.96, green: 0.95, blue: 0.93)
                Canvas { context, canvasSize in
                    drawBoard(context: &context, size: canvasSize)
                }
                .allowsHitTesting(false)
                ForEach(elements) { element in
                    elementView(element, size: size)
                        .allowsHitTesting(isTyping(element))
                }
                Canvas { context, canvasSize in
                    drawSelection(context: &context, size: canvasSize)
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(drag(size: size))
            .simultaneousGesture(pinch)
            .background(WheelCatcher(
                onScroll: { dx, dy, zoom in
                    if zoom {
                        if dy != 0 { camera.zoom(by: dy > 0 ? 1.05 : 0.95) }
                    } else {
                        camera.pan(screenDelta: CGSize(width: dx, height: dy))
                    }
                },
                onKey: { keyCode, characters, command, shift, option, control in
                    handleKey(keyCode, characters, command, shift, option, control)
                }
            ))
            .onAppear { viewSize = size }
            .onChange(of: size) { _, newSize in viewSize = newSize }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else {
                        url = item as? URL
                    }
                    guard let url else { return }
                    DispatchQueue.main.async { importImage(url) }
                }
                return true
            }
        }
    }

    private var pinch: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if pinchBase == nil { pinchBase = camera.scale }
                camera.scale = min(4, max(0.2, (pinchBase ?? 1) * value))
            }
            .onEnded { _ in pinchBase = nil }
    }

    private func toolButton(_ tool: CanvasTool, _ symbol: String, _ help: String) -> some View {
        Button { model.tool = tool } label: {
            Image(systemName: symbol)
                .frame(width: 22, height: 18)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(model.tool == tool ? Color.accentColor.opacity(0.22) : .clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private func elementView(_ element: BoardElement, size: CGSize) -> some View {
        switch element {
        case .stroke, .diagram:
            EmptyView()
        case .note(let note):
            let origin = camera.screenPoint(fromWorld: note.origin, viewSize: size)
            noteBody(note)
                .font(noteFont)
                .padding(8 * camera.scale)
                .frame(
                    width: note.width * camera.scale,
                    height: Note.height * camera.scale,
                    alignment: .topLeading
                )
                .background {
                    if !sketching {
                        RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.94))
                    }
                }
                .overlay {
                    if !sketching {
                        RoundedRectangle(cornerRadius: 8).stroke(.black.opacity(0.08))
                    }
                }
                .rotationEffect(.degrees(sketching ? SketchLook.tiltDegrees(seed: SketchLook.seed(for: note.id)) : 0))
                .offset(x: origin.x, y: origin.y)
        case .image(let image):
            let origin = camera.screenPoint(fromWorld: image.origin, viewSize: size)
            imageContent(image)
                .frame(width: image.width * camera.scale, height: image.height * camera.scale)
                .offset(x: origin.x, y: origin.y)
        }
    }

    @ViewBuilder
    private func noteBody(_ note: Note) -> some View {
        if typingNoteID == note.id {
            TextField("Type", text: $noteDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundStyle(Color(hex: "1F2328"))
                .focused($noteFocused)
                .onAppear { noteFocused = true }
                .onChange(of: noteDraft) { _, newValue in
                    updateSelectedNote(newValue)
                }
        } else {
            Text(note.text.isEmpty ? "Text" : note.text)
                .foregroundStyle(note.text.isEmpty ? .secondary : Color(hex: "1F2328"))
        }
    }

    private func isTyping(_ element: BoardElement) -> Bool {
        guard case .note(let note) = element else { return false }
        return typingNoteID == note.id
    }

    @ViewBuilder
    private func imageContent(_ image: PlacedImage) -> some View {
        if let nsImage = imageCache[image.fileName] {
            Image(nsImage: nsImage).resizable().interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: 4).fill(.gray.opacity(0.25))
        }
    }

    private func drawBoard(context: inout GraphicsContext, size: CGSize) {
        let topLeft = camera.worldPoint(fromScreen: .zero, viewSize: size)
        let bottomRight = camera.worldPoint(fromScreen: CGPoint(x: size.width, y: size.height), viewSize: size)
        let step: CGFloat = 28
        var x = floor(topLeft.x / step) * step
        while x <= bottomRight.x {
            var y = floor(topLeft.y / step) * step
            while y <= bottomRight.y {
                let screen = camera.screenPoint(fromWorld: CGPoint(x: x, y: y), viewSize: size)
                let dot = CGRect(x: screen.x - 1, y: screen.y - 1, width: 2, height: 2)
                context.fill(Path(ellipseIn: dot), with: .color(.black.opacity(0.16)))
                y += step
            }
            x += step
        }
        for element in elements {
            switch element {
            case .stroke(let stroke):
                drawPolyline(stroke.points, color: stroke.colorHex, width: stroke.width, size: size, context: &context)
            case .diagram(let diagram):
                drawDiagramShape(diagram, size: size, context: &context)
            case .note, .image:
                break
            }
        }
    }

    private var noteFont: Font {
        sketching
            ? .custom("Bradley Hand", size: max(15, 20 * camera.scale))
            : .system(size: max(11, 14 * camera.scale))
    }

    private func drawDiagramShape(_ diagram: Diagram, size: CGSize, context: inout GraphicsContext) {
        let seed = SketchLook.seed(for: diagram.id)
        if diagram.kind != .arrow {
            let box = hachureBox(diagram)
            for line in SketchLook.hachure(from: box.0, to: box.1, seed: seed) {
                drawCurves([line], color: diagram.colorHex, width: 1, opacity: 0.45, size: size, context: &context)
            }
        }
        let edges = diagram.kind == .arrow
            ? SketchLook.roughChain(ConnectorRoute.points(for: diagram, among: elements), seed: seed)
            : SketchLook.roughEdges(kind: diagram.kind, from: diagram.start, to: diagram.end, seed: seed)
        for edge in edges {
            drawCurves(edge, color: diagram.colorHex, width: diagram.width, opacity: 1, size: size, context: &context)
        }
    }

    private func hachureBox(_ diagram: Diagram) -> (CGPoint, CGPoint) {
        let minX = min(diagram.start.x, diagram.end.x)
        let minY = min(diagram.start.y, diagram.end.y)
        let maxX = max(diagram.start.x, diagram.end.x)
        let maxY = max(diagram.start.y, diagram.end.y)
        let pad = diagram.kind == .rectangle ? 0 : min(maxX - minX, maxY - minY) * 0.16
        return (CGPoint(x: minX + pad, y: minY + pad), CGPoint(x: maxX - pad, y: maxY - pad))
    }

    private func drawPolyline(
        _ points: [CGPoint],
        color: String,
        width: Double,
        size: CGSize,
        context: inout GraphicsContext
    ) {
        guard let first = points.first else { return }
        var path = Path()
        let start = camera.screenPoint(fromWorld: first, viewSize: size)
        if points.count == 1 {
            path.addEllipse(in: CGRect(x: start.x - 1, y: start.y - 1, width: 2, height: 2))
        } else {
            path.move(to: start)
            for point in points.dropFirst() {
                path.addLine(to: camera.screenPoint(fromWorld: point, viewSize: size))
            }
        }
        context.stroke(
            path,
            with: .color(Color(hex: color)),
            style: StrokeStyle(lineWidth: width * camera.scale, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawCurves(
        _ curves: [RoughCurve],
        color: String,
        width: Double,
        opacity: Double,
        size: CGSize,
        context: inout GraphicsContext
    ) {
        var path = Path()
        for curve in curves {
            path.move(to: camera.screenPoint(fromWorld: curve.start, viewSize: size))
            path.addQuadCurve(
                to: camera.screenPoint(fromWorld: curve.end, viewSize: size),
                control: camera.screenPoint(fromWorld: curve.control, viewSize: size)
            )
        }
        context.stroke(
            path,
            with: .color(Color(hex: color).opacity(opacity)),
            style: StrokeStyle(lineWidth: max(1, width) * camera.scale, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawSelection(context: inout GraphicsContext, size: CGSize) {
        guard let selectedID, let element = elements.first(where: { $0.id == selectedID }) else { return }
        let rect = selectionBounds(element)
        guard !rect.isNull, !rect.isInfinite else { return }
        let a = camera.screenPoint(fromWorld: CGPoint(x: rect.minX, y: rect.minY), viewSize: size)
        let b = camera.screenPoint(fromWorld: CGPoint(x: rect.maxX, y: rect.maxY), viewSize: size)
        let box = CGRect(
            x: min(a.x, b.x) - 3,
            y: min(a.y, b.y) - 3,
            width: abs(b.x - a.x) + 6,
            height: abs(b.y - a.y) + 6
        )
        context.stroke(Path(roundedRect: box, cornerRadius: 4), with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        if case .diagram(let diagram) = element {
            let handles = diagram.kind == .arrow ? arrowHandles(diagram) : diagram.handles()
            for (_, point) in handles {
                let screen = camera.screenPoint(fromWorld: point, viewSize: size)
                let handle = CGRect(x: screen.x - 4, y: screen.y - 4, width: 8, height: 8)
                context.fill(Path(roundedRect: handle, cornerRadius: 1.5), with: .color(.white))
                context.stroke(Path(roundedRect: handle, cornerRadius: 1.5), with: .color(.accentColor), lineWidth: 1.5)
            }
        }
    }

    private func drag(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let world = camera.worldPoint(fromScreen: value.location, viewSize: size)
                switch model.tool {
                case .hand:
                    pan(by: value.translation)
                case .pen:
                    drawPen(at: world)
                case .select:
                    selectDrag(world: world, translation: value.translation)
                case .text:
                    break
                case .rectangle, .ellipse, .diamond, .arrow:
                    if let kind = model.tool.diagramKind { drawDiagram(kind, at: world) }
                }
            }
            .onEnded { value in
                let travel = hypot(value.translation.width, value.translation.height)
                let world = camera.worldPoint(fromScreen: value.startLocation, viewSize: size)
                if travel < 6, registerDoubleTap(at: world) {
                    beginTyping(at: world)
                    dragMode = nil
                    lastTranslation = .zero
                    return
                }
                let drawnID: UUID? = switch dragMode {
                case .pen(let id), .diagram(let id): id
                default: nil
                }
                if model.tool == .text, travel < 4 {
                    addNote(at: world)
                } else if model.tool == .select, travel < 4 {
                    selectedID = HitTest.element(at: world, in: elements)
                }
                if let drawnID { selectedID = drawnID }
                try? model.commitGesture()
                dragMode = nil
                lastTranslation = .zero
            }
    }

    private func handleKey(_ keyCode: UInt16, _ characters: String, _ command: Bool, _ shift: Bool, _ option: Bool, _ control: Bool) -> Bool {
        let editing = NSApp.keyWindow?.firstResponder is NSTextView
        guard let action = CanvasKeys.action(
            keyCode: keyCode,
            characters: characters,
            command: command,
            shift: shift,
            option: option,
            control: control,
            editingText: editing
        ) else { return false }
        switch action {
        case .deleteSelection:
            deleteSelected()
        case .undo:
            try? model.undo()
        case .redo:
            try? model.redo()
        case .tool(let tool):
            model.tool = tool
        }
        return true
    }

    private func pan(by translation: CGSize) {
        let delta = CGSize(width: translation.width - lastTranslation.width, height: translation.height - lastTranslation.height)
        lastTranslation = translation
        camera.pan(screenDelta: delta)
    }

    private func drawPen(at world: CGPoint) {
        guard let selection else { return }
        if dragMode == nil { try? model.commitGesture() }
        if case .pen(let id) = dragMode {
            try? model.preview { library in
                try library.updateElement(folderID: selection.folderID, boardID: selection.boardID, elementID: id) { element in
                    guard case .stroke(var stroke) = element else { return }
                    stroke.points.append(world)
                    element = .stroke(stroke)
                }
            }
            return
        }
        let id = UUID()
        dragMode = .pen(id)
        try? model.preview { library in
            try library.addElement(
                folderID: selection.folderID,
                boardID: selection.boardID,
                element: .stroke(Stroke(id: id, points: [world], colorHex: model.colorHex, width: model.strokeWidth))
            )
        }
    }

    private func toggleSketch() {
        guard let selection else { return }
        let next: BoardStyle = sketching ? .clean : .sketch
        try? model.change { try $0.setStyle(folderID: selection.folderID, boardID: selection.boardID, style: next) }
    }

    private func drawDiagram(_ kind: DiagramKind, at world: CGPoint) {
        guard let selection else { return }
        if dragMode == nil { try? model.commitGesture() }
        if case .diagram(let id) = dragMode {
            try? model.preview { library in
                try library.updateElement(folderID: selection.folderID, boardID: selection.boardID, elementID: id) { element in
                    guard case .diagram(var diagram) = element else { return }
                    diagram.end = world
                    if diagram.kind == .arrow {
                        let startTarget = bindingTarget(at: diagram.start, ignoring: id)
                        let endTarget = bindingTarget(at: world, ignoring: id)
                        diagram.startBind = startTarget
                        diagram.endBind = endTarget == startTarget ? nil : endTarget
                    }
                    element = .diagram(diagram)
                }
            }
            return
        }
        let id = UUID()
        dragMode = .diagram(id)
        try? model.preview { library in
            try library.addElement(
                folderID: selection.folderID,
                boardID: selection.boardID,
                element: .diagram(Diagram(id: id, kind: kind, start: world, end: world, colorHex: model.colorHex, width: model.strokeWidth))
            )
        }
    }

    private func selectDrag(world: CGPoint, translation: CGSize) {
        switch dragMode {
        case .resize(let id, let handle):
            resize(id: id, handle: handle, to: world)
        case .move(let id, _):
            let delta = CGSize(width: world.x - lastWorld.x, height: world.y - lastWorld.y)
            lastWorld = world
            move(id: id, by: delta)
        case .pan:
            pan(by: translation)
        case .arm:
            if hypot(translation.width, translation.height) > 4 {
                dragMode = .pan
                lastTranslation = translation
            }
        case .pen, .diagram, nil:
            if let diagram = selectedDiagram, let handle = handleHit(diagram, point: world) {
                selectedID = diagram.id
                dragMode = .resize(diagram.id, handle)
            } else if let id = HitTest.element(at: world, in: elements) {
                selectedID = id
                if let arrow = elements.compactMap({ element -> Diagram? in
                    if case .diagram(let diagram) = element, diagram.id == id { diagram } else { nil }
                }).first, arrow.kind == .arrow, arrow.startBind != nil, arrow.endBind != nil {
                    dragMode = .arm
                } else {
                    dragMode = .move(id, world)
                    lastWorld = world
                    noteDraft = selectedNote?.text ?? ""
                }
            } else {
                selectedID = nil
                dragMode = .arm
                lastTranslation = translation
            }
        }
    }

    private var selectedDiagram: Diagram? {
        guard let selectedID, case .diagram(let diagram) = elements.first(where: { $0.id == selectedID }) else { return nil }
        return diagram
    }

    private func handleHit(_ diagram: Diagram, point: CGPoint) -> ResizeHandle? {
        let slop = 10 / max(camera.scale, 0.2)
        let handles = diagram.kind == .arrow ? arrowHandles(diagram) : diagram.handles()
        return handles.first { hypot($0.1.x - point.x, $0.1.y - point.y) <= slop }?.0
    }

    private func arrowHandles(_ diagram: Diagram) -> [(ResizeHandle, CGPoint)] {
        let route = ConnectorRoute.points(for: diagram, among: elements)
        guard let first = route.first, let last = route.last else {
            return [(.start, diagram.start), (.end, diagram.end)]
        }
        return [(.start, first), (.end, last)]
    }

    private func selectionBounds(_ element: BoardElement) -> CGRect {
        guard case .diagram(let diagram) = element, diagram.kind == .arrow else { return element.bounds }
        let route = ConnectorRoute.points(for: diagram, among: elements)
        guard let first = route.first else { return element.bounds }
        var rect = CGRect(origin: first, size: .zero)
        for point in route.dropFirst() {
            rect = rect.union(CGRect(origin: point, size: .zero))
        }
        return rect.insetBy(dx: -14, dy: -14)
    }

    private func bindingTarget(at point: CGPoint, ignoring arrowID: UUID) -> UUID? {
        for element in elements.reversed() {
            guard case .diagram(let diagram) = element, diagram.id != arrowID, diagram.kind != .arrow else { continue }
            if element.bounds.insetBy(dx: -14, dy: -14).contains(point) { return diagram.id }
        }
        return nil
    }

    private func resize(id: UUID, handle: ResizeHandle, to world: CGPoint) {
        guard let selection else { return }
        try? model.preview { library in
            try library.updateElement(folderID: selection.folderID, boardID: selection.boardID, elementID: id) { element in
                guard case .diagram(let diagram) = element else { return }
                element = .diagram(diagram.resized(handle, to: world))
            }
        }
    }

    private func move(id: UUID, by delta: CGSize) {
        guard let selection, delta != .zero else { return }
        try? model.preview { library in
            try library.updateElement(folderID: selection.folderID, boardID: selection.boardID, elementID: id) { element in
                element = element.moved(by: delta)
            }
        }
    }

    private func registerDoubleTap(at world: CGPoint) -> Bool {
        let now = Date()
        if let last = lastBoardTap,
           now.timeIntervalSince(last.0) < 0.35,
           hypot(world.x - last.1.x, world.y - last.1.y) < 18 {
            lastBoardTap = nil
            return true
        }
        lastBoardTap = (now, world)
        return false
    }

    private func beginTyping(at world: CGPoint) {
        model.cancelGesture()
        model.tool = .text
        if let note = note(at: world) {
            selectedID = note.id
            typingNoteID = note.id
            noteDraft = note.text
            focusNote()
            return
        }
        guard let selection else { return }
        var cleaned = model.library
        if cleaned.removeClickMarks(folderID: selection.folderID, boardID: selection.boardID, near: world),
           model.history.undoValue() == cleaned {
            try? model.undo()
        }
        let id = UUID()
        try? model.change { library in
            _ = library.removeClickMarks(folderID: selection.folderID, boardID: selection.boardID, near: world)
            try library.addElement(
                folderID: selection.folderID,
                boardID: selection.boardID,
                element: .note(Note(id: id, origin: world, text: "", width: 220))
            )
        }
        selectedID = id
        typingNoteID = id
        noteDraft = ""
        focusNote()
    }

    private func note(at point: CGPoint) -> Note? {
        for element in elements.reversed() {
            guard case .note(let note) = element, element.bounds.contains(point) else { continue }
            return note
        }
        return nil
    }

    private func focusNote() {
        Task { @MainActor in
            noteFocused = true
        }
    }

    private func addNote(at world: CGPoint) {
        guard let selection else { return }
        let id = UUID()
        try? model.change { library in
            try library.addElement(
                folderID: selection.folderID,
                boardID: selection.boardID,
                element: .note(Note(id: id, origin: world, text: "", width: 200))
            )
        }
        selectedID = id
        noteDraft = ""
    }

    private func updateSelectedNote(_ text: String) {
        guard let selection, let selectedID else { return }
        try? model.preview { library in
            try library.updateElement(folderID: selection.folderID, boardID: selection.boardID, elementID: selectedID) { element in
                guard case .note(var note) = element else { return }
                note.text = text
                element = .note(note)
            }
        }
    }

    private func deleteSelected() {
        guard let selection, let selectedID else { return }
        try? model.change { library in
            try library.deleteElement(folderID: selection.folderID, boardID: selection.boardID, elementID: selectedID)
        }
        self.selectedID = nil
    }

    private func importImage(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let nsImage = NSImage(data: data), nsImage.size.width > 0 else { return }
        let maxWidth: CGFloat = 360
        let fit = nsImage.size.width > maxWidth ? maxWidth / nsImage.size.width : 1
        let size = CGSize(width: nsImage.size.width * fit, height: nsImage.size.height * fit)
        let placed = CGPoint(x: camera.offset.x - size.width / 2, y: camera.offset.y - size.height / 2)
        try? model.addImage(data: data, fileExtension: url.pathExtension, origin: placed, size: size)
        loadImages()
    }

    private func loadImages() {
        for name in elements.compactMap({ element -> String? in
            if case .image(let image) = element { image.fileName } else { nil }
        }) where imageCache[name] == nil {
            imageCache[name] = NSImage(contentsOf: model.store.imageURL(fileName: name))
        }
    }
}

private enum DragMode {
    case pen(UUID)
    case diagram(UUID)
    case move(UUID, CGPoint)
    case resize(UUID, ResizeHandle)
    case arm
    case pan
}

private struct WheelCatcher: NSViewRepresentable {
    var onScroll: (CGFloat, CGFloat, Bool) -> Void
    var onKey: (UInt16, String, Bool, Bool, Bool, Bool) -> Bool

    func makeNSView(context: Context) -> WheelView {
        let view = WheelView()
        view.onScroll = onScroll
        view.onKey = onKey
        return view
    }

    func updateNSView(_ nsView: WheelView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onKey = onKey
    }
}

private final class WheelMonitor: @unchecked Sendable {
    var token: Any?

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        self.token = nil
    }

    deinit { stop() }
}

private final class WheelView: NSView {
    var onScroll: (CGFloat, CGFloat, Bool) -> Void = { _, _, _ in }
    var onKey: (UInt16, String, Bool, Bool, Bool, Bool) -> Bool = { _, _, _, _, _, _ in false }
    private let monitor = WheelMonitor()
    private let keys = WheelMonitor()

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        monitor.stop()
        keys.stop()
        guard window != nil else { return }
        monitor.token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            let local = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(local) else { return event }
            let unit: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16
            let zoom = event.modifierFlags.contains(.command)
            let dx = event.scrollingDeltaX * unit
            let dy = event.scrollingDeltaY * unit
            DispatchQueue.main.async { [weak self] in
                self?.onScroll(dx, dy, zoom)
            }
            return nil
        }
        keys.token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let characters = event.charactersIgnoringModifiers ?? ""
            let consumed = self.onKey(
                event.keyCode,
                characters,
                flags.contains(.command),
                flags.contains(.shift),
                flags.contains(.option),
                flags.contains(.control)
            )
            return consumed ? nil : event
        }
    }
}

private extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
