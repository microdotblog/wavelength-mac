# Wavelength for Mac

Wavelength is a native macOS podcast studio for Micro.blog. Record, edit, and publish microcasts, narrate your posts, and listen to podcasts from Discover.

It mirrors the Expo app in `../wavelength-react`: the same Micro.blog API calls, the same `episode.json` and `segment-N.m4a` episode layout, and the same 128 kbps mono MP3 on publish.

## Requirements

- macOS 26 or later
- Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Getting started

The Xcode project is generated from `project.yml` and isn't checked in. Generate it, then open it:

```bash
xcodegen generate
open Wavelength.xcodeproj
```

Run `xcodegen generate` again after adding or removing files.

The app is signed with the Micro.blog developer team (`3F9MDJ6K4E`), so you need to be a member of that team in Xcode to build it.

## Tests

```bash
xcodebuild -project Wavelength.xcodeproj -scheme Wavelength -destination 'platform=macOS' test
```

## Layout

- `Wavelength/API` holds the Micro.blog clients (IndieAuth, Micropub, Discover).
- `Wavelength/Stores` holds the observable app state, one store per feature.
- `Wavelength/Storage` holds the episode and narration folders and the Keychain.
- `Wavelength/Audio` holds recording, editing, waveform analysis, MP3 encoding, and playback.
- `Wavelength/Views` holds the SwiftUI screens.
- `Packages/LAME` is LAME 3.100, built from source for MP3 encoding.
