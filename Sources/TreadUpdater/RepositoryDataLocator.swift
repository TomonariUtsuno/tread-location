import Foundation

enum RepositoryDataLocator {
    private static let bundledDataDirectory = "RepositoryData"

    /// Uses the working tree for development, then the app bundle for Finder launches.
    static func locate(
        startingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        bundleResourceURL: URL? = Bundle.main.resourceURL,
        fileManager: FileManager = .default
    ) -> URL? {
        var directory = startingDirectory.standardizedFileURL
        while directory.path != "/" {
            if isDataRoot(directory, fileManager: fileManager) {
                return directory
            }
            directory.deleteLastPathComponent()
        }

        guard let bundleResourceURL else { return nil }
        let bundledRoot = bundleResourceURL.appendingPathComponent(bundledDataDirectory, isDirectory: true)
        return isDataRoot(bundledRoot, fileManager: fileManager) ? bundledRoot : nil
    }

    static func isDataRoot(_ url: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: url.appendingPathComponent("wheels.json").path)
            && fileManager.fileExists(atPath: url.appendingPathComponent("wheels", isDirectory: true).path)
    }
}
