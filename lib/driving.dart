import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MapPoint {
  const MapPoint(this.latitude, this.longitude);

  factory MapPoint.fromJson(Object? value) {
    final coordinates = value as List;
    return MapPoint(
      (coordinates[0] as num).toDouble(),
      (coordinates[1] as num).toDouble(),
    );
  }

  final double latitude;
  final double longitude;

  List<double> toJson() => [latitude, longitude];

  static double _longitudeDelta(double first, double second) =>
      (second - first + 540) % 360 - 180;

  double distanceTo(MapPoint other) {
    final x =
        _longitudeDelta(longitude, other.longitude) *
        math.cos((latitude + other.latitude) * math.pi / 360);
    final y = other.latitude - latitude;
    return math.sqrt(x * x + y * y) * 111195;
  }

  MapPoint towards(MapPoint other, double fraction) => MapPoint(
    latitude + (other.latitude - latitude) * fraction,
    (longitude + _longitudeDelta(longitude, other.longitude) * fraction + 540) %
            360 -
        180,
  );

  Uri get mapsLink => Uri.https('maps.apple.com', '/', {
    'll': '$latitude,$longitude',
    'q': 'Tour stop',
  });
}

class MapPlace {
  const MapPlace(this.name, this.point);

  factory MapPlace.fromJson(Object? value) {
    final fields = value as Map;
    return MapPlace(
      fields['name'] as String,
      MapPoint.fromJson(fields['point']),
    );
  }

  final String name;
  final MapPoint point;

  Map<String, Object> toJson() => {'name': name, 'point': point.toJson()};
}

class RoutePreference {
  const RoutePreference(this.name, this.distance);

  factory RoutePreference.fromJson(Object? value) {
    final data = value as Map;
    return RoutePreference(
      data['name'] as String,
      (data['distance'] as num).toDouble(),
    );
  }

  final String name;
  final double distance;

  Map<String, Object> toJson() => {'name': name, 'distance': distance};

  int match(List<DriveRoute> options) {
    var best = 0;
    var delta = double.infinity;
    for (final (index, route) in options.indexed) {
      if (route.name != name) continue;
      final difference = (route.distance - distance).abs();
      if (difference < delta) {
        best = index;
        delta = difference;
      }
    }
    return best;
  }
}

class DriveRoute {
  DriveRoute.fromJson(Object? value) {
    final row = value as Map;
    name = row['name'] as String;
    distance = (row['distance'] as num).toDouble();
    seconds = (row['time'] as num).toDouble();
    path = RoutePath((row['points'] as List).map(MapPoint.fromJson).toList());
    var last = 0.0;
    cues = [
      for (final step in row['steps'] as List)
        if ((step['points'] as List).isNotEmpty)
          (
            instruction: step['instruction'] as String,
            at: last = path
                .project(
                  MapPoint.fromJson((step['points'] as List).first),
                  after: last,
                )
                .along,
          ),
    ];
  }

  late final String name;
  late final double distance;
  late final double seconds;
  late final RoutePath path;
  late final List<({String instruction, double at})> cues;

  RoutePreference get preference => RoutePreference(name, distance);
}

class RoutePath {
  RoutePath(this.points) {
    for (var i = 1; i < points.length; i++) {
      _offsets.add(_offsets.last + points[i - 1].distanceTo(points[i]));
    }
  }

  final List<MapPoint> points;
  final _offsets = <double>[0];

  double get length => _offsets.last;

  ({MapPoint point, double along, double offset}) project(
    MapPoint fix, {
    double after = 0,
  }) {
    var best = (
      point: points.last,
      along: length,
      offset: fix.distanceTo(points.last),
    );
    for (var i = 1; i < points.length; i++) {
      if (_offsets[i] < after) continue;
      final a = points[i - 1];
      final b = points[i];
      final segment = _offsets[i] - _offsets[i - 1];
      if (segment < .01) continue;
      // Law of cosines gives the projection along this short road segment.
      final from = a.distanceTo(fix);
      final to = b.distanceTo(fix);
      final projected =
          (from * from + segment * segment - to * to) / (2 * segment);
      final minimum = math.max(0.0, after - _offsets[i - 1]);
      final alongSegment = projected.clamp(minimum, segment);
      final point = a.towards(b, alongSegment / segment);
      final offset = fix.distanceTo(point);
      if (offset < best.offset) {
        best = (
          point: point,
          along: _offsets[i - 1] + alongSegment,
          offset: offset,
        );
      }
    }
    return best;
  }

  MapPoint at(double distance) {
    for (var i = 1; i < points.length; i++) {
      if (_offsets[i] < distance || _offsets[i] <= _offsets[i - 1]) continue;
      return points[i - 1].towards(
        points[i],
        ((distance - _offsets[i - 1]) / (_offsets[i] - _offsets[i - 1])).clamp(
          0,
          1,
        ),
      );
    }
    return points.last;
  }

  List<MapPoint> remaining(double distance) => [
    at(distance),
    for (final (index, point) in points.indexed)
      if (_offsets[index] > distance) point,
  ];
}

typedef MapLine = ({List<MapPoint> points, String style});
typedef MapMarker = ({MapPlace place, String glyph, bool report});
typedef DriveLeg = ({DriveRoute route, MapPlace destination});

class AppleMap {
  AppleMap(this.channel);

  final MethodChannel channel;

  Future<MapPoint> position() async =>
      MapPoint.fromJson(await channel.invokeMethod<Object>('position'));

  Future<void> follow(bool enabled) =>
      channel.invokeMethod<void>('follow', {'enabled': enabled});

  Future<List<MapPlace>> search(String query) async =>
      (await channel.invokeListMethod<Object>('search', {'query': query}) ?? [])
          .map(MapPlace.fromJson)
          .toList();

  Future<List<DriveRoute>> route(
    MapPoint from,
    MapPoint to, {
    bool alternatives = false,
  }) async {
    final results = await channel.invokeListMethod<Object>('route', {
      'from': from.toJson(),
      'to': to.toJson(),
      'alternatives': alternatives,
    });
    final routes = (results ?? [])
        .where((result) => ((result as Map)['points'] as List).length >= 2)
        .map(DriveRoute.fromJson)
        .toList();
    if (routes.isEmpty) {
      throw PlatformException(
        code: 'directions_unavailable',
        message:
            'Apple Maps couldn’t find a driving route between these points.',
      );
    }
    return routes;
  }

  Future<Uint8List?> snapshot(
    List<List<MapPoint>> paths,
    List<MapPlace> stops,
  ) => channel.invokeMethod<Uint8List>('snapshot', {
    'paths': [
      for (final path in paths) path.map((point) => point.toJson()).toList(),
    ],
    'stops': [for (final stop in stops) stop.point.toJson()],
  });

  Future<void> draw({
    required List<MapMarker> pins,
    required List<MapLine> lines,
    bool fit = false,
  }) => channel.invokeMethod<void>('scene', {
    'pins': [
      for (final marker in pins)
        {
          ...marker.place.toJson(),
          'glyph': marker.glyph,
          'report': marker.report,
        },
    ],
    'lines': [
      for (final line in lines)
        {
          'points': line.points.map((point) => point.toJson()).toList(),
          'style': line.style,
        },
    ],
    'fit': fit,
  });
}

class DriveGuidance extends ChangeNotifier {
  DriveGuidance({required this.map, required this.legs, required this.tour})
    : assert(legs.isNotEmpty);

  final AppleMap map;
  final List<DriveLeg> legs;
  final bool tour;
  int _legIndex = 0;
  double _along = 0;
  double _connectorAlong = 0;
  double _rejoinAlong = 0;
  DriveRoute? _connector;
  var _offRouteFixes = 0;
  DateTime? _lastReroute;
  MapPoint? position;
  bool rerouting = false;
  bool arrived = false;
  bool weakSignal = false;
  bool _disposed = false;
  String? error;

  DriveLeg get currentLeg => legs[_legIndex];
  String get destination => legs.last.destination.name;
  bool get rejoining => _connector != null;
  int get stopsRemaining => legs.length - _legIndex;

  double _remainingFraction(DriveRoute route, double along) =>
      (1 - along / math.max(route.path.length, 1)).clamp(0.0, 1.0);

  ({double distance, double seconds}) get remaining {
    if (arrived) return (distance: 0, seconds: 0);
    final connector = _connector;
    final fraction = _remainingFraction(
      currentLeg.route,
      connector == null ? _along : _rejoinAlong,
    );
    var meters = currentLeg.route.distance * fraction;
    var seconds = currentLeg.route.seconds * fraction;
    if (connector != null) {
      final remaining = _remainingFraction(connector, _connectorAlong);
      meters += connector.distance * remaining;
      seconds += connector.seconds * remaining;
    }
    for (final leg in legs.skip(_legIndex + 1)) {
      meters += leg.route.distance;
      seconds += leg.route.seconds;
    }
    return (distance: meters, seconds: seconds);
  }

  ({String instruction, double distance}) get nextManeuver {
    final route = _connector ?? currentLeg.route;
    final along = _connector == null ? _along : _connectorAlong;
    for (final cue in route.cues) {
      if (cue.at > along + 12) {
        return (instruction: cue.instruction, distance: cue.at - along);
      }
    }
    return (
      instruction: rejoining && tour
          ? 'Continue to the tour route'
          : 'Continue to ${currentLeg.destination.name}',
      distance: math.max(0, route.path.length - along),
    );
  }

  List<MapLine> get lines => [
    if (!arrived) ...[
      if (_connector case final route?)
        (points: route.path.remaining(_connectorAlong), style: 'connector'),
      (
        points: currentLeg.route.path.remaining(
          _connector == null ? _along : _rejoinAlong,
        ),
        style: 'route',
      ),
      for (final leg in legs.skip(_legIndex + 1))
        (points: leg.route.path.points, style: 'route'),
    ],
  ];

  void update(MapPoint fix, double accuracy) {
    if (arrived || _disposed) return;
    if (accuracy < 0 || accuracy > 65) {
      if (!weakSignal) {
        weakSignal = true;
        notifyListeners();
      }
      return;
    }
    weakSignal = false;
    position = fix;
    final connector = _connector;
    final path = (connector ?? currentLeg.route).path;
    final progress = connector == null ? _along : _connectorAlong;
    final projection = path.project(fix, after: math.max(0, progress - 30));
    final onRoute = projection.offset < math.max(42, accuracy);
    final finishRadius = math.max(35.0, accuracy * .8);

    if (onRoute) {
      if (connector == null) {
        _along = math.max(_along, projection.along);
      } else {
        _connectorAlong = math.max(_connectorAlong, projection.along);
      }
    }

    if (fix.distanceTo(path.points.last) <= finishRadius &&
        path.length - (connector == null ? _along : _connectorAlong) < 120) {
      if (connector != null) {
        _connector = null;
        _along = _rejoinAlong;
      } else if (_legIndex == legs.length - 1) {
        arrived = true;
      } else {
        _legIndex++;
        _along = 0;
      }
      _offRouteFixes = 0;
      error = null;
      notifyListeners();
      return;
    }

    if (projection.offset > math.max(55, accuracy * 1.5)) {
      _offRouteFixes++;
      final time = DateTime.now();
      if (_offRouteFixes >= 2 &&
          !rerouting &&
          (_lastReroute == null ||
              time.difference(_lastReroute!).inSeconds >= 18)) {
        _lastReroute = time;
        _reroute(fix);
      }
    } else {
      _offRouteFixes = 0;
      error = null;
    }
    notifyListeners();
  }

  Future<void> _reroute(MapPoint fix) async {
    final index = _legIndex;
    final original = currentLeg.route.path;
    final forward = original.project(fix, after: _along).along;
    final distances = tour
        ? {
            forward,
            math.min(original.length, forward + 300),
            math.min(original.length, forward + 900),
          }
        : {original.length};
    rerouting = true;
    error = null;
    try {
      final options = await Future.wait([
        for (final along in distances)
          _returnOptions(fix, original.at(along), along),
      ]);
      if (_disposed || index != _legIndex || arrived) return;
      final followedPath = (_connector ?? currentLeg.route).path;
      final progress = _connector == null ? _along : _connectorAlong;
      if (followedPath
              .project(position ?? fix, after: math.max(0, progress - 30))
              .offset <
          42) {
        return;
      }
      final routes = options.expand((offers) => offers).toList()
        ..sort((a, b) => a.route.distance.compareTo(b.route.distance));
      if (routes.isEmpty) {
        error = tour
            ? 'Couldn’t rejoin the tour. Waiting to retry.'
            : 'Couldn’t reroute. Waiting to retry.';
        return;
      }
      _connector = routes.first.route;
      _connectorAlong = 0;
      _rejoinAlong = routes.first.along;
      _offRouteFixes = 0;
    } finally {
      rerouting = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<List<({DriveRoute route, double along})>> _returnOptions(
    MapPoint from,
    MapPoint to,
    double along,
  ) async {
    try {
      final routes = await map.route(from, to, alternatives: true);
      return [for (final route in routes) (route: route, along: along)];
    } on PlatformException {
      return [];
    } on MissingPluginException {
      return [];
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
