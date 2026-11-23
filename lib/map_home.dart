import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'crew.dart';
import 'driving.dart';
import 'pursuit_ui.dart';
import 'tours.dart';

part 'map_workflows.dart';

const _appleMapViewType = 'pursuit/apple-map';

class MapHome extends StatefulWidget {
  const MapHome({
    super.key,
    required this.onGarage,
    required this.tours,
    required this.crew,
    required this.miles,
    required this.onCrew,
    required this.onSettings,
  });

  final VoidCallback onGarage;
  final TourLibrary tours;
  final CrewDirectory crew;
  final bool miles;
  final VoidCallback onCrew;
  final VoidCallback onSettings;

  @override
  State<MapHome> createState() => _MapHomeState();
}

class _MapHomeState extends State<MapHome> with _MapWorkflows {
  bool _locating = false;
  String? _locationError;

  bool get _hasAppleMap =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _locate() async {
    final channel = _mapChannel;
    if (channel == null || _locating) return;

    setState(() {
      _locating = true;
      _locationError = null;
    });
    const fallbackError = 'Couldn’t find your location. Try again.';
    String? message;
    try {
      await channel.invokeMethod<void>('locate');
    } on PlatformException catch (error) {
      message = error.message ?? fallbackError;
    } on MissingPluginException {
      message = fallbackError;
    }
    if (!mounted) return;
    setState(() {
      _locating = false;
      _locationError = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _phase == _MapPhase.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _phase != _MapPhase.home) _closeWorkspace();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: const Color(0xff101b1c),
          resizeToAvoidBottomInset: false,
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (_hasAppleMap)
                UiKitView(
                  viewType: _appleMapViewType,
                  onPlatformViewCreated: (id) {
                    if (!mounted) return;
                    _attachMap(MethodChannel('$_appleMapViewType/$id'));
                  },
                )
              else
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Apple Maps is available on iOS.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurface),
                    ),
                  ),
                ),
              Positioned(top: 0, left: 0, right: 0, child: _header()),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _phase == _MapPhase.home ? _footer(colors) : _mapPanel(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => SafeArea(
    bottom: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: _phase == _MapPhase.drive
          ? _guidanceBanner()
          : Align(
              alignment: Alignment.centerLeft,
              child: Tooltip(
                message: _phase == _MapPhase.home
                    ? 'Settings'
                    : _highlightedLeg == null
                    ? 'Close map panel'
                    : 'Back to pins',
                child: _MapButton(
                  radius: 24,
                  onPressed: _phase == _MapPhase.home
                      ? widget.onSettings
                      : _closeWorkspace,
                  child: SizedBox.square(
                    dimension: 48,
                    child: Icon(
                      _phase == _MapPhase.home
                          ? Icons.menu_rounded
                          : _highlightedLeg == null
                          ? Icons.close_rounded
                          : Icons.arrow_back_rounded,
                    ),
                  ),
                ),
              ),
            ),
    ),
  );

  Widget _footer(ColorScheme colors) => SafeArea(
    top: false,
    minimum: const EdgeInsets.symmetric(horizontal: 16),
    child: Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 352),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hasAppleMap)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (_locationError case final error?)
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Semantics(
                              liveRegion: true,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colors.onPrimary,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(error),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Tooltip(
                        message: _locating
                            ? 'Finding your location…'
                            : 'Use my location',
                        child: _MapButton(
                          radius: 24,
                          onPressed: _mapChannel == null || _locating
                              ? null
                              : _locate,
                          child: SizedBox.square(
                            dimension: 48,
                            child: _locating
                                ? Center(
                                    child: SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        color: colors.onPrimary,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.my_location_rounded),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                spacing: 12,
                children: [
                  Expanded(
                    flex: 2,
                    child: _action(
                      'My Garage',
                      Icons.directions_car_outlined,
                      widget.onGarage,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: _action(
                      "Let's Tour",
                      Icons.route_rounded,
                      _openTourMenu,
                      primary: true,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: _action(
                      'My Crew',
                      Icons.group_outlined,
                      widget.onCrew,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _action(
    String label,
    IconData icon,
    VoidCallback onPressed, {
    bool primary = false,
  }) => _MapButton(
    primary: primary,
    radius: primary ? 32 : 26,
    onPressed: onPressed,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: primary ? 16 : 13),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 5,
        children: [
          Icon(icon, size: primary ? 30 : 23),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: primary ? 16 : 13,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.radius,
    required this.onPressed,
    required this.child,
    this.primary = false,
  });

  final double radius;
  final VoidCallback? onPressed;
  final Widget child;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(radius);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(
            color: primary ? const Color(0xfff1ffad) : Colors.white,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: primary
                ? [const Color(0xfff1ff9d), colors.primary]
                : const [Color(0xfcffffff), Color(0xedebf5ef)],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x38152f29),
              blurRadius: 20,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: borderRadius,
            overlayColor: const WidgetStatePropertyAll(Color(0x20071e20)),
            child: IconTheme.merge(
              data: IconThemeData(color: colors.onPrimary),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: colors.onPrimary),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
