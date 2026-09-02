# Window CRT Lens

An isolated macOS experiment that tracks one user-selected window, captures its composited display region with ScreenCaptureKit, and places a Metal CRT lens directly over it.

- The overlay ignores mouse events and cannot become the key or main window.
- Keyboard and mouse input continue to go to the real application underneath.
- Moving or resizing the source window updates both the overlay and capture region.
- Capturing the composited region preserves what is visible behind translucent source windows instead of replacing transparency with a flat fill.
- `◉` > `CRT appearance…` opens live controls for source zoom, captured screen radius, outer lens radius, and anti-aliased edge softness. Values persist between launches.
- CRT zoom enlarges only the sampled application image; it does not resize the real window or stretch the outer lens shell.
- `◉` > `Look` includes seven deliberately different profiles: the original Subtle, Glassy, and Bulbous looks plus Deep Consumer Tube, Rooftop Arcade, PVM Aperture Grille, and Neutral Terminal.
- The newer profiles add axis-aware cubic tube geometry, aperture-grille/shadow-mask/slot-mask phosphors, brightness recovery, configurable glass response, and an optional four-tap halation pass. Profiles without halation retain the original three texture taps; profiles with it use seven.
- Scanlines and phosphor masks remain fixed to the simulated glass instead of moving with source zoom or curvature. The original profiles use a two-pixel phosphor pitch to reduce display-scale moiré while retaining visible CRT texture.
- The screen mask replaces desktop pixels exposed by macOS window corners with the CRT shell before the image is curved.
- The lens is only shown while the selected application's window is in the foreground, so it does not follow the user into unrelated Spaces or applications.
- Native macOS fullscreen is supported: the passive overlay can follow the selected app into its fullscreen Space, and it stays hidden during fullscreen/resize geometry transitions until ScreenCaptureKit catches up.
- It does not load or modify RetroArch, ES-DE, Dock, Finder, wallpaper, login items, audio, or camera settings.
- It does not record, stream, or save captured frames.

Build with `Scripts/build-app.sh`. It stages and signs outside Documents, then writes `dist/Window CRT Lens.app.zip`; this avoids File Provider attaching Finder metadata that invalidates app signatures. For this local test build, the script uses a stable bundle-identifier-only designated requirement so macOS can associate rebuilt copies with the existing Screen Recording approval. This is intentionally a local-development signing setup, not a distribution signature. The currently installed test copy is `/Users/rey/Applications/Window CRT Lens.app`.

Screen Recording permission is required because macOS treats any live window capture as screen recording.

Set `WINDOW_CRT_DIAGNOSTICS=1` before launching the executable to emit once-per-second ScreenCaptureKit frame counters while diagnosing capture stalls.

## Technique references

- The Rooftop Arcade profile is informed by Nick Barlow's axis-aware cubic UV remapping study and the MIT-licensed Rooftop Rampage shader source: <https://babylonjs.medium.com/retro-crt-shader-a-post-processing-effect-study-1cb3f783afbc> and <https://github.com/Drigax/RooftopRampage_Source/blob/master/public/Shaders/crt.fragment.fx>.
- The phosphor, halation, glow, and geometry split follows the concepts documented by Libretro's CRT shader guide while remaining a purpose-built, single-pass Metal implementation: <https://docs.libretro.com/shader/crt/>.
- The local Mega Bezel installation was inspected only as a behavioral reference. This app does not load, copy, or modify Mega Bezel or RetroArch files.
