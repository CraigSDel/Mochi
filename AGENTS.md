# Local AI Controller — Swift/macOS

## Reusable Swift architecture guidance

For Swift feature creation or refactoring, apply the project-local
`skills/clean-architecture-swift/SKILL.md` guidance: Clean Architecture and
MVVM, protocol-based dependency inversion, modern concurrency, explicit domain
errors, and isolated tests. Treat it as a design guide within this repository's
established `Sources/LocalAIController` layout; the rules below for macOS
lifecycle, security, persistence compatibility, and file size take precedence
where they are more specific.

For architecture-focused test creation or review, also apply
`skills/swift-architecture-quality/SKILL.md`. Use static boundary checks only
when the repository has corresponding layered source roots, and keep all tests
compatible with the existing SwiftPM target and test conventions.

Standards: [`docs/swift-style.md`](docs/swift-style.md) ·
[`docs/architecture.md`](docs/architecture.md) ·
[`docs/swiftui.md`](docs/swiftui.md) ·
[`docs/service-lifecycle.md`](docs/service-lifecycle.md) ·
[`docs/security-and-networking.md`](docs/security-and-networking.md) ·
[`docs/testing.md`](docs/testing.md) ·
[`docs/agentic-workflows.md`](docs/agentic-workflows.md)

## Stack

Swift 6 · Swift Package Manager · SwiftUI + AppKit · macOS 14+ · XCTest.

The repository builds one executable target, `LocalAIController`, and one test
target, `LocalAIControllerTests`. It packages a locally signed macOS app with
`build_app.sh` and manages local `llama.cpp`, Ollama, and Tailscale processes.

## Repository map

```text
Sources/LocalAIController/       application code
Tests/LocalAIControllerTests/   unit and integration-style tests with fakes
AppResources/                   Info.plist and application icon
start_llama_network.sh          llama.cpp launcher
start_ollama_network.sh         Ollama launcher
build_app.sh                    release build and app-bundle packaging
check_code_line_lengths.sh      250-line authored-file quality gate
```

Add a focused source file when a type has a distinct responsibility. Do not
turn this small package into a speculative multi-module architecture.

## Complexity and collaborator rules

- Treat responsibility mixing as the primary complexity signal, not only line
  count. Split a type when it combines observable state with two or more of
  persistence, OS/process access, networking, model discovery, orchestration,
  or notification delivery.
- Keep observable `@MainActor` types focused on state and intent handling.
  Inject use cases and small protocols for effectful work; do not make views
  or view models own filesystem, process, URLSession, or UserDefaults details.
- Put blocking filesystem scans, process waits, command execution, and runtime
  discovery behind async or actor-backed collaborators. A protocol is required
  when a boundary needs an independent fake or has multiple implementations.
- Preserve one authoritative path for state transitions, persistence formats,
  launcher arguments, environment variables, and process ownership checks.
- For every new collaborator, add isolated tests for success, failure,
  cancellation where relevant, persistence compatibility, and missing runtime
  dependencies. Keep integration tests for shell/runtime contracts.
- Files at or below 250 lines are still candidates for splitting when their
  responsibilities are unrelated. Never compress code or hide dependencies to
  satisfy the line-count gate.

## Gotchas

- UI and observable application state run on `@MainActor`. Keep blocking
  process, file, and network work off the main actor.
- A port listener is not automatically owned by this app. Preserve the
  distinction between managed, external, stopped, and failed services; never
  terminate a process unless its persisted record and command identity match.
- Tailscale, localhost, and LAN binding have different security semantics.
  LAN exposes unauthenticated APIs and must retain explicit user confirmation.
- Configuration fields are locked while a service is active. One-time bind
  overrides must not silently rewrite the saved configuration.
- The controller does not install dependencies or elevate privileges. Missing
  tools must produce actionable guidance.
- Use semantic, appearance-aware colors. Every view must remain readable in
  both light and dark mode; see [`instructions.md`](instructions.md).
- Keep authored code files at or below 250 lines. Split by responsibility
  instead of compressing code to evade the check.
- Preserve backward compatibility for persisted `Codable` records and
  `UserDefaults` keys unless a migration is part of the change.

## Definition of done

Review every user-visible or persisted configuration field through the complete path: UI → model → environment/arguments → launcher → runtime. Flag fields that are stored or displayed but not consumed.

Treat process ownership as an exact identity check. Never consider a process owned solely because its command contains `bash`, a runtime name, or a partial executable name. Verify executable identity, launcher path, arguments, and PID reuse.

Keep synchronous process waits, `lsof`, `ps`, filesystem scans, and model discovery off `@MainActor`. Require injected async/actor-backed probes and responsiveness-focused tests.

Launcher scripts must not install dependencies, invoke `sudo`, alter system configuration, or broaden network exposure. Missing dependencies must fail with actionable guidance.

Require tests for shell/Swift contract synchronization whenever configuration fields, environment variables, ports, bind modes, download policies, or runtime tuning settings change.

Treat passing unit tests as insufficient when scripts or external runtimes are involved; perform static contract inspection and targeted integration checks.

Run the narrowest relevant test while iterating, then run:

```bash
./check_code_line_lengths.sh
swift test
```

For changes to packaging, bundled resources, entitlements, or launch scripts,
also run `./build_app.sh`. Report any check that could not be run.
