import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The Maps SDK for iOS key comes from the MAPS_API_KEY build setting
    // (ios/Flutter/MapsApiKey.xcconfig, git-ignored) through Info.plist's
    // GMSApiKey, so no key is committed. Release builds stop if that file
    // is missing; tool/check_firebase_config.mjs checks it is filled in.
    let mapsKey = (Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if mapsKey.isEmpty || mapsKey.hasPrefix("$(") {
      NSLog("TouchGrass: no Google Maps key. Set MAPS_API_KEY in ios/Flutter/MapsApiKey.xcconfig (PHASE_7A_RELEASE_RUNBOOK.md); the map will not load.")
    } else {
      GMSServices.provideAPIKey(mapsKey)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
