import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'driving.dart';
import 'pursuit_ui.dart';

enum TourCategory {
  saved('Saved'),
  past('Past'),
  shared('Shared with you');

  const TourCategory(this.label);
  final String label;
}

enum TourActivity { created, edited, shared }

class TourStop {
  TourStop(this.name, [this.point]);

  factory TourStop.fromPlace(MapPlace place) =>
      TourStop(place.name, place.point);

  final String name;
  final MapPoint? point;
}

class Tour {
  Tour._({
    required this.name,
    required this.region,
    required this.category,
    required this.stops,
    this.id,
    this.preferences = const [],
    this.sharedBy,
    this._activity,
  });

  final String name;
  final String region;
  final TourCategory category;
  final List<TourStop> stops;
  final String? id;
  final List<RoutePreference?> preferences;
  final String? sharedBy;
  TourActivity? _activity;

  String? get activityLabel => switch (_activity) {
    TourActivity.created => 'Created',
    TourActivity.edited => 'Edited',
    TourActivity.shared => sharedBy == null ? 'Shared' : 'Shared by $sharedBy',
    null => null,
  };

  bool get isLoop => stops.length > 2 && stops.first.name == stops.last.name;

  String get description => [
    if (region.isNotEmpty) region,
    '${stops.length} ${stops.length == 1 ? 'stop' : 'stops'}',
  ].join(' · ');

  String get endpoints => isLoop
      ? 'Loop from ${stops.first.name}'
      : stops.length == 1
      ? stops.first.name
      : '${stops.first.name} → ${stops.last.name}';
}

class TourLibrary extends ChangeNotifier {
  TourLibrary.demo()
    : _tours = [
        Tour._(
          id: 'dolomites',
          name: 'Dolomites Loop',
          region: 'Italian Dolomites',
          category: TourCategory.saved,
          activity: TourActivity.edited,
          stops: [
            TourStop('Ortisei'),
            TourStop('Passo Gardena'),
            TourStop('Corvara in Badia'),
            TourStop('Passo Campolongo'),
            TourStop('Ortisei'),
          ],
        ),
        Tour._(
          name: 'Garda Lakeside',
          region: 'Lake Garda',
          category: TourCategory.past,
          stops: [
            TourStop('Riva del Garda'),
            TourStop('Malcesine'),
            TourStop('Bardolino'),
          ],
        ),
      ] {
    receiveShared(
      name: 'Sella Pass Run',
      region: 'Italian Dolomites',
      sender: 'Maya',
      stops: ['Canazei', 'Passo Sella', 'Selva di Val Gardena'],
    );
  }

  final List<Tour> _tours;

  Iterable<Tour> select(TourCategory? category) => _tours.where(
    (tour) =>
        category == null ? tour._activity != null : tour.category == category,
  );

  Iterable<Tour> get all => _tours;

  static const _storage = MethodChannel('pursuit/tours');
  bool _disposed = false;

  Future<void> restore() async {
    try {
      final payload = await _storage.invokeMethod<String>('load');
      if (payload == null || _disposed) return;
      final saved = [
        for (final item in jsonDecode(payload) as List)
          Tour._(
            id: item['id'] as String,
            name: item['name'] as String,
            region: item['region'] as String,
            category: TourCategory.saved,
            stops: (item['places'] as List)
                .map(MapPlace.fromJson)
                .map(TourStop.fromPlace)
                .toList(),
            preferences: (item['preferences'] as List)
                .map(
                  (choice) =>
                      choice == null ? null : RoutePreference.fromJson(choice),
                )
                .toList(),
            activity: item['edited'] == true
                ? TourActivity.edited
                : TourActivity.created,
          ),
      ].where((tour) => tour.stops.length >= 2).toList();
      _tours.removeWhere((tour) => saved.any((saved) => saved.id == tour.id));
      _tours.insertAll(0, saved);
      notifyListeners();
    } on MissingPluginException {
      // The local store is provided by the iOS runner.
    } on PlatformException {
      // The demo library remains available if the store can't be read.
    } on FormatException {
      // Leave the demo library available if stored data can't be decoded.
    } on TypeError {
      // A previous schema may contain missing or incompatible fields.
    }
  }

  Future<Tour> saveDraft({
    Tour? existing,
    required String name,
    required List<MapPlace> places,
    required List<RoutePreference?> preferences,
  }) async {
    final tour = Tour._(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      region: existing?.region ?? '',
      category: TourCategory.saved,
      stops: places.map(TourStop.fromPlace).toList(),
      preferences: List.of(preferences),
      activity: existing == null ? TourActivity.created : TourActivity.edited,
    );
    final updated = [tour, ..._tours.where((item) => item != existing)];
    final saved = [
      for (final item in updated)
        if (item.id != null && item.stops.every((stop) => stop.point != null))
          {
            'id': item.id,
            'name': item.name,
            'region': item.region,
            'places': [
              for (final stop in item.stops)
                MapPlace(stop.name, stop.point!).toJson(),
            ],
            'preferences': item.preferences
                .map((choice) => choice?.toJson())
                .toList(),
            'edited': item._activity == TourActivity.edited,
          },
    ];
    try {
      await _storage.invokeMethod<void>('save', jsonEncode(saved));
    } on MissingPluginException {
      // Non-iOS previews keep the library in memory.
    }
    if (!_disposed) {
      _tours
        ..clear()
        ..addAll(updated);
      notifyListeners();
    }
    return tour;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void receiveShared({
    required String name,
    required String region,
    required String sender,
    required List<String> stops,
  }) {
    if (stops.isEmpty) return;
    _recordActivity(
      Tour._(
        name: name,
        region: region,
        category: TourCategory.shared,
        sharedBy: sender,
        stops: stops.map(TourStop.new).toList(),
      ),
      TourActivity.shared,
    );
  }

  void _recordActivity(Tour tour, TourActivity activity) {
    tour._activity = activity;
    _tours.remove(tour);
    _tours.insert(0, tour);
    notifyListeners();
  }
}

class TourMapLoader {
  TourMapLoader(this.map);

  final AppleMap map;
  final _loads = <Tour, Future<TourMapData>>{};

  Future<TourMapData> load(Tour tour) async {
    final request = _loads.putIfAbsent(tour, () => _load(tour));
    try {
      final data = await request;
      if (!data.complete && identical(_loads[tour], request)) {
        _loads.remove(tour);
      }
      return data;
    } catch (_) {
      if (identical(_loads[tour], request)) _loads.remove(tour);
      rethrow;
    }
  }

  Future<TourMapData> _load(Tour tour) async {
    final places = <MapPlace>[];
    final missing = <String>[];
    final resolved = <String, MapPoint>{};
    for (final stop in tour.stops) {
      var point = stop.point ?? resolved[stop.name];
      point ??= (await map.search('${stop.name}, Italy')).firstOrNull?.point;
      if (point == null) {
        missing.add(stop.name);
      } else {
        resolved[stop.name] = point;
        places.add(MapPlace(stop.name, point));
      }
    }
    final routes = <List<DriveRoute>>[];
    if (missing.isEmpty) {
      for (var index = 1; index < places.length; index++) {
        final start = places[index - 1].point;
        final end = places[index].point;
        try {
          routes.add(
            start.distanceTo(end) < 8
                ? []
                : await map.route(start, end, alternatives: true),
          );
        } on PlatformException {
          routes.add([]);
        }
      }
    }
    return TourMapData(places, routes, missing);
  }
}

class TourMapData {
  const TourMapData(this.places, this.routes, this.missing);

  final List<MapPlace> places;
  final List<List<DriveRoute>> routes;
  final List<String> missing;

  bool get complete =>
      places.length >= 2 &&
      missing.isEmpty &&
      routes.length == places.length - 1 &&
      routes.every((options) => options.isNotEmpty);

  List<List<MapPoint>> pathsFor(Tour tour) => [
    for (final (index, options) in routes.indexed)
      if (options.isNotEmpty)
        options[index < tour.preferences.length
                ? tour.preferences[index]?.match(options) ?? 0
                : 0]
            .path
            .points,
  ];
}

typedef TourMenuSelection = ({Tour? tour});

Future<TourMenuSelection?> showTourMenu(
  BuildContext context,
  TourLibrary library,
  TourMapLoader? loader,
) => showModalBottomSheet<TourMenuSelection>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 640),
  backgroundColor: canvasColor,
  barrierColor: const Color(0x4d000000),
  sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : null,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .61,
    minChildSize: .33,
    maxChildSize: .94,
    builder: (context, controller) =>
        _TourMenu(library: library, controller: controller, loader: loader),
  ),
);

class _TourMenu extends StatefulWidget {
  const _TourMenu({
    required this.library,
    required this.controller,
    required this.loader,
  });

  final TourLibrary library;
  final ScrollController controller;
  final TourMapLoader? loader;

  @override
  State<_TourMenu> createState() => _TourMenuState();
}

class _TourMenuState extends State<_TourMenu> {
  Future<void> _previewQueue = Future.value();

  Future<Uint8List?> _preview(Tour tour) {
    final loader = widget.loader;
    if (loader == null) return Future.value();
    final preview = _previewQueue.then((_) async {
      if (!mounted) return null;
      try {
        final data = await loader.load(tour);
        if (!mounted || !data.complete) return null;
        return await loader.map.snapshot(data.pathsFor(tour), data.places);
      } on PlatformException {
        return null;
      } on MissingPluginException {
        return null;
      }
    });
    _previewQueue = preview.then<void>((_) {});
    return preview;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final tours = widget.library.all.toList();
      return ListView(
        controller: widget.controller,
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          18 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Text(
            'Tours',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pop<TourMenuSelection>(context, (tour: null)),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add tour'),
          ),
          const SizedBox(height: 14),
          if (tours.isEmpty) const Text('No tours here yet.'),
          for (final tour in tours)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              key: ObjectKey(tour),
              child: _TourCard(
                tour: tour,
                loadPreview: () => _preview(tour),
                onTap: () =>
                    Navigator.pop<TourMenuSelection>(context, (tour: tour)),
              ),
            ),
        ],
      );
    },
  );
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.tour,
    required this.onTap,
    required this.loadPreview,
  });

  final Tour tour;
  final VoidCallback onTap;
  final Future<Uint8List?> Function() loadPreview;

  @override
  Widget build(BuildContext context) => PursuitCard(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(aspectRatio: 3, child: _RoutePreview(load: loadPreview)),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 12),
          child: Row(
            spacing: 10,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    if (tour.activityLabel case final activity?)
                      Text(
                        activity,
                        style: const TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Text(
                      tour.name,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      tour.endpoints,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: secondaryText),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RoutePreview extends StatefulWidget {
  const _RoutePreview({required this.load});

  final Future<Uint8List?> Function() load;

  @override
  State<_RoutePreview> createState() => _RoutePreviewState();
}

class _RoutePreviewState extends State<_RoutePreview> {
  late final Future<Uint8List?> _preview = widget.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _preview,
    builder: (context, snapshot) {
      if (snapshot.data case final image?) {
        return Semantics(
          image: true,
          label: 'Apple Maps driving route',
          child: Image.memory(
            image,
            fit: BoxFit.cover,
            alignment: Alignment.bottomCenter,
          ),
        );
      }
      return ColoredBox(
        color: canvasColor,
        child: Center(
          child: Text(
            snapshot.connectionState == ConnectionState.done
                ? 'Map preview unavailable'
                : 'Loading route preview…',
            style: const TextStyle(color: secondaryText),
          ),
        ),
      );
    },
  );
}
