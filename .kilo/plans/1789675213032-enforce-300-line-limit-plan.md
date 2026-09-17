# Enforce 300-Line Code File Limit - Implementation Plan

## Overview

Refactor oversized files and add automated line-length enforcement to keep all authored code files at or below 300 physical lines.

## Files Exceeding 300 Lines

| File | Lines | Action |
|------|-------|--------|
| `Sources/LocalAIController/Models.swift` | 308 | Split into `ServiceModels.swift` + `RecommendationModels.swift` |
| `Tests/LocalAIControllerTests/ControllerTests.swift` | 565 | Split into 6 topical test files |

## UI Reorganization (Logical Split)

The UI code (~880 lines across 7 files) will be organized into 6 cohesive modules matching the specified responsibilities. Current files already align well:

| Module | Current File(s) | Target File |
|--------|-----------------|-------------|
| App lifecycle and delegate | `LocalAIControllerApp.swift` | `LocalAIControllerApp.swift` (50 lines) ✓ |
| Root navigation and Overview | `MainView.swift` | `MainView.swift` (212 lines) ✓ |
| Service details, configuration, model selectors, logs | `ServiceViews.swift` | `ServiceViews.swift` (260 lines) ✓ |
| Recommendations | `RecommendationsView.swift` | `RecommendationsView.swift` (100 lines) ✓ |
| Menu-bar and Settings views | `MenuAndSettingsViews.swift` | `MenuAndSettingsViews.swift` (62 lines) ✓ |
| Shared launch confirmations/actions | `LaunchActions.swift` | `LaunchActions.swift` (50 lines) ✓ |
| Shared UI components | `VisualStyle.swift` | `VisualStyle.swift` (196 lines) ✓ |

**Action**: Verify each stays ≤300 lines; no splitting needed currently.

---

## 1. Split `Models.swift` (308 → 2 files)

### `Sources/LocalAIController/ServiceModels.swift` (~180 lines)
Service/configuration models:
- `ServiceID`, `SidebarDestination`, `ServiceState`, `StatusTone`
- `BindMode`, `DownloadPolicy`
- `LlamaLaunchConfiguration`, `OllamaLaunchConfiguration`, `ServiceLaunchConfiguration`
- `ConfigurationIssue`, `LaunchWarning`
- `ServiceDefinition`, `ServiceSnapshot`, `ManagedProcessRecord`, `ServiceFailure`
- `ControllerPolicy`

### `Sources/LocalAIController/RecommendationModels.swift` (~130 lines)
Recommendation/model-inventory types:
- `RecommendationRole`, `ModelRuntime`
- `DiscoveredModel`, `ModelAvailability`, `ModelOption`
- `Compatibility`, `ModelRecommendation`
- `ModelInventoryScanner`, `ModelOptionBuilder`

**Visibility changes**: Change `private` to `internal` (module scope) where cross-file access is needed. No public API expansion.

---

## 2. Split `ControllerTests.swift` (565 → 6 files + shared support)

### New Test Files (all in `Tests/LocalAIControllerTests/`)

| File | Test Classes | Est. Lines |
|------|--------------|------------|
| `PolicyRoutingTests.swift` | `ControllerPolicyTests`, `SidebarDestinationTests`, `ServiceStatePresentationTests` | ~100 |
| `ModelDiscoveryTests.swift` | `ModelInventoryScannerTests`, `ModelOptionBuilderTests` | ~80 |
| `DownloadPolicyTests.swift` | `ModelDownloadPolicyTests` | ~50 |
| `StartupValidationTests.swift` | `StartupDiagnosticsTests` (validation/launch config tests) | ~150 |
| `ProcessLifecycleTests.swift` | `StartupDiagnosticsTests` (process lifecycle/networking tests) | ~120 |
| `RecommendationStoreTests.swift` | `RecommendationStoreResilienceTests` | ~50 |
| `TestSupport.swift` | `FakeProbe`, `FakeProcessFactory`, `StubRecommendationProvider` | ~80 |

**Multiple test targets**: Update `Package.swift` to define separate test targets for each suite (or logical groupings), all depending on `LocalAIController`.

---

## 3. Line-Length Check Script

### `check_code_line_lengths.sh` (portable bash)

**Behavior**:
- Scan authored code files with extensions: `.swift`, `.sh`, `.py`, `.js`, `.ts`, `.c`, `.cpp`, `.h`, `.hpp`, `.m`, `.mm`, `Package.swift`, `.json`, `.yaml`, `.yml`, `.toml`
- Exclude: `.git`, `.build`, `dist`, `*.xcodeproj`, `*.xcworkspace`, `AppResources`, `*.png`, `*.icns`, `*.md`
- Count physical lines (`wc -l`)
- Fail with: `<path>:<line_count>` for each file >300 lines
- Exit code 1 if any violations

---

## 4. Integration Points

### `build_app.sh`
Add at start:
```bash
"$ROOT/check_code_line_lengths.sh" || exit 1
```

### Repository-Hygiene XCTest
New test file: `Tests/LocalAIControllerTests/RepositoryHygieneTests.swift`
- Single test invoking `check_code_line_lengths.sh` via `Process`
- Fails if any authored file exceeds 300 lines

---

## 5. Package.swift Updates

Add multiple test targets:
```swift
.targets: [
    .executableTarget(name: "LocalAIController"),
    .testTarget(name: "PolicyRoutingTests", dependencies: ["LocalAIController"]),
    .testTarget(name: "ModelDiscoveryTests", dependencies: ["LocalAIController"]),
    .testTarget(name: "DownloadPolicyTests", dependencies: ["LocalAIController"]),
    .testTarget(name: "StartupValidationTests", dependencies: ["LocalAIController"]),
    .testTarget(name: "ProcessLifecycleTests", dependencies: ["LocalAIController"]),
    .testTarget(name: "RecommendationStoreTests", dependencies: ["LocalAIController"]),
    .testTarget(name: "RepositoryHygieneTests", dependencies: ["LocalAIController"]),
]
```

---

## 6. Validation Plan

1. **Run line-limit script directly** — verify all authored files ≤300 lines
2. **Fixture test** — create temp files at 300/301 lines, verify pass/fail with diagnostic
3. **Full Swift test suite** — `swift test` passes (file moves + visibility changes preserve behavior)
4. **Release build** — `./build_app.sh` succeeds, plist valid, code-signed
5. **Git hygiene** — `git diff --check` clean

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Cross-file `private` references in Models.swift | Audit all `private` usages; promote to `internal` only where needed |
| Test target multiplication increases build time | Acceptable for this project size; enables parallel test runs |
| Line-count script false positives (generated files) | Exclude `.build`, `dist`, and known generated paths |
| Shell script portability | Use POSIX-compliant bash; test on macOS |

---

## Task Order

1. Create `check_code_line_lengths.sh`
2. Update `build_app.sh` to run the check
3. Split `Models.swift` → `ServiceModels.swift` + `RecommendationModels.swift`
4. Update imports in all affected source files
5. Split `ControllerTests.swift` into 7 test files
6. Update `Package.swift` with multiple test targets
7. Add `RepositoryHygieneTests.swift`
8. Verify UI files remain ≤300 lines (no changes needed)
9. Run validation plan steps