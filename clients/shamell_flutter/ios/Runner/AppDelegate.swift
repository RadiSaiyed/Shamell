import Flutter
import UIKit
import DeviceCheck

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "shamell/hardware_attestation",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "devicecheck_token":
          if #available(iOS 11.0, *) {
            let dev = DCDevice.current
            if !dev.isSupported {
              result(FlutterError(code: "unsupported", message: "DeviceCheck unsupported", details: nil))
              return
            }
            dev.generateToken { data, error in
              if let data = data {
                result(data.base64EncodedString())
                return
              }
              if let error = error {
                result(FlutterError(code: "unavailable", message: error.localizedDescription, details: nil))
                return
              }
              result(FlutterError(code: "unavailable", message: "DeviceCheck token unavailable", details: nil))
            }
          } else {
            result(FlutterError(code: "unsupported", message: "DeviceCheck requires iOS 11+", details: nil))
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
