import Foundation

extension FileManager {
    func createSecureDirectory(at url: URL) throws {
        try createDirectory(at: url, withIntermediateDirectories: true)
        try (url as NSURL).setResourceValue(
            URLFileProtection.completeUntilFirstUserAuthentication,
            forKey: .fileProtectionKey
        )
    }
    
    func createSecureFile(at url: URL, contents: Data? = nil) throws {
        if let data = contents {
            try data.write(to: url)
        } else {
            createFile(atPath: url.path, contents: nil)
        }
        try (url as NSURL).setResourceValue(
            URLFileProtection.completeUntilFirstUserAuthentication,
            forKey: .fileProtectionKey
        )
    }
    
    func securelyMoveItem(at srcURL: URL, to dstURL: URL) throws {
        try moveItem(at: srcURL, to: dstURL)
        try (dstURL as NSURL).setResourceValue(
            URLFileProtection.completeUntilFirstUserAuthentication,
            forKey: .fileProtectionKey
        )
    }
}
