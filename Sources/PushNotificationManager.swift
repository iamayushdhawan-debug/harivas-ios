// PushNotificationManager.swift – HARIVAS iOS
// APNs + FCM token registration with HARIVAS backend

import Foundation
import UIKit
import FirebaseMessaging

final class PushNotificationManager: NSObject {

    static let shared = PushNotificationManager()

    // MARK: - Constants

    private let apnsEndpoint = URL(string: "https://gkgos.in/wp-json/harivas/v1/push/register-ios")!

    // MARK: - Init

    private override init() {
        super.init()
    }

    // MARK: - APNS Token

    func registerAPNSToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        print("[APNs] Device token: \(token)")
        postToken(apnsToken: token, fcmToken: nil)
    }

    // MARK: - FCM Token

    func registerFCMToken(_ token: String) {
        print("[FCM] Registration token: \(token)")
        postToken(apnsToken: nil, fcmToken: token)
    }

    // MARK: - Private

    private func postToken(apnsToken: String?, fcmToken: String?) {
        var payload: [String: Any] = [
            "platform": "ios",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "bundle_id": Bundle.main.bundleIdentifier ?? "",
            "device_id": UIDevice.current.identifierForVendor?.uuidString ?? "",
            "device_name": UIDevice.current.name
        ]

        if let apns = apnsToken { payload["apns_token"] = apns }
        if let fcm = fcmToken  { payload["fcm_token"] = fcm }

        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: apnsEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("[PushNotificationManager] Registration error: \(error.localizedDescription)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                print("[PushNotificationManager] Registered with status: \(httpResponse.statusCode)")
            }
        }.resume()
    }
}
