import 'package:material_ui/material_ui.dart';

import 'pursuit_ui.dart';

class Vehicle {
  const Vehicle({
    required this.model,
    this.nickname = '',
    this.year = '',
    this.paint = '',
    this.transmission = '',
    this.odometerKm,
    this.photoAsset,
  });

  final String model;
  final String nickname;
  final String year;
  final String paint;
  final String transmission;
  final int? odometerKm;
  final String? photoAsset;

  String get title => nickname.isEmpty ? model : nickname;
}

class RiderProfile {
  const RiderProfile({
    required this.name,
    required this.handle,
    this.home = '',
    this.avatarAsset,
    this.cars = const [],
  });

  final String name;
  final String handle;
  final String home;
  final String? avatarAsset;
  final List<Vehicle> cars;

  String get tag => '@$handle';

  RiderProfile copyWith({
    String? name,
    String? handle,
    String? home,
    List<Vehicle>? cars,
  }) => RiderProfile(
    name: name ?? this.name,
    handle: handle ?? this.handle,
    home: home ?? this.home,
    avatarAsset: avatarAsset,
    cars: cars ?? this.cars,
  );

  static const sampleGarage = RiderProfile(
    name: '',
    handle: '',
    cars: [
      Vehicle(
        model: '911 Carrera S',
        nickname: 'Rosso',
        year: '2021',
        paint: 'Burgundy metallic',
        transmission: '8-speed PDK',
        odometerKm: 18240,
        photoAsset: 'assets/garage/rosso.png',
      ),
    ],
  );
}

class RiderAvatar extends StatelessWidget {
  const RiderAvatar(this.rider, {super.key, this.radius = 24});

  final RiderProfile rider;
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: const Color(0xff2b3f3e),
    foregroundColor: inkColor,
    foregroundImage: rider.avatarAsset == null
        ? null
        : AssetImage(rider.avatarAsset!),
    child: Icon(Icons.person_outline_rounded, size: radius),
  );
}

class GaragePage extends StatefulWidget {
  const GaragePage({
    super.key,
    required this.profile,
    required this.miles,
    this.onChanged,
    this.profileAction,
  });

  final RiderProfile profile;
  final bool miles;
  final ValueChanged<RiderProfile>? onChanged;
  final Widget? profileAction;

  @override
  State<GaragePage> createState() => _GaragePageState();
}

class _GaragePageState extends State<GaragePage> {
  late RiderProfile _profile = widget.profile;
  bool get _isOwner => widget.onChanged != null;

  void _update(RiderProfile profile) {
    setState(() => _profile = profile);
    widget.onChanged?.call(profile);
  }

  Future<void> _editProfile() async {
    final changes = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => DetailEditor(
          title: 'Edit account',
          values: {
            'Display name': _profile.name,
            'Handle': _profile.handle,
            'Home region': _profile.home,
          },
          requiredFields: const {'Display name', 'Handle'},
        ),
      ),
    );
    if (changes == null || !mounted) return;
    _update(
      _profile.copyWith(
        name: changes['Display name'],
        handle: changes['Handle']!.replaceFirst(RegExp(r'^@+'), ''),
        home: changes['Home region'],
      ),
    );
  }

  void _openVehicle(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VehiclePage(
          vehicle: _profile.cars[index],
          miles: widget.miles,
          onChanged: _isOwner
              ? (vehicle) {
                  final cars = _profile.cars.toList();
                  cars[index] = vehicle;
                  _update(_profile.copyWith(cars: cars));
                }
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PursuitScreen(
    title: _isOwner ? 'My Garage' : "${_profile.name}'s Garage",
    body: ScreenList(
      children: [
        const SectionTitle('Account details'),
        PursuitCard(
          onTap: _isOwner ? _editProfile : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              spacing: 14,
              children: [
                RiderAvatar(_profile, radius: 28),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 3,
                    children: [
                      Text(
                        _profile.name.isEmpty ? 'Your profile' : _profile.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        _profile.handle.isEmpty
                            ? 'Add your name and handle'
                            : _profile.tag,
                        style: TextStyle(
                          color: _profile.handle.isEmpty
                              ? secondaryText
                              : accent,
                        ),
                      ),
                      if (_profile.home.isNotEmpty)
                        Text(
                          _profile.home,
                          style: const TextStyle(color: secondaryText),
                        ),
                    ],
                  ),
                ),
                if (_isOwner) const Icon(Icons.edit_outlined, size: 20),
              ],
            ),
          ),
        ),
        if (widget.profileAction case final action?)
          Padding(padding: const EdgeInsets.only(top: 12), child: action),
        SectionTitle(_isOwner ? 'Your cars' : 'Cars'),
        if (_profile.cars.isEmpty)
          const PursuitCard(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No cars listed yet.'),
            ),
          ),
        for (final (index, car) in _profile.cars.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PursuitCard(
              onTap: () => _openVehicle(index),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  VehicleImage(
                    vehicle: car,
                    aspectRatio: car.photoAsset == null ? 2.9 : 2,
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 2, 14, 8),
                    title: Text(
                      car.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      [
                        if (car.year.isNotEmpty) car.year,
                        if (car.nickname.isNotEmpty) car.model,
                        if (car.nickname.isEmpty && car.paint.isNotEmpty)
                          car.paint,
                      ].join(' · '),
                    ),
                    trailing: const Icon(Icons.arrow_outward_rounded),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class VehicleImage extends StatelessWidget {
  const VehicleImage({
    super.key,
    required this.vehicle,
    required this.aspectRatio,
  });

  final Vehicle vehicle;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: aspectRatio,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -.15),
          radius: .9,
          colors: [Color(0xff354b48), Color(0xff131e20)],
        ),
      ),
      child: vehicle.photoAsset == null
          ? const Icon(
              Icons.directions_car_outlined,
              size: 64,
              color: Color(0xff91aba2),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Image.asset(
                vehicle.photoAsset!,
                semanticLabel: vehicle.model,
                fit: BoxFit.contain,
              ),
            ),
    ),
  );
}

class VehiclePage extends StatefulWidget {
  const VehiclePage({
    super.key,
    required this.vehicle,
    required this.miles,
    this.onChanged,
  });

  final Vehicle vehicle;
  final bool miles;
  final ValueChanged<Vehicle>? onChanged;

  @override
  State<VehiclePage> createState() => _VehiclePageState();
}

class _VehiclePageState extends State<VehiclePage> {
  late Vehicle _vehicle = widget.vehicle;

  Future<void> _editVehicle() async {
    final changes = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => DetailEditor(
          title: 'Edit vehicle',
          values: {
            'Vehicle model': _vehicle.model,
            'Nickname': _vehicle.nickname,
            'Model year': _vehicle.year,
            'Paint': _vehicle.paint,
            'Transmission': _vehicle.transmission,
          },
          requiredFields: const {'Vehicle model'},
        ),
      ),
    );
    if (changes == null || !mounted) return;
    final sameCar = changes['Vehicle model'] == _vehicle.model;
    final car = Vehicle(
      model: changes['Vehicle model']!,
      nickname: changes['Nickname']!,
      year: changes['Model year']!,
      paint: changes['Paint']!,
      transmission: changes['Transmission']!,
      odometerKm: sameCar ? _vehicle.odometerKm : null,
      photoAsset: sameCar && changes['Paint'] == _vehicle.paint
          ? _vehicle.photoAsset
          : null,
    );
    setState(() => _vehicle = car);
    widget.onChanged?.call(car);
  }

  @override
  Widget build(BuildContext context) {
    final odo = _vehicle.odometerKm;
    return PursuitScreen(
      title: 'Vehicle details',
      actions: [
        if (widget.onChanged != null)
          IconButton(
            tooltip: 'Edit vehicle',
            onPressed: _editVehicle,
            icon: const Icon(Icons.edit_outlined),
          ),
      ],
      body: ScreenList(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                Text(
                  _vehicle.title,
                  style: Theme.of(context).textTheme.displaySmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                if (_vehicle.nickname.isNotEmpty)
                  Text(
                    _vehicle.model,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: secondaryText),
                  ),
              ],
            ),
          ),
          PursuitCard(
            child: VehicleImage(vehicle: _vehicle, aspectRatio: 1.55),
          ),
          const SectionTitle('Specifications'),
          PursuitCard(
            child: Column(
              children: [
                _spec(
                  Icons.calendar_today_outlined,
                  'Model year',
                  _vehicle.year,
                ),
                _spec(Icons.palette_outlined, 'Paint', _vehicle.paint),
                _spec(
                  Icons.settings_outlined,
                  'Transmission',
                  _vehicle.transmission,
                ),
                _spec(
                  Icons.speed_rounded,
                  'Odometer',
                  odo == null
                      ? ''
                      : widget.miles
                      ? '${(odo * .621371).round()} mi'
                      : '$odo km',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _spec(IconData icon, String label, String value) => ListTile(
    leading: Icon(icon, color: accent),
    title: Text(label),
    subtitle: Text(value.isEmpty ? 'Not listed' : value),
  );
}
