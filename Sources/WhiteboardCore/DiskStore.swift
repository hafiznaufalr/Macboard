import Foundation

public struct DiskStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var libraryURL: URL { root.appendingPathComponent("library.json") }

    public func imageURL(fileName: String) -> URL {
        imagesURL.appendingPathComponent(URL(fileURLWithPath: fileName).lastPathComponent)
    }

    public func load() throws -> Library? {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return nil }
        let data = try Data(contentsOf: libraryURL)
        return try JSONDecoder().decode(Library.self, from: data)
    }

    public func save(_ library: Library) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(library)
        try data.write(to: libraryURL, options: .atomic)
    }

    public func importImage(data: Data, fileExtension: String) throws -> String {
        try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        let ext = Self.safeExtension(fileExtension)
        let fileName = "\(UUID().uuidString).\(ext)"
        try data.write(to: imageURL(fileName: fileName), options: .atomic)
        return fileName
    }

    public func imageData(fileName: String) throws -> Data {
        try Data(contentsOf: imageURL(fileName: fileName))
    }

    public func purgeImages(keeping: Set<String>) throws {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: imagesURL.path) else { return }
        for name in ImageGC.unreferenced(onDisk: names, keeping: keeping) {
            try FileManager.default.removeItem(at: imagesURL.appendingPathComponent(name))
        }
    }

    private var imagesURL: URL { root.appendingPathComponent("images", isDirectory: true) }

    private static func safeExtension(_ raw: String) -> String {
        let letters = raw.lowercased().filter(\.isLetter)
        let allowed = ["png", "jpg", "jpeg", "gif", "tif", "tiff", "webp", "heic"]
        return allowed.contains(letters) ? letters : "png"
    }
}
