// LocationManager.swift – HARIVAS iOS
// Rider GPS background tracking

import Foundation
import CoreLocation

final class LocationManager: NSObject {

    static let shared = LocationManager()

    // MARK: - Private Properties

    private let clManager = CLLocationManager()
    private var currentOrderId: String = ""
    private var timer: Timer?
    private var lastLocation: CLLocation?
    private let minAccuracyMeters: Double = 50.0
    private let postIntervalSeconds: TimeInterval = 5.0
    private let endpointURL = URL(string: "https://gkgos.in/wp-json/harivas/v1/rider/location")!

    // MARK: - Init

    private override init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        clManager.distanceFilter = 5
        clManager.pausesLocationUpdatesAutomatically = false
        if #available(iOS 11.0, *) {
            clManager.showsBackgroundLocationIndicator = true
        }
    }

    // MARK: - Public API

    /// Called from JS bridge: window.HvNative.startLocationTracking(orderId)
    func startTracking(orderId: String) {
        currentOrderId = orderId
        let status = clManager.authorizationStatus

        switch status {
        case .notDetermined:
            clManager.requestAlwaysAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            beginUpdates()
        default:
            // Permission denied – silently fail
            break
        }
    }

    /// Called from JS bridge: window.HvNative.stopLocationTracking()
    func stopTracking() {
        timer?.invalidate()
        timer = nil
        clManager.stopUpdatingLocation()
        currentOrderId = ""
        lastLocation = nil
    }

    // MARK: - Private

    private func beginUpdates() {
        clManager.startUpdatingLocation()
        clManager.allowsBackgroundLocationUpdates = true

        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: postIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            self?.postLocation()
        }
    }

    private func postLocation() {
        guard let location = lastLocation else { return }

        // Filter poor accuracy
        guard location.horizontalAccuracy <= minAccuracyMeters,
              location.horizontalAccuracy > 0 else { return }

        let payload: [String: Any] = [
            "order_id": currentOrderId,
            "lat": location.coordinate.latitude,
            "lng": location.coordinate.longitude,
            "accuracy": location.horizontalAccuracy,
            "timestamp": ISO8601DateFormatter().string(from: location.timestamp)
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("[LocationManager] POST error: \(error.localizedDescription)")
            }
        }.resume()
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[LocationManager] Failed: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if !currentOrderId.isEmpty {
                beginUpdates()
            }
        default:
            stopTracking()
        }
    }
}
