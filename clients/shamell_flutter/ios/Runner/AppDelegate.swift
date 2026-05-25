import Flutter
import UIKit
import DeviceCheck
import Darwin
import MachO

private enum ReleaseRuntimeHardening {
  private static let suspiciousDyldNeedles = [
    "frida",
    "substrate",
    "substitute",
    "libhooker",
    "ellekit",
    "cycript",
  ]
  private static let suspiciousPaths = [
    "/Applications/Cydia.app",
    "/Library/MobileSubstrate/MobileSubstrate.dylib",
    "/bin/bash",
    "/usr/sbin/sshd",
    "/etc/apt",
    "/private/var/lib/apt",
    "/private/var/jb",
    "/var/jb",
  ]

  static func compromiseSignals() -> [String] {
    #if DEBUG
      return []
    #else
      var signals = Set<String>()
      if isDebuggerAttached() {
        signals.insert("debugger")
      }
      if getenv("DYLD_INSERT_LIBRARIES") != nil {
        signals.insert("dyld_insert_libraries")
      }
      if hasSuspiciousDyldImages() {
        signals.insert("suspicious_dylib")
      }
      if hasJailbreakArtifacts() {
        signals.insert("jailbreak_artifact")
      }
      return Array(signals).sorted()
    #endif
  }

  private static func isDebuggerAttached() -> Bool {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    let status = mib.withUnsafeMutableBufferPointer { mibPtr in
      sysctl(mibPtr.baseAddress, u_int(mibPtr.count), &info, &size, nil, 0)
    }
    if status != 0 {
      return false
    }
    return (info.kp_proc.p_flag & P_TRACED) != 0
  }

  private static func hasSuspiciousDyldImages() -> Bool {
    let count = _dyld_image_count()
    for idx in 0..<count {
      guard let rawName = _dyld_get_image_name(idx) else {
        continue
      }
      let imageName = String(cString: rawName).lowercased()
      if suspiciousDyldNeedles.contains(where: { imageName.contains($0) }) {
        return true
      }
    }
    return false
  }

  private static func hasJailbreakArtifacts() -> Bool {
    let fm = FileManager.default
    return suspiciousPaths.contains(where: { fm.fileExists(atPath: $0) })
  }

  static func blockedViewController(signals: [String]) -> UIViewController {
    let controller = UIViewController()
    controller.view.backgroundColor = UIColor(
      red: 4.0 / 255.0,
      green: 7.0 / 255.0,
      blue: 12.0 / 255.0,
      alpha: 1.0
    )

    let title = UILabel()
    title.translatesAutoresizingMaskIntoConstraints = false
    title.text = "Shamell blocked this session."
    title.textColor = .white
    title.font = .systemFont(ofSize: 24, weight: .semibold)
    title.numberOfLines = 0
    title.textAlignment = .center

    let body = UILabel()
    body.translatesAutoresizingMaskIntoConstraints = false
    body.text =
      "The runtime failed device integrity checks. Restart on a non-compromised device or without active instrumentation."
    body.textColor = UIColor(white: 0.82, alpha: 1.0)
    body.font = .systemFont(ofSize: 16, weight: .regular)
    body.numberOfLines = 0
    body.textAlignment = .center

    let detail = UILabel()
    detail.translatesAutoresizingMaskIntoConstraints = false
    detail.text = signals.joined(separator: ", ")
    detail.textColor = UIColor(white: 0.64, alpha: 1.0)
    detail.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    detail.numberOfLines = 0
    detail.textAlignment = .center

    let stack = UIStackView(arrangedSubviews: [title, body, detail])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical
    stack.spacing = 16
    controller.view.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor),
      stack.leadingAnchor.constraint(
        greaterThanOrEqualTo: controller.view.leadingAnchor,
        constant: 24
      ),
      stack.trailingAnchor.constraint(
        lessThanOrEqualTo: controller.view.trailingAnchor,
        constant: -24
      ),
      stack.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
      stack.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
    ])

    return controller
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var privacyShieldView: UIView?
  private var didBecomeActiveObserver: NSObjectProtocol?
  private var willResignActiveObserver: NSObjectProtocol?
  private var screenCaptureObserver: NSObjectProtocol?

  private func currentCompromiseSignals() -> [String] {
    ReleaseRuntimeHardening.compromiseSignals()
  }

  private func enforceReleaseRuntimeIntegrity() {
    #if DEBUG
      return
    #else
      let signals = currentCompromiseSignals()
      guard !signals.isEmpty else {
        return
      }
      let blocked = ReleaseRuntimeHardening.blockedViewController(signals: signals)
      if let window {
        window.rootViewController = blocked
        window.makeKeyAndVisible()
      } else {
        let blockedWindow = UIWindow(frame: UIScreen.main.bounds)
        blockedWindow.rootViewController = blocked
        blockedWindow.makeKeyAndVisible()
        self.window = blockedWindow
      }
    #endif
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let compromiseSignals = currentCompromiseSignals()
    if !compromiseSignals.isEmpty {
      let blockedWindow = UIWindow(frame: UIScreen.main.bounds)
      blockedWindow.rootViewController = ReleaseRuntimeHardening.blockedViewController(
        signals: compromiseSignals
      )
      blockedWindow.makeKeyAndVisible()
      window = blockedWindow
      return true
    }

    GeneratedPluginRegistrant.register(with: self)
    installReleasePrivacyShieldObservers()
    updateReleasePrivacyShield()

    if let registrar = registrar(forPlugin: "ShamellHardwareAttestation") {
      let channel = FlutterMethodChannel(
        name: "shamell/hardware_attestation",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "runtime_compromise_state":
          let signals = self.currentCompromiseSignals()
          result([
            "compromised": !signals.isEmpty,
            "signals": signals,
          ])
        case "devicecheck_token":
          let signals = self.currentCompromiseSignals()
          if !signals.isEmpty {
            result(
              FlutterError(
                code: "compromised_runtime",
                message: "Runtime integrity check failed",
                details: signals
              )
            )
            return
          }
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

  deinit {
    let center = NotificationCenter.default
    if let didBecomeActiveObserver {
      center.removeObserver(didBecomeActiveObserver)
    }
    if let willResignActiveObserver {
      center.removeObserver(willResignActiveObserver)
    }
    if let screenCaptureObserver {
      center.removeObserver(screenCaptureObserver)
    }
  }

  private func installReleasePrivacyShieldObservers() {
    #if DEBUG
      return
    #else
      guard didBecomeActiveObserver == nil, willResignActiveObserver == nil else {
        return
      }
      let center = NotificationCenter.default
      willResignActiveObserver = center.addObserver(
        forName: UIApplication.willResignActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.updateReleasePrivacyShield(forceVisible: true)
      }
      didBecomeActiveObserver = center.addObserver(
        forName: UIApplication.didBecomeActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.enforceReleaseRuntimeIntegrity()
        self?.updateReleasePrivacyShield()
      }
      if #available(iOS 11.0, *) {
        screenCaptureObserver = center.addObserver(
          forName: UIScreen.capturedDidChangeNotification,
          object: UIScreen.main,
          queue: .main
        ) { [weak self] _ in
          self?.updateReleasePrivacyShield()
        }
      }
    #endif
  }

  private func updateReleasePrivacyShield(forceVisible: Bool = false) {
    #if DEBUG
      return
    #else
      guard let window else {
        return
      }
      let shouldShow = forceVisible || isScreenCaptureActive()
      if shouldShow {
        let shield = releasePrivacyShieldView(for: window)
        shield.frame = window.bounds
        shield.isHidden = false
        window.bringSubviewToFront(shield)
      } else {
        privacyShieldView?.isHidden = true
      }
    #endif
  }

  private func isScreenCaptureActive() -> Bool {
    if #available(iOS 11.0, *) {
      return UIScreen.main.isCaptured
    }
    return false
  }

  private func releasePrivacyShieldView(for window: UIWindow) -> UIView {
    if let privacyShieldView {
      if privacyShieldView.superview !== window {
        window.addSubview(privacyShieldView)
      }
      return privacyShieldView
    }

    let shield = UIView(frame: window.bounds)
    shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    shield.backgroundColor = UIColor(
      red: 4.0 / 255.0,
      green: 7.0 / 255.0,
      blue: 12.0 / 255.0,
      alpha: 1.0
    )
    shield.isUserInteractionEnabled = false

    let title = UILabel()
    title.translatesAutoresizingMaskIntoConstraints = false
    title.text = "Shamell protected this screen."
    title.textColor = .white
    title.font = .systemFont(ofSize: 24, weight: .semibold)
    title.numberOfLines = 0
    title.textAlignment = .center

    let body = UILabel()
    body.translatesAutoresizingMaskIntoConstraints = false
    body.text =
      "Sensitive content is hidden while the app is inactive or an active screen capture session is detected."
    body.textColor = UIColor(white: 0.82, alpha: 1.0)
    body.font = .systemFont(ofSize: 16, weight: .regular)
    body.numberOfLines = 0
    body.textAlignment = .center

    let stack = UIStackView(arrangedSubviews: [title, body])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical
    stack.spacing = 16
    shield.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.centerYAnchor.constraint(equalTo: shield.centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: shield.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: shield.trailingAnchor, constant: -24),
      stack.centerXAnchor.constraint(equalTo: shield.centerXAnchor),
      stack.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
    ])

    window.addSubview(shield)
    privacyShieldView = shield
    return shield
  }
}
