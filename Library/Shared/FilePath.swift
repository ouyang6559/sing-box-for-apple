import Foundation

public enum FilePath {
    public static let packageName = AppConfiguration.packageName
    public static let groupName = AppConfiguration.appGroupID

    private static let defaultSharedDirectory: URL! = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupName)

    #if os(iOS)
        public static let sharedDirectory = defaultSharedDirectory!
    #elseif os(tvOS)
        public static let sharedDirectory = defaultSharedDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
    #elseif os(macOS)
        // Local-build fallback: without a provisioning profile the app-group
        // container is not writable, so fall back to Application Support.
        public static var sharedDirectory: URL! = {
            if let dir = defaultSharedDirectory,
               (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil {
                return dir
            }
            let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("sing-box-local", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback
        }()
    #endif

    #if os(iOS)
        public static let cacheDirectory = sharedDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
    #elseif os(tvOS)
        public static let cacheDirectory = sharedDirectory
    #elseif os(macOS)
        public static var cacheDirectory: URL {
            sharedDirectory
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true)
        }
    #endif

    #if os(macOS)
        public static var workingDirectory: URL {
            cacheDirectory.appendingPathComponent("Working", isDirectory: true)
        }
    #else
        public static let workingDirectory = cacheDirectory.appendingPathComponent("Working", isDirectory: true)

    #endif

    public static var iCloudDirectory = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents", isDirectory: true) ?? URL(string: "stub")!
}

public extension URL {
    var fileName: String {
        var path = relativePath
        if let index = path.lastIndex(of: "/") {
            path = String(path[path.index(index, offsetBy: 1)...])
        }
        return path
    }
}
