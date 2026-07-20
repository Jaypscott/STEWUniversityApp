# STEWUniversity for iPhone

Native SwiftUI client targeting iOS 26 and later.

The Games destination contains offline Harmonic Sudoku and Melody Memory. Band is an authenticated private collaboration space with a customizable logo, accent color, featured project, and shared mood board; every other destination remains anonymous.

## Open and run

1. Open `STEWUniversity.xcodeproj` in Xcode.
2. Select the `STEWUniversity` scheme and an iPhone simulator.
3. Build and run. Band uses `BAND_API_BASE_URL` from `Info.plist`; the generated project defaults to the stable Render hostname.

For simulator-only Band states, add one launch argument:

- `--ui-testing-band-signed-out` shows the account gate.
- `--ui-testing-band-empty` shows the real empty create/join experience.
- `--ui-testing-band-demo` injects a populated owner workspace. Demo content is never selected in production.

Before installing on a physical device, choose your Apple Development Team and confirm that Sign in with Apple, Push Notifications, and Associated Domains are enabled for `com.stewuniversity.ios`. The checked-in entitlement points at `stew-university-backend.onrender.com`; change both the entitlement and backend `PUBLIC_BASE_URL` if the production hostname changes.

Regenerate the project after adding source files with:

```sh
ruby generate_project.rb
```

The OpenAI, Apple server, APNs, and R2 keys remain on the backend. Band keeps its rotating refresh token in Keychain, its access token in memory, and its last selected Band ID locally per user. Background media tasks copy selected files into managed temporary storage and restore their task/asset mappings after relaunch.
