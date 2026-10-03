import Flutter
import UIKit

#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

#if canImport(AlarmKit)
@available(iOS 26.0, *)
private struct GardeFlowAlarmMetadata: AlarmMetadata {
  let body: String
  let payload: String
}
#endif

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var gardeFlowAlarmKitChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    installGardeFlowAlarmKitBridge()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func installGardeFlowAlarmKitBridge() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let channel = FlutterMethodChannel(
      name: "gardeflow/ios_alarmkit",
      binaryMessenger: controller.binaryMessenger
    )
    gardeFlowAlarmKitChannel = channel

    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleGardeFlowAlarmKitCall(call, result: result)
    }
  }

  private func unsupportedStatus() -> [String: Any] {
    return [
      "supported": false,
      "authorization": "unsupported",
      "engine": "legacy"
    ]
  }

  private func handleGardeFlowAlarmKitCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "status":
      #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        result(alarmKitStatus())
      } else {
        result(unsupportedStatus())
      }
      #else
      result(unsupportedStatus())
      #endif

    case "requestAuthorization":
      #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        Task { @MainActor in
          do {
            _ = try await AlarmManager.shared.requestAuthorization()
            result(self.alarmKitStatus())
          } catch {
            result(FlutterError(
              code: "ALARMKIT_AUTHORIZATION_FAILED",
              message: "Impossible d’autoriser les alarmes système Apple.",
              details: error.localizedDescription
            ))
          }
        }
      } else {
        result(unsupportedStatus())
      }
      #else
      result(unsupportedStatus())
      #endif

    case "schedule":
      #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        scheduleAppleAlarm(call: call, result: result)
      } else {
        result(false)
      }
      #else
      result(false)
      #endif

    case "cancel":
      #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        cancelAppleAlarm(call: call, result: result)
      } else {
        result(true)
      }
      #else
      result(true)
      #endif

    case "openSettings":
      guard let url = URL(string: UIApplication.openSettingsURLString) else {
        result(false)
        return
      }
      UIApplication.shared.open(url, options: [:]) { opened in
        result(opened)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  #if canImport(AlarmKit)
  @available(iOS 26.0, *)
  private func authorizationName(
    _ state: AlarmManager.AuthorizationState
  ) -> String {
    switch state {
    case .authorized:
      return "authorized"
    case .denied:
      return "denied"
    case .notDetermined:
      return "notDetermined"
    @unknown default:
      return "unknown"
    }
  }

  @available(iOS 26.0, *)
  private func alarmKitStatus() -> [String: Any] {
    let state = AlarmManager.shared.authorizationState
    return [
      "supported": true,
      "authorization": authorizationName(state),
      "engine": "AlarmKit"
    ]
  }

  @available(iOS 26.0, *)
  private func gardeFlowAlert(title: String) -> AlarmPresentation.Alert {
    let localizedTitle = LocalizedStringResource(stringLiteral: title)

    // iOS 26.1 simplified the templated alert initializer. Keep the original
    // iOS 26.0 API as a compatibility path so GardeFlow can use AlarmKit from
    // the first iOS 26 release rather than dropping back unnecessarily.
    if #available(iOS 26.1, *) {
      return AlarmPresentation.Alert(title: localizedTitle)
    }

    let stopButton = AlarmButton(
      text: "Arrêter",
      textColor: .white,
      systemImageName: "stop.circle.fill"
    )
    return AlarmPresentation.Alert(
      title: localizedTitle,
      stopButton: stopButton,
      secondaryButton: nil,
      secondaryButtonBehavior: nil
    )
  }

  @available(iOS 26.0, *)
  private func scheduleAppleAlarm(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard
      let args = call.arguments as? [String: Any],
      let rawId = args["uuid"] as? String,
      let id = UUID(uuidString: rawId),
      let triggerAtMillis = args["triggerAtMillis"] as? NSNumber,
      let title = args["title"] as? String
    else {
      result(FlutterError(
        code: "ALARMKIT_BAD_ARGUMENTS",
        message: "Paramètres d’alarme iOS incomplets.",
        details: nil
      ))
      return
    }

    let body = args["body"] as? String ?? ""
    let payload = args["payload"] as? String ?? ""
    let fireDate = Date(timeIntervalSince1970: triggerAtMillis.doubleValue / 1000.0)
    guard fireDate.timeIntervalSinceNow > 0.2 else {
      result(false)
      return
    }

    Task { @MainActor in
      guard AlarmManager.shared.authorizationState == .authorized else {
        result(false)
        return
      }

      do {
        let compactBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let composedTitle: String
        if compactBody.isEmpty {
          composedTitle = title
        } else {
          composedTitle = "\(title) · \(compactBody)"
        }
        let displayTitle = String(composedTitle.prefix(150))

        let alert = self.gardeFlowAlert(title: displayTitle)
        let presentation = AlarmPresentation(alert: alert)
        let attributes = AlarmAttributes<GardeFlowAlarmMetadata>(
          presentation: presentation,
          metadata: GardeFlowAlarmMetadata(body: body, payload: payload),
          tintColor: Color(red: 0.04, green: 0.66, blue: 0.39)
        )
        let configuration =
          AlarmManager.AlarmConfiguration<GardeFlowAlarmMetadata>.alarm(
            schedule: .fixed(fireDate),
            attributes: attributes,
            sound: .default
          )

        _ = try await AlarmManager.shared.schedule(
          id: id,
          configuration: configuration
        )
        result(true)
      } catch {
        result(FlutterError(
          code: "ALARMKIT_SCHEDULE_FAILED",
          message: "L’alarme système Apple n’a pas pu être programmée.",
          details: error.localizedDescription
        ))
      }
    }
  }

  @available(iOS 26.0, *)
  private func cancelAppleAlarm(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard
      let args = call.arguments as? [String: Any],
      let rawId = args["uuid"] as? String,
      let id = UUID(uuidString: rawId)
    else {
      result(false)
      return
    }

    do {
      if AlarmManager.shared.alarms.contains(where: { $0.id == id }) {
        try AlarmManager.shared.cancel(id: id)
      }
      result(true)
    } catch {
      result(FlutterError(
        code: "ALARMKIT_CANCEL_FAILED",
        message: "Impossible d’annuler l’alarme système Apple.",
        details: error.localizedDescription
      ))
    }
  }
  #endif
}
