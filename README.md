# CRT Lens

Curved glass, phosphor, and glow for the Mac apps you already use.

I miss the screen as much as the shows and games. CRT Lens puts an ordinary Mac window behind rounded glass, with the texture and depth I remember from old televisions. I use it for watching Dragon Ball Z, playing retro games, and seeing familiar things through a different screen.

[**Download the Mac preview**](https://github.com/thirdPolarity/window-crt-lens/releases/tag/v0.1.0-preview.1) · [Build from source](#build-from-source)

![CRT Lens over an Infuse window playing Dragon Ball Z, with the desktop visible around the curved glass](docs/images/crt-lens-desktop.webp)

## Try it

The download is an **Apple silicon preview for macOS 14 or later**. It is ad-hoc signed and **not notarized by Apple**. This is a personal experiment, with testing on one Mac rather than a broad compatibility guarantee.

1. Download `CRT-Lens-macOS-AppleSilicon.zip` from the release above and unzip it.
2. Move **Window CRT Lens.app** to Applications, then open it. If macOS blocks an unverified developer, review [Apple's instructions for opening an app you trust](https://support.apple.com/en-us/102445). Building it yourself is also an option.
3. Allow Screen Recording in **System Settings → Privacy & Security** when prompted. macOS may call this **Screen & System Audio Recording**. Quit and reopen the app after granting access.
4. Choose a visible window and select **Start Lens**. Click the **◉** menu bar icon to change its look, adjust the glass, choose another window, or stop the lens.

Clicks and typing pass through to the original app. The lens follows its position and size, appears while that app is in the foreground, and can follow it into native fullscreen. It does not replace the player or emulator underneath.

To update, quit CRT Lens before replacing the app. To uninstall, quit and remove the app from Applications; diagnostic logs can also be removed from `~/Library/Logs/Window CRT Lens/`.

## Shape the glass

Seven looks range from subtle curves to bulbous consumer tubes, arcade glass, and an aperture grille. Controls adjust source zoom, screen corners, outer shell corners, and edge softness. Different profiles combine scanlines, phosphor masks, glow, halation, tint, and curvature.

ShaderGlass and Mega Bezel helped shape the idea. My own preference is for rounded corners and a picture with a little volume. Turning up the geometry in Pokémon Silver made familiar paths and buildings feel closer to the place I imagined as a child.

## Build from source

You need macOS 14 or later and Xcode Command Line Tools with Swift 5.9 or later. The app uses Apple frameworks only; there are no external Swift package dependencies.

```sh
git clone https://github.com/thirdPolarity/window-crt-lens.git
cd window-crt-lens
swift test
./Scripts/build-app.sh
```

The script produces `dist/Window CRT Lens.app.zip` for the Mac's current architecture. Unzip it and move the app to Applications. Intel builds have not been tested; the downloadable preview is arm64 only.

The app uses AppKit for its passive overlay, ScreenCaptureKit for the selected window's composited display region, and a purpose-built Metal shader. It captures the visible region, including what shows through translucent windows. It does not modify other apps, load RetroArch shader files, or install login items.

The build script stages and ad-hoc signs in a temporary directory to avoid cloud-folder metadata invalidating the signature. The preview keeps the development bundle ID `com.rey.window-crt-lens.test` and its stable signing requirement for Screen Recording permission continuity. This is not a Developer ID distribution signature.

## Privacy and troubleshooting

Screen Recording permission is required for live screen capture. Processing stays on the Mac. The app does not record video, save captured frames, send screen content anywhere, or contact a cloud service.

Local diagnostic logs are written to `~/Library/Logs/Window CRT Lens/`. **◉ → Diagnostics** has **Mark Mirror Glitch**, **Mark Looks Normal**, and **Open Logs**. Marking a run saves a timestamp, not a screenshot.

Logs include app paths, process and window IDs, selected app bundle IDs, geometry, capture health, errors, and appearance settings. They do not include window titles, screen pixels, typed text, command-line arguments, or environment dumps, and are never uploaded automatically. Files are owner-readable, rotate at 2 MiB, and retain up to 60 files. Review paths and app identifiers before sharing a log.

If the picker is empty after permission was granted, quit and reopen the app with the target window visible. If the lens mirrors itself, mark the incident, choose **Stop Lens**, and quit any duplicate copies. Build 3 fixes a startup case where the app was missing from its own capture exclusion list; capture now refuses to start unless self-exclusion is available.

The capture follows visible screen contents, so obscuring the source window affects the picture. Protected video may not be capturable. Display changes, Spaces transitions, and different display scales need further testing. Use **Stop Lens** to return to the original app at any time.

## Influences and credits

- [ShaderGlass](https://github.com/mausimus/ShaderGlass) inspired applying shaders to everyday app windows.
- [Mega Bezel](https://github.com/HyperspaceMadness/Mega_Bezel) inspired the treatment of curved glass, phosphor, and glow.
- [Libretro's CRT shader guide](https://docs.libretro.com/shader/crt/) provided references for CRT rendering concepts.
- The Rooftop Arcade profile's axis-aware curvature was informed by [Drigax's Rooftop Rampage shader](https://github.com/Drigax/RooftopRampage_Source/blob/master/public/Shaders/crt.fragment.fx). The upstream package declares ISC, not MIT. This app does not bundle that shader file.

The screenshot shows actual use with Infuse. Dragon Ball Z imagery and the desktop artwork belong to their respective rights holders; they are not included in the app.

No open-source license has been selected for the app source. Publishing the repository does not place its code or the screenshot artwork in the public domain.
