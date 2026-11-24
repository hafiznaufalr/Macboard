import CoreGraphics
import Foundation

public struct Library: Codable, Equatable, Sendable {
    public var folders: [Folder]

    public init(folders: [Folder] = []) {
        self.folders = folders
    }

    public static func seed() -> Library {
        let board = Board(id: UUID(), name: "Scratch", elements: [])
        return Library(folders: [Folder(id: UUID(), name: "Inbox", boards: [board])])
    }

    public var allImageFileNames: [String] {
        folders.flatMap(\.boards).flatMap(\.elements).compactMap { element in
            if case .image(let image) = element { image.fileName } else { nil }
        }
    }

    public func board(folderID: UUID, boardID: UUID) -> Board? {
        folders.first { $0.id == folderID }?.boards.first { $0.id == boardID }
    }

    public mutating func addFolder(name: String, id: UUID = UUID()) throws -> UUID {
        let folder = Folder(id: id, name: try Self.validated(name), boards: [])
        folders.append(folder)
        return folder.id
    }

    public mutating func renameFolder(id: UUID, name: String) throws {
        let name = try Self.validated(name)
        guard let index = folders.firstIndex(where: { $0.id == id }) else { throw LibraryError.missingFolder }
        folders[index].name = name
    }

    public mutating func deleteFolder(id: UUID) throws {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { throw LibraryError.missingFolder }
        folders.remove(at: index)
    }

    public mutating func addBoard(folderID: UUID, name: String, id: UUID = UUID()) throws -> UUID {
        let board = Board(id: id, name: try Self.validated(name), elements: [])
        try mutateFolder(folderID) { $0.boards.append(board) }
        return board.id
    }

    public mutating func renameBoard(folderID: UUID, boardID: UUID, name: String) throws {
        let name = try Self.validated(name)
        try mutateBoard(folderID: folderID, boardID: boardID) { $0.name = name }
    }

    public mutating func deleteBoard(folderID: UUID, boardID: UUID) throws {
        try mutateFolder(folderID) { folder in
            guard let index = folder.boards.firstIndex(where: { $0.id == boardID }) else { throw LibraryError.missingBoard }
            folder.boards.remove(at: index)
        }
    }

    public mutating func addElement(folderID: UUID, boardID: UUID, element: BoardElement) throws {
        try mutateBoard(folderID: folderID, boardID: boardID) { $0.elements.append(element) }
    }

    public mutating func deleteElement(folderID: UUID, boardID: UUID, elementID: UUID) throws {
        try mutateBoard(folderID: folderID, boardID: boardID) { board in
            guard let index = board.elements.firstIndex(where: { $0.id == elementID }) else { throw LibraryError.missingElement }
            board.elements.remove(at: index)
        }
    }

    public mutating func updateElement(
        folderID: UUID,
        boardID: UUID,
        elementID: UUID,
        _ body: (inout BoardElement) -> Void
    ) throws {
        try mutateBoard(folderID: folderID, boardID: boardID) { board in
            guard let index = board.elements.firstIndex(where: { $0.id == elementID }) else { throw LibraryError.missingElement }
            body(&board.elements[index])
        }
    }

    public mutating func setStyle(folderID: UUID, boardID: UUID, style: BoardStyle) throws {
        try mutateBoard(folderID: folderID, boardID: boardID) { $0.style = style }
    }

    @discardableResult
    public mutating func removeClickMarks(folderID: UUID, boardID: UUID, near point: CGPoint, radius: CGFloat = 22) -> Bool {
        var removed = false
        try? mutateBoard(folderID: folderID, boardID: boardID) { board in
            board.elements.removeAll { element in
                guard Self.isClickMark(element, near: point, radius: radius) else { return false }
                removed = true
                return true
            }
        }
        return removed
    }

    private static func isClickMark(_ element: BoardElement, near point: CGPoint, radius: CGFloat) -> Bool {
        switch element {
        case .stroke(let stroke):
            return !stroke.points.isEmpty && stroke.points.count <= 4 && stroke.points.allSatisfy {
                hypot($0.x - point.x, $0.y - point.y) <= radius
            }
        case .diagram(let diagram) where diagram.startBind == nil && diagram.endBind == nil:
            return hypot(diagram.start.x - point.x, diagram.start.y - point.y) <= radius
                && hypot(diagram.end.x - point.x, diagram.end.y - point.y) <= radius
        default:
            return false
        }
    }

    private mutating func mutateFolder(_ id: UUID, _ body: (inout Folder) throws -> Void) throws {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { throw LibraryError.missingFolder }
        try body(&folders[index])
    }

    private mutating func mutateBoard(folderID: UUID, boardID: UUID, _ body: (inout Board) throws -> Void) throws {
        try mutateFolder(folderID) { folder in
            guard let index = folder.boards.firstIndex(where: { $0.id == boardID }) else { throw LibraryError.missingBoard }
            try body(&folder.boards[index])
        }
    }

    private static func validated(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw LibraryError.emptyName }
        return trimmed
    }
}

public enum LibraryError: Error, Equatable, Sendable {
    case emptyName
    case missingFolder
    case missingBoard
    case missingElement
}

public struct Folder: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var boards: [Board]

    public init(id: UUID, name: String, boards: [Board]) {
        self.id = id
        self.name = name
        self.boards = boards
    }
}

public enum BoardStyle: String, Codable, Equatable, Sendable {
    case clean, sketch
}

public struct Board: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var style: BoardStyle
    public var elements: [BoardElement]

    public init(id: UUID, name: String, elements: [BoardElement], style: BoardStyle = .clean) {
        self.id = id
        self.name = name
        self.style = style
        self.elements = elements
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        style = try container.decodeIfPresent(BoardStyle.self, forKey: .style) ?? .clean
        elements = try container.decode([BoardElement].self, forKey: .elements)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(style, forKey: .style)
        try container.encode(elements, forKey: .elements)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, style, elements
    }
}

public enum BoardElement: Codable, Equatable, Identifiable, Sendable {
    case stroke(Stroke)
    case note(Note)
    case image(PlacedImage)
    case diagram(Diagram)

    public var id: UUID {
        switch self {
        case .stroke(let stroke): stroke.id
        case .note(let note): note.id
        case .image(let image): image.id
        case .diagram(let diagram): diagram.id
        }
    }

    public func moved(by delta: CGSize) -> BoardElement {
        switch self {
        case .stroke(var stroke):
            stroke.points = stroke.points.map {
                CGPoint(x: $0.x + delta.width, y: $0.y + delta.height)
            }
            return .stroke(stroke)
        case .note(var note):
            note.origin.x += delta.width
            note.origin.y += delta.height
            return .note(note)
        case .image(var image):
            image.origin.x += delta.width
            image.origin.y += delta.height
            return .image(image)
        case .diagram(var diagram):
            diagram.start.x += delta.width
            diagram.start.y += delta.height
            diagram.end.x += delta.width
            diagram.end.y += delta.height
            return .diagram(diagram)
        }
    }

    public var bounds: CGRect {
        switch self {
        case .stroke(let stroke):
            guard let first = stroke.points.first else { return .null }
            var rect = CGRect(origin: first, size: .zero)
            for point in stroke.points.dropFirst() {
                rect = rect.union(CGRect(origin: point, size: .zero))
            }
            return rect.insetBy(dx: -stroke.width, dy: -stroke.width)
        case .note(let note):
            return CGRect(x: note.origin.x, y: note.origin.y, width: note.width, height: Note.height)
        case .image(let image):
            return CGRect(x: image.origin.x, y: image.origin.y, width: image.width, height: image.height)
        case .diagram(let diagram):
            let rect = CGRect(
                x: min(diagram.start.x, diagram.end.x),
                y: min(diagram.start.y, diagram.end.y),
                width: abs(diagram.end.x - diagram.start.x),
                height: abs(diagram.end.y - diagram.start.y)
            )
            return diagram.kind == .arrow ? rect.insetBy(dx: -14, dy: -14) : rect
        }
    }
}

public enum DiagramKind: String, Codable, Equatable, Sendable {
    case rectangle, ellipse, diamond, arrow
}

public struct Diagram: Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: DiagramKind
    public var start: CGPoint
    public var end: CGPoint
    public var colorHex: String
    public var width: Double
    public var startBind: UUID?
    public var endBind: UUID?

    public init(
        id: UUID,
        kind: DiagramKind,
        start: CGPoint,
        end: CGPoint,
        colorHex: String,
        width: Double,
        startBind: UUID? = nil,
        endBind: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.colorHex = colorHex
        self.width = width
        self.startBind = startBind
        self.endBind = endBind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(DiagramKind.self, forKey: .kind)
        start = try container.decode(CGPoint.self, forKey: .start)
        end = try container.decode(CGPoint.self, forKey: .end)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        width = try container.decode(Double.self, forKey: .width)
        startBind = try container.decodeIfPresent(UUID.self, forKey: .startBind) ?? nil
        endBind = try container.decodeIfPresent(UUID.self, forKey: .endBind) ?? nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(width, forKey: .width)
        try container.encodeIfPresent(startBind, forKey: .startBind)
        try container.encodeIfPresent(endBind, forKey: .endBind)
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, start, end, colorHex, width, startBind, endBind
    }
}

public struct RoughCurve: Equatable, Sendable {
    public var start: CGPoint
    public var control: CGPoint
    public var end: CGPoint

    public init(start: CGPoint, control: CGPoint, end: CGPoint) {
        self.start = start
        self.control = control
        self.end = end
    }
}

public enum ResizeHandle: Equatable, Sendable {
    case start, end, topLeft, topRight, bottomLeft, bottomRight
}

extension Diagram {
    public func handles() -> [(ResizeHandle, CGPoint)] {
        if kind == .arrow {
            return [(.start, start), (.end, end)]
        }
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxX = max(start.x, end.x)
        let maxY = max(start.y, end.y)
        return [
            (.topLeft, CGPoint(x: minX, y: minY)),
            (.topRight, CGPoint(x: maxX, y: minY)),
            (.bottomLeft, CGPoint(x: minX, y: maxY)),
            (.bottomRight, CGPoint(x: maxX, y: maxY)),
        ]
    }

    public func resized(_ handle: ResizeHandle, to point: CGPoint) -> Diagram {
        var copy = self
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxX = max(start.x, end.x)
        let maxY = max(start.y, end.y)
        switch handle {
        case .start:
            copy.start = point
            copy.startBind = nil
        case .end:
            copy.end = point
            copy.endBind = nil
        case .topLeft:
            copy.start = point
            copy.end = CGPoint(x: maxX, y: maxY)
        case .bottomRight:
            copy.start = CGPoint(x: minX, y: minY)
            copy.end = point
        case .topRight:
            copy.start = CGPoint(x: minX, y: point.y)
            copy.end = CGPoint(x: point.x, y: maxY)
        case .bottomLeft:
            copy.start = CGPoint(x: point.x, y: minY)
            copy.end = CGPoint(x: maxX, y: point.y)
        }
        return copy
    }
}

public enum ConnectorRoute {
    public static func points(for diagram: Diagram, among elements: [BoardElement]) -> [CGPoint] {
        guard diagram.kind == .arrow else { return [diagram.start, diagram.end] }
        let startBox = diagram.startBind.flatMap { shape($0, in: elements, ignoring: diagram.id) }
        let endBox = diagram.endBind.flatMap { shape($0, in: elements, ignoring: diagram.id) }
        switch (startBox, endBox) {
        case let (start?, end?) where start.id != end.id:
            return elbow(from: start, to: end)
        case let (start?, nil):
            return [borderPoint(of: start, toward: diagram.end), diagram.end]
        case let (nil, end?):
            return [diagram.start, borderPoint(of: end, toward: diagram.start)]
        default:
            return [diagram.start, diagram.end]
        }
    }

    // ponytail: midpoint elbow, no obstacle avoidance. Upgrade path: route around overlapping boxes.
    private static func elbow(from start: ShapeBox, to end: ShapeBox) -> [CGPoint] {
        let startCenter = center(start.rect)
        let endCenter = center(end.rect)
        let leave = side(of: start.rect, toward: endCenter)
        let enter = side(of: end.rect, toward: startCenter)
        let startPoint = borderPoint(of: start, side: leave, align: endCenter)
        let endPoint = borderPoint(of: end, side: enter, align: startCenter)
        let leaveHorizontal = leave == .left || leave == .right
        let enterHorizontal = enter == .left || enter == .right
        let path: [CGPoint]
        if leaveHorizontal, enterHorizontal {
            let midX = (startPoint.x + endPoint.x) / 2
            path = [startPoint, CGPoint(x: midX, y: startPoint.y), CGPoint(x: midX, y: endPoint.y), endPoint]
        } else if !leaveHorizontal, !enterHorizontal {
            let midY = (startPoint.y + endPoint.y) / 2
            path = [startPoint, CGPoint(x: startPoint.x, y: midY), CGPoint(x: endPoint.x, y: midY), endPoint]
        } else if leaveHorizontal {
            path = [startPoint, CGPoint(x: endPoint.x, y: startPoint.y), endPoint]
        } else {
            path = [startPoint, CGPoint(x: startPoint.x, y: endPoint.y), endPoint]
        }
        return dedupe(path)
    }

    private static func borderPoint(of box: ShapeBox, toward point: CGPoint) -> CGPoint {
        borderPoint(of: box, side: side(of: box.rect, toward: point), align: point)
    }

    private static func borderPoint(of box: ShapeBox, side: Side, align: CGPoint) -> CGPoint {
        let rect = box.rect
        let onRect: CGPoint
        switch side {
        case .left:
            onRect = CGPoint(x: rect.minX, y: clamp(align.y, rect.minY, rect.maxY))
        case .right:
            onRect = CGPoint(x: rect.maxX, y: clamp(align.y, rect.minY, rect.maxY))
        case .top:
            onRect = CGPoint(x: clamp(align.x, rect.minX, rect.maxX), y: rect.minY)
        case .bottom:
            onRect = CGPoint(x: clamp(align.x, rect.minX, rect.maxX), y: rect.maxY)
        }
        return project(onRect, kind: box.kind, rect: rect)
    }

    private static func project(_ point: CGPoint, kind: DiagramKind, rect: CGRect) -> CGPoint {
        let center = center(rect)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let radiusX = max(rect.width / 2, 0.001)
        let radiusY = max(rect.height / 2, 0.001)
        switch kind {
        case .ellipse:
            let scale = 1 / max(sqrt((dx / radiusX) * (dx / radiusX) + (dy / radiusY) * (dy / radiusY)), 0.001)
            return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
        case .diamond:
            let scale = 1 / max(abs(dx) / radiusX + abs(dy) / radiusY, 0.001)
            return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
        case .rectangle, .arrow:
            return point
        }
    }

    private static func side(of rect: CGRect, toward point: CGPoint) -> Side {
        let origin = center(rect)
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        if abs(dx) >= abs(dy) { return dx >= 0 ? .right : .left }
        return dy >= 0 ? .bottom : .top
    }

    private static func boxRect(_ diagram: Diagram) -> CGRect {
        CGRect(
            x: min(diagram.start.x, diagram.end.x),
            y: min(diagram.start.y, diagram.end.y),
            width: abs(diagram.end.x - diagram.start.x),
            height: abs(diagram.end.y - diagram.start.y)
        )
    }

    private static func center(_ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(value, low), high)
    }

    private static func dedupe(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points {
            if let last = result.last, hypot(last.x - point.x, last.y - point.y) < 0.5 { continue }
            result.append(point)
        }
        return result.count >= 2 ? result : points
    }

    private static func shape(_ id: UUID, in elements: [BoardElement], ignoring: UUID) -> ShapeBox? {
        for element in elements {
            guard case .diagram(let diagram) = element, diagram.id == id, diagram.id != ignoring, diagram.kind != .arrow else { continue }
            return ShapeBox(id: diagram.id, kind: diagram.kind, rect: boxRect(diagram))
        }
        return nil
    }

    private struct ShapeBox {
        var id: UUID
        var kind: DiagramKind
        var rect: CGRect
    }

    private enum Side {
        case left, right, top, bottom
    }
}

public enum SketchLook {
    public static func seed(for id: UUID, salt: UInt64 = 0) -> UInt64 {
        let bytes = id.uuid
        let high = UInt64(bytes.0) << 56 | UInt64(bytes.1) << 48 | UInt64(bytes.2) << 40 | UInt64(bytes.3) << 32
            | UInt64(bytes.4) << 24 | UInt64(bytes.5) << 16 | UInt64(bytes.6) << 8 | UInt64(bytes.7)
        let low = UInt64(bytes.8) << 56 | UInt64(bytes.9) << 48 | UInt64(bytes.10) << 40 | UInt64(bytes.11) << 32
            | UInt64(bytes.12) << 24 | UInt64(bytes.13) << 16 | UInt64(bytes.14) << 8 | UInt64(bytes.15)
        return high ^ low &+ salt
    }

    public static func tiltDegrees(seed: UInt64) -> Double {
        sin(Double(seed % 10_000) * 0.001) * 2.2
    }

    public static func passes(points: [CGPoint], seed: UInt64, amount: CGFloat = 1.5) -> [[CGPoint]] {
        [
            offset(points, seed: seed, pass: 0, amount: amount),
            offset(points, seed: seed &+ 19, pass: 1, amount: amount * 0.75),
        ]
    }

    public static func roughEdges(kind: DiagramKind, from start: CGPoint, to end: CGPoint, seed: UInt64) -> [[RoughCurve]] {
        switch kind {
        case .rectangle:
            let minX = min(start.x, end.x)
            let minY = min(start.y, end.y)
            let maxX = max(start.x, end.x)
            let maxY = max(start.y, end.y)
            let corners = [
                CGPoint(x: minX, y: minY),
                CGPoint(x: maxX, y: minY),
                CGPoint(x: maxX, y: maxY),
                CGPoint(x: minX, y: maxY),
            ]
            return chain(corners, seed: seed)
        case .diamond:
            let midX = (start.x + end.x) / 2
            let midY = (start.y + end.y) / 2
            let corners = [
                CGPoint(x: midX, y: min(start.y, end.y)),
                CGPoint(x: max(start.x, end.x), y: midY),
                CGPoint(x: midX, y: max(start.y, end.y)),
                CGPoint(x: min(start.x, end.x), y: midY),
            ]
            return chain(corners, seed: seed &+ 5)
        case .ellipse:
            return ellipse(from: start, to: end, seed: seed)
        case .arrow:
            return roughChain([start, end], seed: seed)
        }
    }

    public static func roughChain(_ points: [CGPoint], seed: UInt64) -> [[RoughCurve]] {
        var pairs: [(CGPoint, CGPoint)] = []
        for index in points.indices.dropLast() {
            let start = points[index]
            let end = points[index + 1]
            if hypot(end.x - start.x, end.y - start.y) > 0.5 {
                pairs.append((start, end))
            }
        }
        var edges: [[RoughCurve]] = []
        for (index, pair) in pairs.enumerated() {
            edges.append(doubleLine(from: pair.0, to: pair.1, seed: seed &+ UInt64(index &* 17)))
            if index == pairs.count - 1 {
                edges.append(contentsOf: arrowHead(from: pair.0, to: pair.1, seed: seed &+ 11))
            }
        }
        return edges
    }

    private static func arrowHead(from start: CGPoint, to end: CGPoint, seed: UInt64) -> [[RoughCurve]] {
        let length = max(hypot(end.x - start.x, end.y - start.y), 1)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let head = min(26, max(14, length * 0.28))
        let spread = CGFloat.pi * 0.8
        let left = CGPoint(x: end.x + cos(angle + spread) * head, y: end.y + sin(angle + spread) * head)
        let right = CGPoint(x: end.x + cos(angle - spread) * head, y: end.y + sin(angle - spread) * head)
        return [
            doubleLine(from: end, to: left, seed: seed),
            doubleLine(from: end, to: right, seed: seed &+ 18),
        ]
    }

    public static func hachure(from start: CGPoint, to end: CGPoint, seed: UInt64, gap: CGFloat = 12) -> [RoughCurve] {
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxX = max(start.x, end.x)
        let maxY = max(start.y, end.y)
        guard maxX - minX > 8, maxY - minY > 8 else { return [] }
        var lines: [RoughCurve] = []
        var cursor = minX + minY
        let limit = maxX + maxY
        var salt: UInt64 = 0
        while cursor <= limit {
            if let span = clipDiagonal(sum: cursor, minX: minX, minY: minY, maxX: maxX, maxY: maxY),
               hypot(span.1.x - span.0.x, span.1.y - span.0.y) > 6 {
                lines.append(doubleLine(from: span.0, to: span.1, seed: seed &+ salt)[0])
            }
            cursor += gap
            salt += 3
        }
        return lines
    }

    private static func clipDiagonal(sum: CGFloat, minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) -> (CGPoint, CGPoint)? {
        var hits: [CGPoint] = []
        func add(_ point: CGPoint) {
            if hits.contains(where: { hypot($0.x - point.x, $0.y - point.y) < 0.5 }) { return }
            hits.append(point)
        }
        let yLeft = sum - minX
        if yLeft >= minY, yLeft <= maxY { add(CGPoint(x: minX, y: yLeft)) }
        let yRight = sum - maxX
        if yRight >= minY, yRight <= maxY { add(CGPoint(x: maxX, y: yRight)) }
        let xTop = sum - minY
        if xTop >= minX, xTop <= maxX { add(CGPoint(x: xTop, y: minY)) }
        let xBottom = sum - maxY
        if xBottom >= minX, xBottom <= maxX { add(CGPoint(x: xBottom, y: maxY)) }
        guard hits.count >= 2 else { return nil }
        return (hits[0], hits[1])
    }

    private static func offset(_ points: [CGPoint], seed: UInt64, pass: Int, amount: CGFloat) -> [CGPoint] {
        guard points.count > 1 else { return points }
        return points.enumerated().map { index, point in
            let previous = points[max(0, index - 1)]
            let next = points[min(points.count - 1, index + 1)]
            let dx = next.x - previous.x
            let dy = next.y - previous.y
            let length = max(hypot(dx, dy), 0.001)
            let wave = sin(Double(seed % 10_000) * 0.017 + Double(index) * 1.35 + Double(pass) * 2.1)
            let shift = CGFloat(wave) * amount
            return CGPoint(x: point.x + (-dy / length) * shift, y: point.y + (dx / length) * shift)
        }
    }

    private static func chain(_ corners: [CGPoint], seed: UInt64) -> [[RoughCurve]] {
        corners.enumerated().map { index, corner in
            let next = corners[(index + 1) % corners.count]
            return doubleLine(from: corner, to: next, seed: seed &+ UInt64(index &* 17))
        }
    }

    private static func ellipse(from start: CGPoint, to end: CGPoint, seed: UInt64) -> [[RoughCurve]] {
        let center = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let radiusX = max(abs(end.x - start.x) / 2, 1)
        let radiusY = max(abs(end.y - start.y) / 2, 1)
        let steps = 8
        return (0..<steps).map { index in
            let a0 = CGFloat(index) / CGFloat(steps) * .pi * 2
            let a1 = CGFloat(index + 1) / CGFloat(steps) * .pi * 2
            let p0 = CGPoint(x: center.x + cos(a0) * radiusX, y: center.y + sin(a0) * radiusY)
            let p1 = CGPoint(x: center.x + cos(a1) * radiusX, y: center.y + sin(a1) * radiusY)
            return doubleLine(from: p0, to: p1, seed: seed &+ UInt64(index &* 13))
        }
    }

    private static func doubleLine(from start: CGPoint, to end: CGPoint, seed: UInt64) -> [RoughCurve] {
        [curve(from: start, to: end, seed: seed, bowSign: 1), curve(from: start, to: end, seed: seed &+ 97, bowSign: -1)]
    }

    private static func curve(from start: CGPoint, to end: CGPoint, seed: UInt64, bowSign: CGFloat) -> RoughCurve {
        var rng = SplitMix(seed: seed)
        let length = max(hypot(end.x - start.x, end.y - start.y), 1)
        let dx = (end.x - start.x) / length
        let dy = (end.y - start.y) / length
        let nx = -dy
        let ny = dx
        let jitter = min(2.4, max(0.8, length * 0.02))
        let along = min(2.0, length * 0.04)
        let s = CGPoint(
            x: start.x + nx * rng.signed(jitter) - dx * rng.signed(along),
            y: start.y + ny * rng.signed(jitter) - dy * rng.signed(along)
        )
        let e = CGPoint(
            x: end.x + nx * rng.signed(jitter) + dx * rng.signed(along),
            y: end.y + ny * rng.signed(jitter) + dy * rng.signed(along)
        )
        let bow = bowSign * (0.7 + abs(rng.unit()) * 0.9) * min(length * 0.12, 12)
        let control = CGPoint(x: (s.x + e.x) / 2 + nx * bow, y: (s.y + e.y) / 2 + ny * bow)
        return RoughCurve(start: s, control: control, end: e)
    }
}

private struct SplitMix {
    var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func unit() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let bits = Double((state >> 11) & 0x1F_FFFF) / Double(0x1F_FFFF)
        return CGFloat(bits * 2 - 1)
    }

    mutating func signed(_ scale: CGFloat) -> CGFloat {
        unit() * scale
    }
}

public struct Stroke: Codable, Equatable, Sendable {
    public var id: UUID
    public var points: [CGPoint]
    public var colorHex: String
    public var width: Double

    public init(id: UUID, points: [CGPoint], colorHex: String, width: Double) {
        self.id = id
        self.points = points
        self.colorHex = colorHex
        self.width = width
    }
}

public struct Note: Codable, Equatable, Sendable {
    public static let height: Double = 120

    public var id: UUID
    public var origin: CGPoint
    public var text: String
    public var width: Double

    public init(id: UUID, origin: CGPoint, text: String, width: Double) {
        self.id = id
        self.origin = origin
        self.text = text
        self.width = width
    }
}

public struct PlacedImage: Codable, Equatable, Sendable {
    public var id: UUID
    public var origin: CGPoint
    public var width: Double
    public var height: Double
    public var fileName: String

    public init(id: UUID, origin: CGPoint, width: Double, height: Double, fileName: String) {
        self.id = id
        self.origin = origin
        self.width = width
        self.height = height
        self.fileName = fileName
    }
}

public enum HitTest {
    public static func element(at point: CGPoint, in elements: [BoardElement], slop: CGFloat = 6) -> UUID? {
        for element in elements.reversed() {
            switch element {
            case .stroke(let stroke):
                if hits(stroke.points, point: point, limit: max(stroke.width / 2, slop)) { return stroke.id }
            case .diagram(let diagram) where diagram.kind == .arrow:
                let route = ConnectorRoute.points(for: diagram, among: elements)
                if hits(route, point: point, limit: max(diagram.width / 2, slop + 10)) { return diagram.id }
            case .diagram:
                if element.bounds.insetBy(dx: -(slop + 8), dy: -(slop + 8)).contains(point) { return element.id }
            case .note, .image:
                if element.bounds.contains(point) { return element.id }
            }
        }
        return nil
    }

    private static func hits(_ points: [CGPoint], point: CGPoint, limit: CGFloat) -> Bool {
        guard let first = points.first else { return false }
        if points.count == 1 { return hypot(point.x - first.x, point.y - first.y) <= limit }
        for index in points.indices.dropFirst() {
            if distance(point, points[index - 1], points[index]) <= limit { return true }
        }
        return false
    }

    private static func distance(_ point: CGPoint, _ start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared == 0 { return hypot(point.x - start.x, point.y - start.y) }
        let t = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy))
    }
}

public struct Camera: Equatable, Sendable {
    public var offset: CGPoint
    public var scale: CGFloat

    public init(offset: CGPoint = .zero, scale: CGFloat = 1) {
        self.offset = offset
        self.scale = scale
    }

    public func worldPoint(fromScreen point: CGPoint, viewSize: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x - viewSize.width / 2) / scale + offset.x,
            y: (point.y - viewSize.height / 2) / scale + offset.y
        )
    }

    public func screenPoint(fromWorld point: CGPoint, viewSize: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x - offset.x) * scale + viewSize.width / 2,
            y: (point.y - offset.y) * scale + viewSize.height / 2
        )
    }

    public mutating func pan(screenDelta: CGSize) {
        offset.x -= screenDelta.width / scale
        offset.y -= screenDelta.height / scale
    }

    public mutating func zoom(by factor: CGFloat) {
        scale = min(4, max(0.2, scale * factor))
    }
}

public struct History<T: Equatable>: Equatable {
    public private(set) var present: T
    public let limit: Int
    private var undoStack: [T] = []
    private var redoStack: [T] = []

    public init(present: T, limit: Int = 50) {
        self.present = present
        self.limit = max(1, limit)
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public func undoValue() -> T? { undoStack.last }
    public var canRedo: Bool { !redoStack.isEmpty }

    public mutating func setPresent(_ value: T) {
        present = value
    }

    public mutating func commit(_ value: T) {
        guard value != present else { return }
        undoStack.append(present)
        trim(&undoStack)
        present = value
        redoStack.removeAll()
    }

    public mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(present)
        trim(&redoStack)
        present = previous
    }

    public mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(present)
        trim(&undoStack)
        present = next
    }

    public func retained() -> [T] {
        undoStack + [present] + redoStack
    }

    private func trim(_ stack: inout [T]) {
        while stack.count > limit { stack.removeFirst() }
    }
}

public enum ImageGC {
    public static func unreferenced(onDisk: [String], keeping: Set<String>) -> [String] {
        onDisk.filter { !keeping.contains($0) }
    }
}
