import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pursuit/crew.dart';
import 'package:pursuit/driving.dart';
import 'package:pursuit/main.dart';
import 'package:pursuit/map_home.dart';
import 'package:pursuit/tours.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ios = TargetPlatformVariant({TargetPlatform.iOS});

  testWidgets('The tour sheet dismisses back to the map', (tester) async {
    await tester.pumpWidget(const PursuitApp());
    await tester.tap(find.text("Let's Tour"));
    await tester.pumpAndSettle();
    expect(find.byType(MapHome), findsOneWidget);
    expect(find.text('Add tour').hitTestable(), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Sella Pass Run'), findsOneWidget);
    await tester.drag(find.text('Add tour'), const Offset(0, -440));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Garda Lakeside'), 100);
    await tester.pumpAndSettle();
    expect(find.text('Dolomites Loop'), findsOneWidget);
    expect(find.text('Garda Lakeside').hitTestable(), findsOneWidget);
    final sheet = tester.getRect(find.byType(BottomSheet));
    await tester.dragFrom(
      Offset(sheet.center.dx, sheet.top + 14),
      const Offset(0, 470),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text("Let's Tour").hitTestable(), findsOneWidget);
  });

  testWidgets('A shared tour draws real map stops and starts guidance', (
    tester,
  ) async {
    final map = await _mountMap(tester);
    await tester.tap(find.text("Let's Tour"));
    await tester.pumpAndSettle();
    expect(map.previewPaths.first, hasLength(2));
    final expectedPaths = map.previewPaths.first;
    await tester.tap(find.text('Sella Pass Run').hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(UiKitView), findsOneWidget);
    expect(map.pins, hasLength(3));
    expect(map.lines, hasLength(2));
    expect(map.lines.map((line) => line['points']).toList(), expectedPaths);
    expect(find.text('Copy itinerary'), findsNothing);
    await tester.tap(find.text('Start tour'));
    await tester.pumpAndSettle();
    expect(find.text('End drive'), findsOneWidget);
    expect(map.following, isTrue);
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom event'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Gravel on bend');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(
      map.pins.where((pin) => pin['report'] == true).single['name'],
      'Gravel on bend',
    );
    await tester.tap(find.text('End drive'));
    await tester.pumpAndSettle();
    expect(map.following, isFalse);
  }, variant: ios);

  testWidgets('A saved tour can reorder stops from its detail panel', (
    tester,
  ) async {
    final map = await _mountMap(tester);
    await tester.tap(find.text("Let's Tour"));
    await tester.pumpAndSettle();
    final saved = find.text('Dolomites Loop');
    await tester.drag(find.text('Sella Pass Run'), const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(saved, 150);
    await tester.pumpAndSettle();
    await tester.tap(saved.hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reorder stops'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move stop 1 down'));
    await tester.pumpAndSettle();
    expect(map.pins.take(2).map((pin) => pin['name']), [
      'Passo Gardena',
      'Ortisei',
    ]);
    await tester.tap(find.text('Finalize tour'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save tour'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Reorder stops'), findsOneWidget);
    expect(find.text('1. Passo Gardena'), findsOneWidget);
    expect(find.text('2. Ortisei'), findsOneWidget);
  }, variant: ios);

  testWidgets('Add tour saves pins and the selected road on the map', (
    tester,
  ) async {
    final map = await _mountMap(tester);
    final storage = const MethodChannel('pursuit/tours');
    String? written;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(storage, (
      call,
    ) async {
      if (call.method == 'save') written = call.arguments as String;
      return call.method == 'load' ? written : null;
    });
    await tester.tap(find.text("Let's Tour"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add tour'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    await map.pin(tester, const MapPlace('Canazei', MapPoint(46.47, 11.77)));
    await map.pin(
      tester,
      const MapPlace('Passo Sella', MapPoint(46.51, 11.76)),
    );
    expect(map.pins, hasLength(2));
    await tester.tap(find.textContaining('Choose road'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Via the pass'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use selected road'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finalize tour'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Morning Loop');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save tour'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Morning Loop').hitTestable(), findsOneWidget);
    expect(written, contains('Via the pass'));
    expect(written, contains('Canazei'));
    expect(map.lines, hasLength(1));
    final restored = TourLibrary.demo();
    addTearDown(restored.dispose);
    await restored.restore();
    expect(restored.select(null).first.name, 'Morning Loop');
    expect(
      restored.select(null).first.preferences.single?.name,
      'Via the pass',
    );
  }, variant: ios);

  testWidgets('A dropped pin offers directions and a crew picker', (
    tester,
  ) async {
    final map = await _mountMap(tester);
    await map.pin(
      tester,
      const MapPlace('Dropped pin', MapPoint(46.51, 11.76)),
    );
    await tester.tap(find.text('Share with crew'));
    await tester.pumpAndSettle();
    expect(find.text('Share with which crew?'), findsOneWidget);
    await tester.tap(find.text('Alpine Drivers'));
    await tester.pumpAndSettle();
    expect(
      find.text('Added to Alpine Drivers on this device.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Travel here'));
    await tester.pumpAndSettle();
    expect(find.text('Start drive'), findsOneWidget);
    expect(map.lines, hasLength(1));
  }, variant: ios);

  test('A saved or newly shared tour leads the suggestion list', () async {
    final library = TourLibrary.demo();
    addTearDown(library.dispose);
    expect(library.select(null).first.name, 'Sella Pass Run');
    final created = await library.saveDraft(
      name: 'Sunrise run',
      places: const [
        MapPlace('Florence', MapPoint(43.77, 11.26)),
        MapPlace('Fiesole', MapPoint(43.81, 11.29)),
      ],
      preferences: const [null],
    );
    expect(library.select(null).first, same(created));
    expect(created.activityLabel, 'Created');
    library.receiveShared(
      name: 'Mountain roads',
      region: 'Dolomites',
      sender: 'Nina',
      stops: ['Ortisei', 'Corvara'],
    );
    expect(library.select(null).first.activityLabel, 'Shared by Nina');
  });

  test('An off-route tour takes the shortest available connector and keeps its stops', () async {
    const channel = MethodChannel('pursuit/navigation-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var candidate = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final distance = [800.0, 240.0, 500.0][candidate++];
      return [
        _mockRoute(
          call.arguments['from'],
          call.arguments['to'],
          distance: distance,
        ),
      ];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    const first = MapPlace('First', MapPoint(0, .02));
    const last = MapPlace('Second', MapPoint(0, .03));
    final guide = DriveGuidance(
      map: AppleMap(channel),
      tour: true,
      legs: [
        (
          route: DriveRoute.fromJson(_mockRoute([0, 0], first.point.toJson())),
          destination: first,
        ),
        (
          route: DriveRoute.fromJson(
            _mockRoute(first.point.toJson(), last.point.toJson()),
          ),
          destination: last,
        ),
      ],
    );
    addTearDown(guide.dispose);
    guide.update(const MapPoint(.002, .004), 5);
    guide.update(const MapPoint(.002, .005), 5);
    expect(guide.rerouting, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(guide.rejoining, isTrue);
    expect(guide.currentLeg.destination, first);
    expect(guide.stopsRemaining, 2);
    final join = guide.lines.first.points.last;
    expect(join.longitude, closeTo(.005 + 300 / 111195, .00001));
    guide.update(join, 5);
    expect(guide.rejoining, isFalse);
    guide.update(first.point, 5);
    expect(guide.currentLeg.destination, last);
  });

  testWidgets('The home actions open Garage, Crew, and Settings', (
    tester,
  ) async {
    await tester.pumpWidget(const PursuitApp());

    await tester.tap(find.text('My Garage'));
    await tester.pumpAndSettle();
    expect(find.text('Account details').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Rosso'));
    await tester.pumpAndSettle();
    expect(find.text('Specifications'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Burgundy metallic'), 180);
    expect(find.text('Burgundy metallic'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('My Crew'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('@maya').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text("Maya Chen's Garage"), findsOneWidget);
    expect(find.text('Blue Hour'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Mazda MX-5'), 180);
    expect(find.text('Mazda MX-5'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Larger text').hitTestable(), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
    expect(tester.getSize(find.byType(Scaffold)).width, 800);

    await tester.tap(find.byTooltip('Close settings'));
    await tester.pumpAndSettle();
    expect(find.text("Let's Tour").hitTestable(), findsOneWidget);
  });

  test(
    'Rider suggestions respond to partners and prioritise a matching contact',
    () {
      final directory = CrewDirectory();
      addTearDown(directory.dispose);
      expect(directory.suggestions.map((entry) => entry.rider.handle), [
        'nina',
        'omar',
      ]);
      expect(directory.suggestions.first.mutual, 2);
      expect(directory.matchContact('  Omar  Haddad '), isTrue);
      expect(directory.suggestions.first.rider.handle, 'omar');
      expect(directory.suggestions.first.contact, isTrue);
      expect(directory.addHandle('@omar'), isTrue);
      expect(directory.suggestions.map((entry) => entry.rider.handle), [
        'nina',
      ]);
    },
  );

  testWidgets(
    'The map fills the screen and the floating controls respect safe areas',
    (tester) async {
      const screen = Size(320, 690);
      const safeArea = FakeViewPadding(top: 48, bottom: 34);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = screen;
      tester.view.padding = safeArea;
      tester.view.viewPadding = safeArea;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (_) async => null,
      );

      await tester.pumpWidget(const PursuitApp());
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byType(UiKitView)), Offset.zero & screen);
      expect(find.text('» PURSUIT'), findsNothing);
      final garage = tester.getRect(find.text('My Garage'));
      final tour = tester.getRect(find.text("Let's Tour"));
      final crew = tester.getRect(find.text('My Crew'));
      expect(garage.right, lessThan(tour.left));
      expect(tour.center.dx, closeTo(screen.width / 2, 1));
      expect(crew.left, greaterThan(tour.right));
      expect(tour.bottom, lessThan(screen.height - safeArea.bottom));
      expect(
        tester.getTopLeft(find.byTooltip('Settings')).dy,
        greaterThan(safeArea.top),
      );
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );
}

Map<String, Object> _mockRoute(
  Object from,
  Object to, {
  String name = 'Main road',
  double distance = 6200,
}) => {
  'name': name,
  'distance': distance,
  'time': 300,
  'points': [from, to],
  'steps': <Object>[],
};

Future<_TestMap> _mountMap(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('pursuit/tours'),
    (_) async => null,
  );
  final map = _TestMap();
  messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
    call,
  ) async {
    if (call.method == 'create') {
      map.channel = MethodChannel("pursuit/apple-map/${call.arguments['id']}");
      messenger.setMockMethodCallHandler(map.channel, map.handle);
    }
    return null;
  });
  await tester.pumpWidget(const PursuitApp());
  await tester.pumpAndSettle();
  return map;
}

class _TestMap {
  late MethodChannel channel;
  List<dynamic> pins = [];
  List<dynamic> lines = [];
  final previewPaths = <List<dynamic>>[];
  bool following = false;
  int searches = 0;

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments;
    switch (call.method) {
      case 'snapshot':
        previewPaths.add(args['paths'] as List);
      case 'scene':
        pins = args['pins'] as List;
        lines = args['lines'] as List;
      case 'search':
        return [
          MapPlace(
            args['query'] as String,
            MapPoint(46.47 + .02 * searches++, 11.75),
          ).toJson(),
        ];
      case 'route':
        return [
          _mockRoute(args['from'], args['to']),
          if (args['alternatives'] == true)
            _mockRoute(
              args['from'],
              args['to'],
              name: 'Via the pass',
              distance: 7200,
            ),
        ];
      case 'position':
        return [46.46, 11.75];
      case 'follow':
        following = args['enabled'] as bool;
    }
    return null;
  }

  Future<void> pin(WidgetTester tester, MapPlace place) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('placeSelected', place.toJson()),
      ),
      null,
    );
    await tester.pumpAndSettle();
  }
}
