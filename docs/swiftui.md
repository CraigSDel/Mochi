# SwiftUI and AppKit

- Keep the app entry point responsible for scene composition and top-level
  ownership. Pass shared `@StateObject` instances into child views explicitly.
- Observable UI state belongs on `@MainActor`. Use `@Published private(set)`
  when only the owning type may change it.
- Keep `body` declarative. Move policy, process inspection, persistence, and
  non-trivial transformations out of views.
- Extract a component when it has a coherent UI role or when extraction makes
  state and accessibility easier to reason about; avoid one-off wrapper types.
- Use `AppTheme` and semantic system colors for foregrounds, backgrounds,
  surfaces, borders, disabled states, and status tones. Verify light and dark
  appearances together.
- Keep Apple blue as the primary interaction color. Status color must not be
  the only way information is communicated.
- Provide accessible labels for icon-only controls and status symbols. Preserve
  usable keyboard navigation, focus behavior, and control hit targets.
- Destructive, network-exposing, download-enabling, and unverified-memory
  actions require clear confirmation at the point of action.
- UI controls that edit a launch configuration remain disabled while that
  service is starting, running, or stopping.
- Use AppKit only for macOS capabilities that SwiftUI does not express cleanly,
  such as termination negotiation or native alerts. Keep bridging localized.

For visual changes, inspect both appearances and relevant compact/window-size
states. A successful compile does not validate contrast, truncation, or layout.
