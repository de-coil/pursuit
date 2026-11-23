import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'garage.dart';
import 'pursuit_ui.dart';

const _riders = {
  'maya': RiderProfile(
    name: 'Maya Chen',
    handle: 'maya',
    home: 'Bolzano, Italy',
    avatarAsset: 'assets/avatars/maya.jpg',
    cars: [
      Vehicle(
        model: 'Alpine A110',
        nickname: 'Blue Hour',
        year: '2022',
        paint: 'Alpine blue',
        transmission: '7-speed dual-clutch',
        photoAsset: 'assets/garage/blue-hour.png',
      ),
      Vehicle(
        model: 'Mazda MX-5',
        year: '2016',
        paint: 'Ceramic white',
        transmission: '6-speed manual',
      ),
    ],
  ),
  'leo': RiderProfile(
    name: 'Leo Moretti',
    handle: 'leo',
    home: 'Trento, Italy',
    avatarAsset: 'assets/avatars/leo.jpg',
    cars: [
      Vehicle(
        model: 'BMW M2',
        year: '2020',
        paint: 'Hockenheim silver',
        transmission: '6-speed manual',
      ),
    ],
  ),
  'nina': RiderProfile(
    name: 'Nina Rossi',
    handle: 'nina',
    home: 'Verona, Italy',
    avatarAsset: 'assets/avatars/nina.jpg',
    cars: [
      Vehicle(
        model: 'Lotus Elise',
        year: '2018',
        paint: 'British racing green',
        transmission: '6-speed manual',
      ),
    ],
  ),
  'omar': RiderProfile(
    name: 'Omar Haddad',
    handle: 'omar',
    home: 'Florence, Italy',
    avatarAsset: 'assets/avatars/omar.jpg',
    cars: [
      Vehicle(
        model: 'Toyota GR Yaris',
        year: '2023',
        paint: 'Pearl white',
        transmission: '6-speed manual',
      ),
    ],
  ),
};

const _crews = [
  (
    name: 'Alpine Drivers',
    region: 'Dolomites',
    members: ['maya', 'leo', 'nina'],
  ),
  (name: 'Sunday Run Club', region: 'Tuscany', members: ['leo', 'omar']),
];

const _connections = {
  'nina': {'maya', 'leo'},
  'omar': {'leo'},
};

class CrewDirectory extends ChangeNotifier {
  final _profiles = {..._riders};
  final _partners = <String>{'maya', 'leo'};
  final _contactMatches = <String>{};
  final _posts = <String, List<({String title, String text})>>{};

  Iterable<String> get crewNames => _crews.map((crew) => crew.name);
  List<({String title, String text})> postsFor(String crew) =>
      List.unmodifiable(_posts[crew] ?? const []);

  void shareWithCrew(String crew, String title, String text) {
    _posts.putIfAbsent(crew, () => []).insert(0, (title: title, text: text));
    notifyListeners();
  }

  Iterable<RiderProfile> get partners => _partners.map(profile);
  RiderProfile profile(String handle) => _profiles[handle]!;
  bool isPartner(RiderProfile rider) => _partners.contains(rider.handle);

  List<({RiderProfile rider, int mutual, bool contact})> get suggestions {
    final suggestions = [
      for (final rider in _profiles.values)
        if (!isPartner(rider))
          (
            rider: rider,
            mutual:
                _connections[rider.handle]?.intersection(_partners).length ?? 0,
            contact: _contactMatches.contains(rider.handle),
          ),
    ]..removeWhere((entry) => !entry.contact && entry.mutual == 0);
    return suggestions..sort((first, second) {
      if (first.contact != second.contact) return first.contact ? -1 : 1;
      final byMutual = second.mutual.compareTo(first.mutual);
      return byMutual != 0
          ? byMutual
          : first.rider.name.compareTo(second.rider.name);
    });
  }

  bool matchContact(String name) {
    final normalized = name.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    if (normalized.isEmpty) return false;
    final matches = _profiles.values.where(
      (rider) =>
          rider.name.toLowerCase() == normalized || rider.handle == normalized,
    );
    if (matches.length != 1 || isPartner(matches.single)) return false;
    if (_contactMatches.add(matches.single.handle)) notifyListeners();
    return true;
  }

  bool addHandle(String input) {
    final handle = input.replaceFirst(RegExp(r'^@+'), '').trim().toLowerCase();
    if (handle.isEmpty || RegExp(r'\s').hasMatch(handle)) return false;
    final rider = _profiles.putIfAbsent(
      handle,
      () => RiderProfile(name: handle, handle: handle),
    );
    setPartner(rider, true);
    return true;
  }

  void setPartner(RiderProfile rider, bool isPartner) {
    final changed = isPartner
        ? _partners.add(rider.handle)
        : _partners.remove(rider.handle);
    if (changed) notifyListeners();
  }
}

class CrewPage extends StatefulWidget {
  const CrewPage({super.key, required this.directory, required this.miles});

  final CrewDirectory directory;
  final bool miles;

  @override
  State<CrewPage> createState() => _CrewPageState();
}

class _CrewPageState extends State<CrewPage> {
  bool _pickingContact = false;
  CrewDirectory get _directory => widget.directory;

  void _openRider(RiderProfile rider) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GaragePage(
          profile: rider,
          miles: widget.miles,
          profileAction: ListenableBuilder(
            listenable: _directory,
            builder: (context, _) {
              final partner = _directory.isPartner(rider);
              return OutlinedButton.icon(
                onPressed: () => _directory.setPartner(rider, !partner),
                icon: Icon(
                  partner ? Icons.person_remove_outlined : Icons.person_add_alt,
                ),
                label: Text(partner ? 'Remove partner' : 'Add partner'),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _addPartner() async {
    final handle = await askForText(context, 'Add a partner', 'Handle');
    if (!mounted || handle == null) return;
    if (!_directory.addHandle(handle)) {
      _showMessage('Enter a handle without spaces.');
    }
  }

  Future<void> _pickContact() async {
    if (_pickingContact) return;
    setState(() => _pickingContact = true);
    String? message;
    try {
      final name = await const MethodChannel('pursuit/contacts')
          .invokeMethod<String>('pickName');
      if (!mounted) return;
      if (name != null && !_directory.matchContact(name)) {
        message = 'No new rider matches that contact name.';
      }
    } on PlatformException {
      message = 'Couldn’t open Contacts. Try again.';
    } on MissingPluginException {
      message = 'Contacts are unavailable.';
    }
    if (!mounted) return;
    setState(() => _pickingContact = false);
    if (message != null) _showMessage(message);
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  void _openCrew(String name, List<RiderProfile> members) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PursuitScreen(
          title: name,
          body: ListenableBuilder(
            listenable: _directory,
            builder: (context, _) => ScreenList(
              children: [
                const SectionTitle('Riders'),
                for (final rider in members)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _RiderCard(
                      rider: rider,
                      onTap: () => _openRider(rider),
                    ),
                  ),
                if (_directory.postsFor(name).isNotEmpty)
                  const SectionTitle('Shared with this crew'),
                for (final post in _directory.postsFor(name))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PursuitCard(
                      child: ListTile(
                        leading: const Icon(Icons.share_location_outlined),
                        title: Text(post.title),
                        subtitle: const Text('Saved on this device'),
                        trailing: IconButton(
                          tooltip: 'Copy shared item',
                          icon: const Icon(Icons.copy_outlined),
                          onPressed: () =>
                              Clipboard.setData(ClipboardData(text: post.text)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PursuitScreen(
    title: 'My Crew',
    body: ListenableBuilder(
      listenable: _directory,
      builder: (context, _) {
        final suggestions = _directory.suggestions;
        return ScreenList(
          children: [
            const SectionTitle('Your crews'),
            for (final crew in _crews)
              _crewCard(
                crew.name,
                crew.region,
                crew.members.map(_directory.profile).toList(),
              ),
            SectionTitle(
              'Partners',
              action: IconButton(
                tooltip: 'Add a partner',
                icon: const Icon(Icons.person_add_alt),
                onPressed: _addPartner,
              ),
            ),
            if (_directory.partners.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Add a partner by their handle.'),
              ),
            for (final rider in _directory.partners)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RiderCard(rider: rider, onTap: () => _openRider(rider)),
              ),
            const SectionTitle('Riders you might know'),
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _pickingContact ? null : _pickContact,
                  icon: const Icon(Icons.contacts_outlined),
                  label: const Text('Match a saved contact'),
                ),
              ),
            if (suggestions.isEmpty)
              const Text('New suggestions appear as you add partners.'),
            for (final item in suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RiderCard(
                  rider: item.rider,
                  reason: item.contact
                      ? 'Matches a saved contact name'
                      : '${item.mutual} mutual ${item.mutual == 1 ? 'partner' : 'partners'}',
                  onTap: () => _openRider(item.rider),
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _crewCard(String name, String region, List<RiderProfile> members) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: PursuitCard(
          onTap: () => _openCrew(name, members),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xff203733), panelColor]),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 9,
              children: [
                Row(
                  spacing: 10,
                  children: [
                    const Icon(Icons.terrain_rounded, color: accent),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final rider in members) RiderAvatar(rider, radius: 14),
                    Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: Text(
                        '$region · ${members.length} riders',
                        style: const TextStyle(color: secondaryText),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _RiderCard extends StatelessWidget {
  const _RiderCard({required this.rider, required this.onTap, this.reason});

  final RiderProfile rider;
  final VoidCallback onTap;
  final String? reason;

  @override
  Widget build(BuildContext context) => PursuitCard(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        spacing: 12,
        children: [
          RiderAvatar(rider),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  rider.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(rider.tag, style: const TextStyle(color: accent)),
                if (reason case final description?)
                  Text(
                    description,
                    style: const TextStyle(color: secondaryText),
                  ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    ),
  );
}
