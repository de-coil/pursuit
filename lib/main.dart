import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'crew.dart';
import 'garage.dart';
import 'map_home.dart';
import 'pursuit_ui.dart';
import 'tours.dart';

void main() => runApp(const PursuitApp());

class PursuitApp extends StatefulWidget {
  const PursuitApp({super.key});

  @override
  State<PursuitApp> createState() => _PursuitAppState();
}

class _PursuitAppState extends State<PursuitApp> {
  final _preferences = _Preferences();
  final _crew = CrewDirectory();
  final _tours = TourLibrary.demo();
  RiderProfile _garage = RiderProfile.sampleGarage;

  @override
  void initState() {
    super.initState();
    _tours.restore();
  }

  @override
  void dispose() {
    _preferences.dispose();
    _crew.dispose();
    _tours.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _preferences,
    builder: (context, _) {
      final scheme =
          ColorScheme.fromSeed(
            seedColor: accent,
            brightness: Brightness.dark,
          ).copyWith(
            primary: accent,
            onPrimary: canvasColor,
            surface: _preferences.contrast ? canvasColor : panelColor,
            onSurface: inkColor,
            onSurfaceVariant: _preferences.contrast
                ? Colors.white
                : secondaryText,
            secondaryContainer: accent,
            onSecondaryContainer: canvasColor,
            outline: const Color(0xff829691),
          );
      return MaterialApp(
        title: 'Pursuit',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: scheme,
          scaffoldBackgroundColor: _preferences.contrast
              ? Colors.black
              : canvasColor,
          appBarTheme: const AppBarTheme(
            backgroundColor: canvasColor,
            foregroundColor: inkColor,
            scrolledUnderElevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            titleTextStyle: TextStyle(
              color: inkColor,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: _preferences.largeText
                  ? TextScaler.linear(media.textScaler.scale(1) * 1.2)
                  : media.textScaler,
              disableAnimations:
                  media.disableAnimations || _preferences.reduceMotion,
            ),
            child: child!,
          );
        },
        home: Builder(
          builder: (context) => MapHome(
            tours: _tours,
            crew: _crew,
            miles: _preferences.miles,
            onSettings: () => _open(context, _Settings(_preferences)),
            onCrew: () => _open(
              context,
              CrewPage(directory: _crew, miles: _preferences.miles),
            ),
            onGarage: () => _open(
              context,
              GaragePage(
                profile: _garage,
                miles: _preferences.miles,
                onChanged: (profile) => _garage = profile,
              ),
            ),
          ),
        ),
      );
    },
  );

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

class _Preferences extends ChangeNotifier {
  bool largeText = false;
  bool contrast = false;
  bool reduceMotion = false;
  bool miles = false;

  void update(VoidCallback change) {
    change();
    notifyListeners();
  }
}

class _Settings extends StatelessWidget {
  const _Settings(this.preferences);

  final _Preferences preferences;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => PursuitScreen(
      title: 'Settings',
      leading: IconButton(
        tooltip: 'Close settings',
        icon: const Icon(Icons.close_rounded),
        onPressed: () => Navigator.pop(context),
      ),
      body: ScreenList(
        children: [
          const SectionTitle('Accessibility'),
          PursuitCard(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Larger text'),
                  value: preferences.largeText,
                  onChanged: (value) =>
                      preferences.update(() => preferences.largeText = value),
                ),
                SwitchListTile(
                  title: const Text('Higher contrast'),
                  value: preferences.contrast,
                  onChanged: (value) =>
                      preferences.update(() => preferences.contrast = value),
                ),
                SwitchListTile(
                  title: const Text('Reduce motion'),
                  value: preferences.reduceMotion,
                  onChanged: (value) => preferences.update(
                    () => preferences.reduceMotion = value,
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('App preferences'),
          PursuitCard(
            child: SwitchListTile(
              title: const Text('Use miles'),
              subtitle: Text(
                preferences.miles ? 'Example: 10 mi' : 'Example: 16 km',
              ),
              value: preferences.miles,
              onChanged: (value) =>
                  preferences.update(() => preferences.miles = value),
            ),
          ),
        ],
      ),
    ),
  );
}
