# App Instructions

## Appearance and theming

- Every screen and shared component must support both macOS light mode and dark mode.
- Use semantic system colors such as `NSColor.labelColor` and appearance-aware theme colors for text, backgrounds, surfaces, borders, and controls.
- Do not combine a fixed light background with semantic foreground colors, or a fixed dark background with semantic foreground colors. Background and foreground colors must change together when the system appearance changes.
- Preserve sufficient contrast for primary text, secondary text, disabled controls, status badges, and card content in both appearances.
- Keep Apple blue as the primary interactive color in both modes. Neutral surfaces should use the app's adaptive `AppTheme` colors.
- Verify all visual changes in both light and dark mode before considering them complete.
