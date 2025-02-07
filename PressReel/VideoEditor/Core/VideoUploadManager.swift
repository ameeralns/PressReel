import Foundation
import FirebaseStorage
import FirebaseAuth

class VideoUploadManager {
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 2.0
    
    func uploadVideo(at url: URL, to path: String, metadata: StorageMetadata? = nil) async throws -> URL {
        let secureURL = try await createSecureCopy(of: url)
        return try await withCheckedThrowingContinuation { continuation in
            uploadWithRetry(file: secureURL, to: path, metadata: metadata, retries: maxRetries) { result in
                switch result {
                case .success(let downloadURL):
                    continuation.resume(returning: downloadURL)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
                // Clean up temporary file
                try? FileManager.default.removeItem(at: secureURL)
            }
        }
    }
    
    private func createSecureCopy(of url: URL) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let secureDir = tempDir.appendingPathComponent(UUID().uuidString)
        let secureURL = secureDir.appendingPathComponent(url.lastPathComponent)
        
        try FileManager.default.createSecureDirectory(at: secureDir)
        try FileManager.default.copyItem(at: url, to: secureURL)
        try (secureURL as NSURL).setResourceValue(
            URLFileProtection.completeUntilFirstUserAuthentication,
            forKey: .fileProtectionKey
        )
        
        return secureURL
    }
    
    private func uploadWithRetry(file: URL, to path: String, metadata: StorageMetadata?, retries: Int, completion: @escaping (Result<URL, Error>) -> Void) {
        let storageRef = Storage.storage().reference().child(path)
        
        storageRef.putFile(from: file, metadata: metadata) { metadata, error in
            if let error = error {
                if retries > 0 {
                    print("🔄 [VideoUpload] Retrying upload. Attempts remaining: \(retries)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + self.retryDelay) {
                        self.uploadWithRetry(file: file, to: path, metadata: metadata, retries: retries - 1, completion: completion)
                    }
                } else {
                    completion(.failure(error))
                }
                return
            }
            
            storageRef.downloadURL { url, error in
                if let downloadURL = url {
                    completion(.success(downloadURL))
                } else {
                    completion(.failure(error ?? NSError(domain: "VideoUploadManager", code: -1)))
                }
            }
        }
    }
}
