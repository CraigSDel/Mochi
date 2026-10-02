# App Instructions

## Swift feature architecture

- Organize new feature responsibilities across Domain, Data, and Presentation
  boundaries when a feature needs more than a small local change.
- Keep Domain types framework-independent and define repository protocols
  there. Implement repositories and DTO/entity mappers in the Data boundary.
- Keep SwiftUI views declarative; put state transitions and use-case
  coordination in `@MainActor` ViewModels, with dependencies injected through
  initializers or a feature factory.
- Prefer `async`/`await` and structured concurrency. Translate infrastructure
  failures into domain-specific errors and provide fakes for isolated tests.
- When showing or generating code, include the layer and file path in comments
  and show how dependencies are composed at the application entry point.
- For architecture tests, use SwiftSyntax when it is already available, fail
  with actionable boundary messages, and scope scans to real source roots.
- Test UseCases with mock repositories and ViewModels with mock UseCases using
  async XCTest and `@MainActor` assertions where applicable. Use descriptive
  `test_[subject]_[scenario]_[expectedResult]` names.

## Appearance and theming

- Every screen and shared component must support both macOS light mode and dark mode.
- Use semantic system colors such as `NSColor.labelColor` and appearance-aware theme colors for text, backgrounds, surfaces, borders, and controls.
- Do not combine a fixed light background with semantic foreground colors, or a fixed dark background with semantic foreground colors. Background and foreground colors must change together when the system appearance changes.
- Preserve sufficient contrast for primary text, secondary text, disabled controls, status badges, and card content in both appearances.
- Keep Apple blue as the primary interactive color in both modes. Neutral surfaces should use the app's adaptive `AppTheme` colors.
- Verify all visual changes in both light and dark mode before considering them complete.
