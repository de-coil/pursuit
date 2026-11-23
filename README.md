# Pursuit

An iOS-first Flutter prototype for planning car tours.

## Run locally

Start an iPhone simulator in Device Hub or connect a development-enabled iPhone. From this directory:

```sh
flutter pub get
flutter devices
flutter run -d <device-id>
```

Use the device ID from `flutter devices`. For a physical iPhone, select your Apple development team under Signing & Capabilities in the Runner target if Flutter reports a signing error.

## Try the prototype

- Home opens on a dark, full-screen Apple Map of the Dolomites. The location button above **My Crew** recenters the map after iOS location permission is granted. The top-left menu opens full-screen Settings.
- **My Garage** shows your account and a sample car. Tap the account card to edit your profile, or tap the car card to see and edit its specifications.
- **My Crew** shows sample crews, partners, and suggested riders. Suggestions use mutual partners and, on iOS, the name of a contact you choose. Tap a rider's tag to view their profile and cars. The contact name is compared on-device.
- Tap a landmark or hold the map to drop a pin. **Travel here** previews Apple Maps driving directions. **Start drive** starts foreground guidance with maneuver distance, remaining distance, and ETA.
- **Let's Tour** opens a swipe-down sheet. The tour list shows Apple Maps driving previews and puts recent activity first. Open a tour to see its numbered stops and driving legs on the map. **Reorder stops** opens the editor for a saved tour, where you can drag stops or use the up and down buttons. **Start tour** guides you to the stops in order. If you leave the route, Pursuit compares available driving distances to nearby rejoin points on the active leg.
- **Add tour** opens a map editor. Hold the map, tap a landmark, or use **Find a place** to add stops. Drag a stop by its handle to reorder it or tap its remove button. **Choose road** shows alternatives when Apple Maps supplies them. **Finalize tour** saves the named tour to this iPhone.
- **Report** during guidance adds a road-event pin for this session. **Share with crew** asks which crew, adds the item to its local activity, and offers the iOS share sheet for sending the itinerary or location.

Profiles, crews, and incoming shares use demo data. Crew activity and road reports are local to the running app. Saved routes retain their pins and road preferences on the device, and Apple Maps recalculates the driving legs when opened.

## Demo imagery

The built-in ImageGen tool generated the car images at `assets/garage/rosso.png` and `assets/garage/blue-hour.png`, and the rider portraits at `assets/avatars/maya.jpg`, `assets/avatars/leo.jpg`, `assets/avatars/nina.jpg`, and `assets/avatars/omar.jpg`.

<details>
<summary>Image generation prompts</summary>

- **Rosso**. Use case: product-mockup. Asset type: vehicle hero cutout for a dark performance touring garage app. Subject: a single metallic deep burgundy red modern rear-engined European touring sports coupe, subtle wide rear fenders, conventional round headlamps, brushed gunmetal wheels. Clean three-quarter front view from slightly above, nose at lower left, rear at upper right. Full vehicle with breathing room in a wide landscape composition, natural proportions and authentic paint reflections, premium studio automotive photograph, soft overhead strip lighting with just enough fill to see the dark tires. Genuine transparent background with soft contact shadow beneath the tires only. No setting, text, emblems, advertising or markings.
- **Blue Hour**. Use case: product-mockup. Asset type: vehicle cutout for a fictional rider’s garage in a touring app. Single modern light metallic Alpine-blue A110-style compact mid-engine sports coupe with its characteristic four round front lights, roof at upper right and nose pointing lower left. Three-quarter front automotive studio photograph from slightly above, wide landscape crop with the full car and breathing room. Dark wheels, natural proportions and soft continuous light. Genuine transparent background with soft contact shadow under tires only. No scene, text, logos, people, or emblems.
- **Rider portraits**. Use case: photorealistic-natural. Asset type: one square 2 by 2 profile photo contact sheet for a social driving app. Exactly four equal square photos with hard boundaries at the center (no gutters, frames, grid lines, whitespace, text or logos). Each photo is a different fictional adult person's tightly framed head-and-shoulders portrait, face centered within their own square and sized for a circle crop. Top left: woman with short dark curly hair and a tan driving jacket, natural smile. Top right: man with short dark hair and light stubble in a black jacket. Bottom left: woman with auburn hair in an olive jacket. Bottom right: man with dark skin and close cropped hair in a charcoal jacket. Natural candid photography, soft early morning light and softly out-of-focus mountain road scenery. Keep faces distinct and legible at avatar size.

</details>
