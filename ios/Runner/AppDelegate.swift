swift
    import UIKit
    import Flutter
    import GoogleMaps // <--- IMPORT THIS

    @UIApplicationMain
    @objc class AppDelegate: FlutterAppDelegate {
      override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
      ) -> Bool {
        // --- ADD THIS ---
        var googleApiKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_API_KEY") as? String
        if googleApiKey == nil || googleApiKey == "YOUR_GOOGLE_PLACES_API_KEY_HERE" {
            // Try to get it from environment variable if not in Info.plist (useful for CI/CD or build scripts)
            // This is a common pattern, but make sure it's actually set in your build environment.
            googleApiKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"]
        }

        if let key = googleApiKey, !key.isEmpty, key != "YOUR_GOOGLE_PLACES_API_KEY_HERE" {
            GMSServices.provideAPIKey(key)
        } else {
            print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
            print("ERROR: GOOGLE_API_KEY not found or is placeholder in AppDelegate.")
            print("Map functionality will be impaired.")
            print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
        }
        // --- END ADD ---

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
      }
    }
    