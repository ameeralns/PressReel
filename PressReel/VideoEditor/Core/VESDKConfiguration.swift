import Foundation
import VideoEditorSDK
import UIKit

enum VESDKConfiguration {
    static func initialize() {
        guard let license = Bundle.main.infoDictionary?["VESDK_LICENSE"] as? String else {
            print("⚠️ VESDK License not found in configuration")
            return
        }
        
        try? VESDK.unlockWithLicense(from: license)
    }
    
    static func defaultConfiguration() -> Configuration {
        Configuration { builder in
            builder.theme.backgroundColor = UIColor.black
        }
    }
}
