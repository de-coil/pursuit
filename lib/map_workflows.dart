part of 'map_home.dart';

enum _MapPhase { home, place, tour, editor, drive }

typedef _LegKey = (MapPoint, MapPoint);

mixin _MapWorkflows on State<MapHome> {
  final _stops = <MapPlace>[];
  final _routes = <_LegKey, List<DriveRoute>>{};
  final _requested = <_LegKey, Future<List<DriveRoute>>>{};
  final _preferences = <_LegKey, RoutePreference>{};
  final _reports = <MapPlace>[];
  MethodChannel? _mapChannel;
  AppleMap? _appleMap;
  TourMapLoader? _tourMaps;
  _MapPhase _phase = _MapPhase.home;
  MapPlace? _place;
  Tour? _tour;
  DriveRoute? _pointRoute;
  DriveGuidance? _guidance;
  String? _error;
  bool _working = false;
  bool _saving = false;
  int _generation = 0;
  int? _highlightedLeg;
  MapPoint? _drawnFix;
  (int, bool, bool, bool)? _drawnDriveState;

  void _attachMap(MethodChannel channel) {
    channel.setMethodCallHandler(_mapEvent);
    setState(() {
      _mapChannel = channel;
      _appleMap = AppleMap(channel);
      _tourMaps = TourMapLoader(_appleMap!);
    });
  }

  Future<void> _mapEvent(MethodCall event) async {
    if (!mounted) return;
    switch (event.method) {
      case 'placeSelected':
        final place = MapPlace.fromJson(event.arguments);
        if (_reports.any(
          (report) =>
              report.point.distanceTo(place.point) < 3 &&
              report.name == place.name,
        )) {
          _notify(place.name);
          return;
        }
        if (_phase == _MapPhase.editor) {
          if (!_saving && _highlightedLeg == null) _addStop(place);
        } else if (_phase == _MapPhase.home || _phase == _MapPhase.place) {
          _showPlace(place);
        }
      case 'positionChanged':
        final fix = event.arguments as Map;
        _guidance?.update(
          MapPoint.fromJson(fix['point']),
          (fix['accuracy'] as num).toDouble(),
        );
    }
  }

  @override
  void dispose() {
    _generation++;
    _mapChannel?.setMethodCallHandler(null);
    _guidance?.dispose();
    super.dispose();
  }

  bool _current(int ticket) => mounted && ticket == _generation;

  String _message(Object error) => switch (error) {
    PlatformException(:final message?) => message,
    MissingPluginException() =>
      'Live maps and directions are available on iOS.',
    _ => 'The map couldn’t complete that request. Try again.',
  };

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.sizeOf(context).height * .51,
          ),
        ),
      );
  }

  Future<void> _openTourMenu() async {
    final selection = await showTourMenu(context, widget.tours, _tourMaps);
    if (!mounted || selection == null) return;
    if (selection.tour case final tour?) {
      await _openTour(tour);
    } else {
      _startEditor();
    }
  }

  void _closeWorkspace() {
    if (_saving) return;
    if (_highlightedLeg case final leg?) {
      _chooseLeg(leg);
      return;
    }
    final guidance = _guidance;
    if (guidance != null) {
      _appleMap?.follow(false).catchError((Object _) {});
      guidance.dispose();
    }
    _generation++;
    _requested.clear();
    setState(() {
      _guidance = null;
      _phase = _MapPhase.home;
      _working = false;
      _error = null;
      _stops.clear();
      _routes.clear();
      _preferences.clear();
      _tour = null;
      _place = null;
      _pointRoute = null;
      _highlightedLeg = null;
      _drawnFix = null;
      _drawnDriveState = null;
    });
    _draw();
  }

  void _showPlace(MapPlace place) {
    _generation++;
    setState(() {
      _phase = _MapPhase.place;
      _place = place;
      _pointRoute = null;
      _working = false;
      _error = null;
    });
    _draw();
  }

  List<_LegKey> get _legs => [
    for (var index = 1; index < _stops.length; index++)
      (_stops[index - 1].point, _stops[index].point),
  ];

  DriveRoute? _routeFor(_LegKey leg) {
    final routes = _routes[leg];
    if (routes == null || routes.isEmpty) return null;
    return routes[_preferences[leg]?.match(routes) ?? 0];
  }

  List<MapLine> get _lines {
    if (_guidance case final guidance?) return guidance.lines;
    if (_pointRoute case final route?) {
      return [(points: route.path.points, style: 'route')];
    }
    final legs = _legs;
    final alternate = _highlightedLeg;
    return [
      if (alternate != null && alternate < legs.length)
        for (final route in _routes[legs[alternate]] ?? <DriveRoute>[])
          if (route != _routeFor(legs[alternate]))
            (points: route.path.points, style: 'alternative'),
      for (final leg in legs)
        if (_routeFor(leg) case final route?)
          (points: route.path.points, style: 'route'),
    ];
  }

  void _draw({bool fit = false}) {
    final map = _appleMap;
    if (map == null) return;
    map
        .draw(
          pins: [
            if (_place case final place?)
              (place: place, glyph: '', report: false),
            for (final (index, stop) in _stops.indexed)
              (place: stop, glyph: '${index + 1}', report: false),
            for (final report in _reports)
              (place: report, glyph: '!', report: true),
          ],
          lines: _lines,
          fit: fit,
        )
        .catchError((Object _) {});
  }

  Future<void> _openTour(Tour tour) async {
    final ticket = ++_generation;
    setState(() {
      _phase = _MapPhase.tour;
      _tour = tour;
      _stops.clear();
      _routes.clear();
      _preferences.clear();
      _highlightedLeg = null;
      _working = true;
      _error = null;
    });
    final loader = _tourMaps;
    if (loader == null) {
      setState(() {
        _error = 'The live route is available on iOS.';
        _working = false;
      });
      return;
    }
    try {
      final data = await loader.load(tour);
      if (!_current(ticket)) return;
      setState(() {
        _stops.addAll(data.places);
        for (final (index, options) in data.routes.indexed) {
          final leg = (data.places[index].point, data.places[index + 1].point);
          if (options.isNotEmpty) _routes[leg] = options;
          if (index < tour.preferences.length &&
              tour.preferences[index] != null) {
            _preferences[leg] = tour.preferences[index]!;
          }
        }
        if (data.missing.isNotEmpty) {
          _error = 'Couldn’t locate ${data.missing.join(', ')}.';
        } else if (!data.complete) {
          _error = 'Driving directions are unavailable for one or more legs.';
        }
      });
      _draw(fit: true);
    } on PlatformException catch (error) {
      if (_current(ticket)) setState(() => _error = _message(error));
    } on MissingPluginException catch (error) {
      if (_current(ticket)) setState(() => _error = _message(error));
    } finally {
      if (_current(ticket)) setState(() => _working = false);
    }
  }

  void _startEditor({bool edit = false}) {
    _generation++;
    setState(() {
      _phase = _MapPhase.editor;
      _working = false;
      _error = null;
      _highlightedLeg = null;
      if (!edit) {
        _tour = null;
        _stops.clear();
        _routes.clear();
        _preferences.clear();
      }
    });
    _draw();
  }

  void _addStop(MapPlace selection) {
    if (_stops.length >= 20) {
      _notify('A tour can have up to 20 stops.');
      return;
    }
    if (_stops.lastOrNull?.point.distanceTo(selection.point)
        case final distance? when distance < 8) {
      _notify('Choose a different location for the next stop.');
      return;
    }
    final place = selection.name == 'Dropped pin'
        ? MapPlace('Stop ${_stops.length + 1}', selection.point)
        : selection;
    setState(() => _stops.add(place));
    _stopsChanged();
  }

  void _moveStop(int from, int to) {
    if (_saving || from == to) return;
    setState(() => _stops.insert(to, _stops.removeAt(from)));
    _stopsChanged();
  }

  void _stopsChanged() {
    _highlightedLeg = null;
    _draw();
    _buildRoutes();
  }

  Future<void> _buildRoutes({bool fit = false}) async {
    final map = _appleMap;
    if (map == null) return;
    final ticket = ++_generation;
    final legs = _legs;
    setState(() {
      _working = legs.isNotEmpty;
      _error = null;
    });
    var failed = false;
    for (final leg in legs) {
      if (!_current(ticket)) return;
      if (_routes.containsKey(leg)) continue;
      if (leg.$1.distanceTo(leg.$2) < 8) {
        failed = true;
        continue;
      }
      final future = _requested.putIfAbsent(
        leg,
        () => map.route(leg.$1, leg.$2, alternatives: true),
      );
      try {
        final found = await future;
        if (_current(ticket)) _routes[leg] = found;
      } on PlatformException {
        failed = true;
      } on MissingPluginException {
        failed = true;
      } finally {
        if (identical(_requested[leg], future)) _requested.remove(leg);
      }
      if (!_current(ticket)) return;
    }
    if (!_current(ticket)) return;
    setState(() {
      _working = false;
      if (failed) {
        _error = 'Driving directions are unavailable for one or more legs.';
      }
    });
    _draw(fit: fit);
  }

  Future<void> _findPlace() async {
    final map = _appleMap;
    if (map == null) {
      _notify('Place search is available on iOS.');
      return;
    }
    final place = await showDialog<MapPlace>(
      context: context,
      builder: (_) => _PlaceSearch(map),
    );
    if (!mounted || place == null || _phase != _MapPhase.editor) return;
    _addStop(place);
    _draw(fit: true);
  }

  Future<void> _routeToPlace() async {
    final map = _appleMap;
    final place = _place;
    if (map == null || place == null || _working) return;
    final ticket = ++_generation;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final origin = await map.position();
      if (!_current(ticket)) return;
      if (origin.distanceTo(place.point) < 30) {
        setState(() => _error = 'You’re already here.');
        return;
      }
      final options = await map.route(origin, place.point);
      if (!_current(ticket)) return;
      setState(() => _pointRoute = options.first);
      _draw(fit: true);
    } on PlatformException catch (error) {
      if (_current(ticket)) setState(() => _error = _message(error));
    } on MissingPluginException catch (error) {
      if (_current(ticket)) setState(() => _error = _message(error));
    } finally {
      if (_current(ticket)) setState(() => _working = false);
    }
  }

  Future<void> _startDrive() async {
    final map = _appleMap;
    if (map == null || _working) return;
    final ticket = ++_generation;
    final isTour = _phase == _MapPhase.tour;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final origin = await map.position();
      if (!_current(ticket)) return;
      final destinations = isTour ? _stops.toList() : [_place!];
      final legs = <DriveLeg>[];
      final first = destinations.first;
      if (origin.distanceTo(first.point) >= 35) {
        final preview = _pointRoute;
        final approach =
            preview != null && origin.distanceTo(preview.path.points.first) < 80
            ? preview
            : (await map.route(origin, first.point)).first;
        if (!_current(ticket)) return;
        legs.add((route: approach, destination: first));
      }
      if (isTour) {
        for (final (index, leg) in _legs.indexed) {
          legs.add((
            route: _routeFor(leg)!,
            destination: destinations[index + 1],
          ));
        }
      }
      if (legs.isEmpty) {
        setState(() => _error = 'You’re already here.');
        return;
      }
      final guidance = DriveGuidance(map: map, legs: legs, tour: isTour)
        ..position = origin;
      guidance.addListener(_guidanceChanged);
      setState(() {
        _guidance = guidance;
        _phase = _MapPhase.drive;
      });
      _draw();
      await map.follow(true);
    } on PlatformException catch (error) {
      if (_current(ticket)) setState(() => _error = _message(error));
    } on MissingPluginException catch (error) {
      if (_current(ticket)) setState(() => _error = _message(error));
    } finally {
      if (_current(ticket)) setState(() => _working = false);
    }
  }

  void _guidanceChanged() {
    final guidance = _guidance;
    if (!mounted || guidance == null) return;
    if (guidance.arrived) {
      _appleMap?.follow(false).catchError((Object _) {});
    }
    setState(() {});
    final state = (
      guidance.stopsRemaining,
      guidance.rejoining,
      guidance.arrived,
      guidance.rerouting,
    );
    final fix = guidance.position;
    if (_drawnDriveState != state ||
        (fix != null &&
            (_drawnFix?.distanceTo(fix) ?? double.infinity) >= 25)) {
      _drawnFix = fix;
      _drawnDriveState = state;
      _draw();
    }
  }

  Future<void> _report() async {
    final fix = _guidance?.position;
    if (fix == null) return;
    final type = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Report a road event'),
        children: [
          for (final label in [
            'Hazard',
            'Roadworks',
            'Traffic',
            'Custom event',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, label),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(label),
              ),
            ),
        ],
      ),
    );
    if (!mounted || type == null) return;
    final note = type == 'Custom event'
        ? await askForText(context, 'Custom event', 'What happened?')
        : type;
    if (!mounted || note == null || note.isEmpty) return;
    _reports.add(MapPlace(note, fix));
    _draw();
    _notify('Road event marked on this device.');
  }

  void _chooseLeg(int index) {
    final leg = _legs[index];
    final routes = _routes[leg];
    if (routes == null) return;
    setState(() => _highlightedLeg = _highlightedLeg == index ? null : index);
    _draw();
  }

  Future<void> _saveTour() async {
    if (_saving || _working || _stops.length < 2) return;
    final result = await showDialog<({String name, bool share})>(
      context: context,
      builder: (_) => _SaveTourDialog(_tour?.name ?? ''),
    );
    if (!mounted || result == null || _phase != _MapPhase.editor) return;
    setState(() => _saving = true);
    try {
      final tour = await widget.tours.saveDraft(
        existing: _tour,
        name: result.name,
        places: _stops.toList(),
        preferences: [for (final leg in _legs) _routeFor(leg)?.preference],
      );
      if (!mounted) return;
      setState(() {
        _tour = tour;
        _phase = _MapPhase.tour;
        _highlightedLeg = null;
      });
      _draw(fit: true);
      if (result.share) {
        await _shareTour();
      } else {
        _notify('Tour saved.');
      }
    } on PlatformException catch (error) {
      if (mounted) _notify(_message(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _placeLink(MapPlace place) => '${place.name}: ${place.point.mapsLink}';

  Future<void> _shareTour() {
    final lines = <String>[];
    final legs = _legs;
    for (final (index, stop) in _stops.indexed) {
      lines.add('${index + 1}. ${_placeLink(stop)}');
      if (index < legs.length) {
        final road = _routeFor(legs[index])?.name;
        if (road != null && road.isNotEmpty) lines.add('   Via $road');
      }
    }
    return _share(_tour!.name, lines.join('\n'));
  }

  Future<void> _share(String title, String itinerary) async {
    final crew = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Share with which crew?'),
        children: [
          for (final name in widget.crew.crewNames)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, name),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(name),
              ),
            ),
        ],
      ),
    );
    if (!mounted || crew == null) return;
    final text = '$title\n$itinerary';
    widget.crew.shareWithCrew(crew, title, text);
    try {
      await const MethodChannel('pursuit/tours')
          .invokeMethod<void>('share', '$crew\n$text');
      if (mounted) _notify('Added to $crew on this device.');
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) _notify('Added to $crew on this device.');
    } on PlatformException catch (error) {
      if (mounted) _notify(_message(error));
    }
  }

  String _distance(double meters) {
    if (widget.miles) {
      return meters < 160
          ? '${(meters * 3.28084).round()} ft'
          : '${(meters / 1609.344).toStringAsFixed(1)} mi';
    }
    return meters < 1000
        ? '${meters.round()} m'
        : '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _duration(double seconds) {
    final minutes = (seconds / 60).ceil();
    return minutes < 60
        ? '$minutes min'
        : '${minutes ~/ 60} h ${minutes % 60} min';
  }

  Widget _mapPanel() {
    final size = MediaQuery.sizeOf(context);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.symmetric(horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 580,
              maxHeight: size.height * .48,
            ),
            child: PursuitCard(
              child: _phase == _MapPhase.editor
                  ? (_highlightedLeg == null
                        ? _editorPanel()
                        : _roadChoices(_highlightedLeg!))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 10,
                        children: [
                          switch (_phase) {
                            _MapPhase.place => _placePanel(),
                            _MapPhase.tour => _tourPanel(),
                            _MapPhase.editor => const SizedBox.shrink(),
                            _MapPhase.drive => _drivePanel(),
                            _MapPhase.home => const SizedBox.shrink(),
                          },
                          if (_working) const LinearProgressIndicator(),
                          if (_error case final error?)
                            Text(
                              error,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(String label) => Text(
    label,
    style: Theme.of(context).textTheme.titleLarge
        ?.copyWith(fontWeight: FontWeight.w800),
  );

  Widget _placePanel() {
    final place = _place!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        _title(place.name),
        if (_pointRoute case final route?)
          Text('${_distance(route.distance)} · ${_duration(route.seconds)}'),
        FilledButton.icon(
          onPressed: _working
              ? null
              : _pointRoute == null
              ? _routeToPlace
              : _startDrive,
          icon: const Icon(Icons.directions_rounded),
          label: Text(_pointRoute == null ? 'Travel here' : 'Start drive'),
        ),
        OutlinedButton.icon(
          onPressed: () => _share(place.name, _placeLink(place)),
          icon: const Icon(Icons.group_outlined),
          label: const Text('Share with crew'),
        ),
      ],
    );
  }

  Widget _tourPanel() {
    final tour = _tour!;
    final complete = _stops.length == tour.stops.length;
    final routes = _legs.map(_routeFor).whereType<DriveRoute>().toList();
    final ready =
        complete && routes.length == _stops.length - 1 && routes.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        _title(tour.name),
        if (ready)
          Text(
            '${_distance(routes.fold(0.0, (total, route) => total + route.distance))} · '
            '${_duration(routes.fold(0.0, (total, route) => total + route.seconds))}',
          ),
        if (_working && !complete) const Text('Finding stops on the map…'),
        FilledButton.icon(
          onPressed: !_working && ready ? _startDrive : null,
          icon: const Icon(Icons.navigation_rounded),
          label: const Text('Start tour'),
        ),
        Wrap(
          spacing: 8,
          children: [
            if (tour.category == TourCategory.saved)
              OutlinedButton.icon(
                onPressed: _working || !complete
                    ? null
                    : () => _startEditor(edit: true),
                icon: const Icon(Icons.edit_location_alt_outlined),
                label: const Text('Reorder stops'),
              ),
            OutlinedButton.icon(
              onPressed: complete ? _shareTour : null,
              icon: const Icon(Icons.group_outlined),
              label: const Text('Share with crew'),
            ),
            if (!_working && !ready && _appleMap != null)
              TextButton(
                onPressed: () =>
                    complete ? _buildRoutes(fit: true) : _openTour(tour),
                child: const Text('Retry directions'),
              ),
          ],
        ),
        const Text('Itinerary', style: TextStyle(fontWeight: FontWeight.w800)),
        for (final (index, stop) in tour.stops.indexed)
          Text('${index + 1}. ${stop.name}'),
      ],
    );
  }

  Widget _editorPanel() => Padding(
    padding: const EdgeInsets.all(14),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Flexible(
          child: ReorderableListView.builder(
            shrinkWrap: true,
            primary: false,
            buildDefaultDragHandles: false,
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                _title(_tour == null ? 'Add tour' : 'Edit tour'),
                const Text('Hold the map or tap a landmark to add a stop.'),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _findPlace,
                  icon: const Icon(Icons.search),
                  label: const Text('Find a place'),
                ),
              ],
            ),
            footer: _error == null
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      TextButton(
                        onPressed: _working ? null : _buildRoutes,
                        child: const Text('Retry directions'),
                      ),
                    ],
                  ),
            itemCount: _stops.length,
            onReorderItem: _moveStop,
            itemBuilder: (context, index) {
              final stop = _stops[index];
              final legs = _legs;
              final leg = index < legs.length ? legs[index] : null;
              final route = leg == null ? null : _routeFor(leg);
              final current = leg == null ? null : _routes[leg];
              return Column(
                key: ObjectKey(stop),
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(stop.name),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Move stop ${index + 1} up',
                          icon: const Icon(Icons.arrow_upward_rounded),
                          onPressed: _saving || index == 0
                              ? null
                              : () => _moveStop(index, index - 1),
                        ),
                        IconButton(
                          tooltip: 'Move stop ${index + 1} down',
                          icon: const Icon(Icons.arrow_downward_rounded),
                          onPressed: _saving || index == _stops.length - 1
                              ? null
                              : () => _moveStop(index, index + 1),
                        ),
                        IconButton(
                          tooltip: 'Remove stop ${index + 1}',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _saving
                              ? null
                              : () {
                                  setState(() => _stops.removeAt(index));
                                  _stopsChanged();
                                },
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          enabled: !_saving && !_working,
                          child: const SizedBox.square(
                            dimension: 44,
                            child: Icon(Icons.drag_indicator),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (route != null && current != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: current.length > 1 && !_saving
                            ? () => _chooseLeg(index)
                            : null,
                        icon: const Icon(Icons.alt_route_rounded),
                        label: Text(
                          current.length > 1
                              ? 'Choose road · ${route.name.isEmpty ? _distance(route.distance) : route.name}'
                              : '${_distance(route.distance)} · ${_duration(route.seconds)}',
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        if (_working) const LinearProgressIndicator(),
        FilledButton.icon(
          onPressed: _stops.length >= 2 && !_saving && !_working
              ? _saveTour
              : null,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Finalize tour'),
        ),
      ],
    ),
  );

  Widget _roadChoices(int index) {
    final leg = _legs[index];
    final routes = _routes[leg]!;
    final selected = _routeFor(leg);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Flexible(
            child: ListView(
              shrinkWrap: true,
              primary: false,
              children: [
                _title('Choose road'),
                Text('${_stops[index].name} → ${_stops[index + 1].name}'),
                for (final (option, candidate) in routes.indexed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      candidate.name.isEmpty
                          ? 'Route ${option + 1}'
                          : candidate.name,
                    ),
                    subtitle: Text(
                      '${_distance(candidate.distance)} · ${_duration(candidate.seconds)}',
                    ),
                    leading: Icon(
                      candidate == selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: candidate == selected ? accent : Colors.blueAccent,
                    ),
                    selected: candidate == selected,
                    onTap: () {
                      setState(() => _preferences[leg] = candidate.preference);
                      _draw();
                    },
                  ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => _chooseLeg(index),
            child: const Text('Use selected road'),
          ),
        ],
      ),
    );
  }

  Widget _guidanceBanner() {
    final guidance = _guidance!;
    final maneuver = guidance.nextManeuver;
    return PursuitCard(
      child: Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            spacing: 12,
            children: [
              Icon(
                guidance.arrived
                    ? Icons.flag_rounded
                    : guidance.rerouting
                    ? Icons.alt_route_rounded
                    : Icons.navigation_rounded,
                size: 30,
                color: accent,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _title(
                      guidance.arrived
                          ? 'Arrived'
                          : guidance.rerouting
                          ? (guidance.tour ? 'Rejoining tour…' : 'Rerouting…')
                          : maneuver.instruction,
                    ),
                    if (!guidance.arrived && !guidance.rerouting)
                      Text(
                        guidance.error ??
                            (guidance.weakSignal
                                ? 'Weak GPS signal'
                                : _distance(maneuver.distance)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drivePanel() {
    final guidance = _guidance!;
    final remaining = guidance.remaining;
    final eta = DateTime.now().add(
      Duration(seconds: remaining.seconds.round()),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        _title(
          guidance.arrived
              ? guidance.destination
              : _tour?.name ?? guidance.destination,
        ),
        if (!guidance.arrived)
          Text(
            '${_duration(remaining.seconds)} · ${_distance(remaining.distance)} · '
            'ETA ${TimeOfDay.fromDateTime(eta).format(context)}',
          ),
        if (!guidance.arrived && guidance.tour)
          Text('Next stop: ${guidance.currentLeg.destination.name}'),
        Wrap(
          spacing: 8,
          children: [
            if (!guidance.arrived) ...[
              OutlinedButton.icon(
                onPressed: guidance.position == null ? null : _report,
                icon: const Icon(Icons.warning_amber_rounded),
                label: const Text('Report'),
              ),
              IconButton(
                tooltip: 'Recenter map',
                onPressed: () =>
                    _appleMap?.follow(true).catchError((Object _) {}),
                icon: const Icon(Icons.my_location_rounded),
              ),
            ],
            TextButton(
              onPressed: _closeWorkspace,
              child: Text(guidance.arrived ? 'Done' : 'End drive'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlaceSearch extends StatefulWidget {
  const _PlaceSearch(this.map);
  final AppleMap map;

  @override
  State<_PlaceSearch> createState() => _PlaceSearchState();
}

class _PlaceSearchState extends State<_PlaceSearch> {
  final _text = TextEditingController();
  List<MapPlace>? _places;
  bool _searching = false;
  bool _failed = false;

  Future<void> _search() async {
    if (_searching || _text.text.trim().isEmpty) return;
    setState(() {
      _searching = true;
      _failed = false;
    });
    try {
      final results = await widget.map.search(_text.text.trim());
      if (mounted) setState(() => _places = results);
    } on PlatformException {
      if (mounted) setState(() => _failed = true);
    } on MissingPluginException {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Find a place'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _text,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: 'Place or address',
              suffixIcon: IconButton(
                tooltip: 'Search map',
                icon: const Icon(Icons.search),
                onPressed: _searching ? null : _search,
              ),
            ),
          ),
          if (_searching) const LinearProgressIndicator(),
          if (_failed) const Text('Search unavailable. Try again.'),
          if (!_failed && _places?.isEmpty == true)
            const Text('No matching places.'),
          for (final place in _places ?? <MapPlace>[])
            ListTile(
              title: Text(place.name),
              leading: const Icon(Icons.place_outlined),
              onTap: () => Navigator.pop(context, place),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}

class _SaveTourDialog extends StatefulWidget {
  const _SaveTourDialog(this.name);
  final String name;

  @override
  State<_SaveTourDialog> createState() => _SaveTourDialogState();
}

class _SaveTourDialogState extends State<_SaveTourDialog> {
  late String _name = widget.name;

  void _save(bool share) {
    if (_name.trim().isNotEmpty) {
      Navigator.pop(context, (name: _name.trim(), share: share));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Save tour'),
    content: TextFormField(
      initialValue: widget.name,
      onChanged: (value) => setState(() => _name = value),
      maxLength: 60,
      decoration: const InputDecoration(labelText: 'Tour name'),
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _save(false),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      OutlinedButton(
        onPressed: _name.trim().isEmpty ? null : () => _save(true),
        child: const Text('Save & share'),
      ),
      FilledButton(
        onPressed: _name.trim().isEmpty ? null : () => _save(false),
        child: const Text('Save tour'),
      ),
    ],
  );
}
