# Window CRT Lens

An isolated macOS experiment that tracks one user-selected window, captures its composited display region with ScreenCaptureKit, and places a Metal CRT lens directly over it.

- The overlay ignores mouse events and cannot become the key or main window.
- Keyboard and mouse input continue to go to the real application underneath.
- Moving or resizing the source window updates both the overlay and capture region.
- Capturing the composited region preserves what is visible behind translucent source windows instead of replacing transparency with a flat fill.
- `◉` > `CRT appearance…` opens live controls for source zoom, captured screen radius, outer lens radius, and anti-aliased edge softness. Values persist between launches.
- CRT zoom enlarges only the sampled application image; it does not resize the real window or stretch the outer lens shell.
- The screen mask replaces desktop pixels exposed by macOS window corners with the CRT shell before the image is curved.
- The lens is only shown while the selected application's window is in the foreground, so it does not follow the user into unrelated Spaces or applications.
- It does not load or modify RetroArch, ES-DE, Dock, Finder, wallpaper, login items, audio, or camera settings.
- It does not record, stream, or save captured frames.

Build with `Scripts/build-app.sh`. It stages and signs outside Documents, then writes `dist/Window CRT Lens.app.zip`; this avoids File Provider attaching Finder metadata that invalidates app signatures. For this local test build, the script uses a stable bundle-identifier-only designated requirement so macOS can associate rebuilt copies with the existing Screen Recording approval. This is intentionally a local-development signing setup, not a distribution signature. The currently installed test copy is `/Users/rey/Applications/Window CRT Lens.app`.

Screen Recording permission is required because macOS treats any live window capture as screen recording.

Set `WINDOW_CRT_DIAGNOSTICS=1` before launching the executable to emit once-per-second ScreenCaptureKit frame counters while diagnosing capture stalls.
