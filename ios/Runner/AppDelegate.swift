import ContactsUI
import CoreLocation
import Flutter
import MapKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var contactResult: FlutterResult?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PursuitAppleMap") {
      registrar.register(
        PursuitMapFactory(messenger: registrar.messenger()),
        withId: "pursuit/apple-map"
      )
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PursuitTours") {
      let data = FlutterMethodChannel(
        name: "pursuit/tours", binaryMessenger: registrar.messenger()
      )
      data.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "load":
          result(UserDefaults.standard.string(forKey: "savedTours"))
        case "save":
          UserDefaults.standard.set(call.arguments as? String, forKey: "savedTours")
          result(nil)
        case "share":
          guard let text = call.arguments as? String, let presenter = self?.visiblePresenter() else {
            result(FlutterError(code: "share_unavailable", message: "Couldn’t open the share sheet.",
                                details: nil))
            return
          }
          let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
          if let popover = sheet.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                        y: presenter.view.bounds.midY, width: 1, height: 1)
          }
          presenter.present(sheet, animated: true)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PursuitContacts") {
      let channel = FlutterMethodChannel(
        name: "pursuit/contacts",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "pickName", let self else {
          result(FlutterMethodNotImplemented)
          return
        }
        self.pickContact(result)
      }
    }
  }

  private func visiblePresenter() -> UIViewController? {
    let activeScene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    guard var presenter = activeScene?.keyWindow?.rootViewController else { return nil }
    while let presented = presenter.presentedViewController {
      presenter = presented
    }
    return presenter
  }

  private func pickContact(_ result: @escaping FlutterResult) {
    guard contactResult == nil, let presenter = visiblePresenter() else {
      result(FlutterError(code: "contacts_unavailable", message: nil, details: nil))
      return
    }
    let picker = CNContactPickerViewController()
    picker.delegate = self
    contactResult = result
    presenter.present(picker, animated: true)
  }

  private func finishPickingContact(_ name: String?) {
    let result = contactResult
    contactResult = nil
    result?(name)
  }
}

extension AppDelegate: CNContactPickerDelegate {
  func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
    finishPickingContact([contact.givenName, contact.familyName].joined(separator: " "))
  }

  func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
    finishPickingContact(nil)
  }
}

private final class PursuitMapFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let channel = FlutterMethodChannel(
      name: "pursuit/apple-map/\(viewId)",
      binaryMessenger: messenger
    )
    return PursuitMapView(frame: frame, channel: channel)
  }
}

private final class PursuitMapView: NSObject, FlutterPlatformView,
  CLLocationManagerDelegate, MKMapViewDelegate {
  private let map: MKMapView
  private let channel: FlutterMethodChannel
  private let location = CLLocationManager()
  private var locationResult: FlutterResult?
  private var waitingForAuthorization = false
  private var centerOnLocation = false
  private var following = false
  private var requests: [UUID: MKDirections] = [:]

  init(frame: CGRect, channel: FlutterMethodChannel) {
    map = MKMapView(frame: frame)
    self.channel = channel
    super.init()

    map.overrideUserInterfaceStyle = .dark
    if #available(iOS 16.0, *) {
      map.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
      map.selectableMapFeatures = [.pointsOfInterest, .physicalFeatures]
    } else {
      map.mapType = .mutedStandard
    }
    map.setRegion(MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: 46.574, longitude: 11.671),
      latitudinalMeters: 13_000, longitudinalMeters: 13_000
    ), animated: false)
    map.delegate = self
    map.addGestureRecognizer(UILongPressGestureRecognizer(
      target: self, action: #selector(dropPin(_:))
    ))
    location.delegate = self
    location.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    location.distanceFilter = 5
    location.activityType = .automotiveNavigation
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  deinit {
    for request in requests.values { request.cancel() }
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView { map }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "locate", "position":
      guard locationResult == nil else {
        result(failure("location_in_progress", "A location request is already running."))
        return
      }
      centerOnLocation = call.method == "locate"
      locationResult = result
      requestLocation()
    case "follow":
      following = args["enabled"] as? Bool ?? false
      if following {
        location.startUpdatingLocation()
        if let fix = location.location {
          map.setRegion(MKCoordinateRegion(
            center: fix.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000
          ), animated: true)
        }
        map.setUserTrackingMode(.follow, animated: true)
      } else {
        location.stopUpdatingLocation()
        map.setUserTrackingMode(.none, animated: true)
      }
      result(nil)
    case "route":
      guard let from = coordinate(args["from"]), let to = coordinate(args["to"]) else {
        result(failure("invalid_place", "The route needs two valid map locations."))
        return
      }
      directions(from: from, to: to, alternatives: args["alternatives"] as? Bool ?? false,
                 result: result)
    case "search":
      guard let query = args["query"] as? String, !query.isEmpty else {
        result([])
        return
      }
      let request = MKLocalSearch.Request()
      request.naturalLanguageQuery = query
      request.region = map.region
      MKLocalSearch(request: request).start { [weak self] response, _ in
        guard let self else { return }
        result(response?.mapItems.prefix(6).map { item in
          self.place(item.name ?? query, at: item.placemark.coordinate)
        } ?? [])
      }
    case "snapshot":
      snapshotRoute(args, result: result)
    case "scene":
      drawScene(args)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @objc private func dropPin(_ gesture: UILongPressGestureRecognizer) {
    guard gesture.state == .began, !following else { return }
    let point = map.convert(gesture.location(in: map), toCoordinateFrom: map)
    channel.invokeMethod("placeSelected", arguments: place("Dropped pin", at: point))
  }

  func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
    guard !following, !(annotation is MKUserLocation) else { return }
    let title = (annotation.title ?? nil) ?? "Map location"
    channel.invokeMethod("placeSelected", arguments: place(title, at: annotation.coordinate))
    mapView.deselectAnnotation(annotation, animated: false)
  }

  func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
    guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
    let renderer = MKPolylineRenderer(polyline: line)
    renderer.lineJoin = .round
    renderer.lineCap = .round
    switch line.title {
    case "alternative":
      renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.7)
      renderer.lineWidth = 4
    case "connector":
      renderer.strokeColor = .systemCyan
      renderer.lineWidth = 6
    default:
      renderer.strokeColor = UIColor(red: 0.86, green: 1.0, blue: 0.27, alpha: 1.0)
      renderer.lineWidth = 6
    }
    return renderer
  }

  func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
    guard let pin = annotation as? PursuitPin else { return nil }
    let marker = mapView.dequeueReusableAnnotationView(withIdentifier: "pin")
      as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: pin, reuseIdentifier: "pin")
    marker.annotation = pin
    marker.markerTintColor = pin.report ? .systemOrange : UIColor(
      red: 0.86, green: 1.0, blue: 0.27, alpha: 1.0
    )
    marker.glyphTintColor = .black
    marker.glyphText = pin.glyph
    return marker
  }

  private func drawScene(_ args: [String: Any]) {
    map.removeAnnotations(map.annotations.compactMap { $0 as? PursuitPin })
    map.removeOverlays(map.overlays)
    var bounds = MKMapRect.null
    for item in args["pins"] as? [[String: Any]] ?? [] {
      guard let point = coordinate(item["point"]) else { continue }
      let pin = PursuitPin()
      pin.coordinate = point
      pin.title = item["name"] as? String
      pin.glyph = item["glyph"] as? String
      pin.report = item["report"] as? Bool ?? false
      map.addAnnotation(pin)
      let mapPoint = MKMapPoint(point)
      if !pin.report {
        bounds = bounds.union(MKMapRect(x: mapPoint.x, y: mapPoint.y, width: 1, height: 1))
      }
    }
    for item in args["lines"] as? [[String: Any]] ?? [] {
      let points = (item["points"] as? [[Double]] ?? []).compactMap { coordinate($0) }
      guard points.count > 1 else { continue }
      let line = MKPolyline(coordinates: points, count: points.count)
      line.title = item["style"] as? String
      bounds = bounds.union(line.boundingMapRect)
      map.addOverlay(line, level: .aboveRoads)
    }
    if args["fit"] as? Bool == true, !bounds.isNull, !following {
      let inset = max(0, 1400 - min(bounds.width, bounds.height)) / 2
      let bottom = map.bounds.height * 0.48
      let top = min(105, map.bounds.height * 0.21)
      map.setVisibleMapRect(
        bounds.insetBy(dx: -inset, dy: -inset),
        edgePadding: UIEdgeInsets(top: top, left: 35, bottom: bottom, right: 35),
        animated: true
      )
    }
  }

  private func snapshotRoute(_ args: [String: Any], result: @escaping FlutterResult) {
    let paths = (args["paths"] as? [[[Double]]] ?? []).map { path in
      path.compactMap { coordinate($0) }
    }.filter { $0.count > 1 }
    let stops = (args["stops"] as? [[Double]] ?? []).compactMap { coordinate($0) }
    guard !paths.isEmpty else {
      result(nil)
      return
    }

    var bounds = MKMapRect.null
    for point in paths.flatMap({ $0 }) + stops {
      let projected = MKMapPoint(point)
      bounds = bounds.union(MKMapRect(x: projected.x, y: projected.y, width: 1, height: 1))
    }
    let options = MKMapSnapshotter.Options()
    options.size = CGSize(width: 540, height: 180)
    options.traitCollection = UITraitCollection(traitsFrom: [
      UITraitCollection(userInterfaceStyle: .dark),
      UITraitCollection(displayScale: 1.5)
    ])
    if #available(iOS 17.0, *) {
      options.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
    } else {
      options.mapType = .mutedStandard
    }
    let height = max(bounds.height * 1.32, bounds.width * 1.18 / 3, 500)
    let width = height * 3
    options.mapRect = MKMapRect(
      x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height
    )

    let snapshotter = MKMapSnapshotter(options: options)
    snapshotter.start { [snapshotter] snapshot, _ in
      withExtendedLifetime(snapshotter) {
        guard let snapshot else {
          result(nil)
          return
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.image.scale
        let image = UIGraphicsImageRenderer(size: snapshot.image.size, format: format).image { context in
          snapshot.image.draw(at: .zero)
          let pen = context.cgContext
          let green = UIColor(red: 0.86, green: 1.0, blue: 0.27, alpha: 1.0)
          pen.setLineJoin(.round)
          pen.setLineCap(.round)
          for path in paths {
            let line = CGMutablePath()
            line.addLines(between: path.map { snapshot.point(for: $0) })
            pen.addPath(line)
            pen.setStrokeColor(UIColor.black.withAlphaComponent(0.7).cgColor)
            pen.setLineWidth(6)
            pen.strokePath()
            pen.addPath(line)
            pen.setStrokeColor(green.cgColor)
            pen.setLineWidth(3.5)
            pen.strokePath()
          }
          for stop in stops {
            let point = snapshot.point(for: stop)
            let pin = CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9)
            pen.setFillColor(green.cgColor)
            pen.fillEllipse(in: pin)
            pen.setLineWidth(1.5)
            pen.setStrokeColor(UIColor.black.cgColor)
            pen.strokeEllipse(in: pin)
          }
        }
        result(image.pngData().map { FlutterStandardTypedData(bytes: $0) })
      }
    }
  }

  private func directions(
    from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, alternatives: Bool,
    result: @escaping FlutterResult
  ) {
    let request = MKDirections.Request()
    request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
    request.transportType = .automobile
    request.requestsAlternateRoutes = alternatives
    let directions = MKDirections(request: request)
    let id = UUID()
    requests[id] = directions
    directions.calculate { [weak self] response, error in
      guard let self else { return }
      self.requests.removeValue(forKey: id)
      guard let routes = response?.routes, !routes.isEmpty else {
        result(self.failure("directions_unavailable",
          error?.localizedDescription ?? "Apple Maps could not find a driving route."))
        return
      }
      result(routes.map { route in
        [
          "name": route.name,
          "distance": route.distance,
          "time": route.expectedTravelTime,
          "points": self.points(route.polyline),
          "steps": route.steps.filter { !$0.instructions.isEmpty }.map { step in
            [
              "instruction": step.instructions,
              "distance": step.distance,
              "points": self.points(step.polyline)
            ] as [String: Any]
          }
        ] as [String: Any]
      })
    }
  }

  private func points(_ line: MKPolyline) -> [[Double]] {
    (0..<line.pointCount).map { index in
      let coordinate = line.points()[index].coordinate
      return [coordinate.latitude, coordinate.longitude]
    }
  }

  private func coordinate(_ value: Any?) -> CLLocationCoordinate2D? {
    guard let values = value as? [Double], values.count == 2 else { return nil }
    let point = CLLocationCoordinate2D(latitude: values[0], longitude: values[1])
    return CLLocationCoordinate2DIsValid(point) ? point : nil
  }

  private func place(_ name: String, at coordinate: CLLocationCoordinate2D) -> [String: Any] {
    ["name": name, "point": [coordinate.latitude, coordinate.longitude]]
  }

  private func failure(_ code: String, _ message: String) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }

  private func requestLocation() {
    switch location.authorizationStatus {
    case .notDetermined:
      waitingForAuthorization = true
      location.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      map.showsUserLocation = true
      location.requestLocation()
    case .restricted, .denied:
      finishLocation(failure("location_denied", "Allow location access in iOS Settings to get directions."))
    @unknown default:
      finishLocation(failure("location_unavailable", "Location is unavailable."))
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard waitingForAuthorization, manager.authorizationStatus != .notDetermined else { return }
    waitingForAuthorization = false
    requestLocation()
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let current = locations.last, current.horizontalAccuracy >= 0 else {
      if locationResult != nil {
        finishLocation(failure("location_unavailable", "Couldn’t find your location. Try again."))
      }
      return
    }
    if following {
      channel.invokeMethod("positionChanged", arguments: [
        "point": [current.coordinate.latitude, current.coordinate.longitude],
        "accuracy": current.horizontalAccuracy
      ])
    }
    if locationResult != nil {
      if centerOnLocation {
        if following {
          map.setUserTrackingMode(.follow, animated: true)
        } else {
          map.setRegion(MKCoordinateRegion(
            center: current.coordinate, latitudinalMeters: 2_000, longitudinalMeters: 2_000
          ), animated: true)
        }
      }
      finishLocation(centerOnLocation ? nil : [current.coordinate.latitude, current.coordinate.longitude])
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    if locationResult != nil {
      finishLocation(failure("location_unavailable", "Couldn’t find your location. Try again."))
    }
  }

  private func finishLocation(_ value: Any?) {
    let result = locationResult
    locationResult = nil
    result?(value)
  }
}

private final class PursuitPin: MKPointAnnotation {
  var glyph: String?
  var report = false
}
