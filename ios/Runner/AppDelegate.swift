import UIKit
import Flutter
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

      let googleApiKey = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsApiKey") as? String ?? ""

    if googleApiKey.isEmpty || googleApiKey == "YOUR_ACTUAL_API_KEY_HERE" || googleApiKey == "YOUR_GOOGLE_PLACES_API_KEY_HERE" {
        print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
        print("ERROR: AppDelegate.swift - Google API Key is a placeholder or empty.")
        print("Map functionality will be severely impaired or non-functional.")
        print("Please replace 'YOUR_ACTUAL_API_KEY_HERE' with your valid Google API Key.")
        print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
    }

    // Provide the API key to Google Maps Services
    GMSServices.provideAPIKey(googleApiKey)

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
