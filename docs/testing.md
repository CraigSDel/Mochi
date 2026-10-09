# Testing

Tests use XCTest and mirror externally observable behavior. Keep tests
deterministic and independent of installed models, live Tailscale peers, active
ports, the user's defaults domain, and public registries.

- Put tests in `Tests/LocalAIControllerTests/` and name classes after the
  behavior or production type under test.
- Use descriptive `test...` method names that state the condition and expected
  outcome.
- Reuse `FakeProbe`, `FakeProcessFactory`, and provider stubs. Extend a focused
  fake when a boundary needs control instead of adding sleeps or hitting a live
  dependency.
- Use a unique temporary directory and `UserDefaults(suiteName:)` for tests that
  persist state. Clean up when data can outlive the test process.
- Mark UI-state and manager tests `@MainActor`.
- Assert state and user-visible diagnostics, not private implementation steps.
  For lifecycle work, cover the service state, process record, endpoint, log,
  and failure guidance that users depend on.
- Keep asynchronous waits bounded. Prefer a controllable fake or eventual
  condition over fixed delays; where a real child process is essential, ensure
  the test stops it even after assertion failures.
- Add regression coverage for bug fixes and legacy persisted formats.
- Test each effectful collaborator independently through its protocol. Cover
  successful results, operational failures, cancellation for async workflows,
  persistence failures, missing dependencies, and safety/ownership rejection.
- Keep observable facade tests focused on published state and user-visible
  diagnostics; do not assert private collaborator call sequences.
- Architecture tests should reject direct persistence, process, filesystem,
  or networking imports in presentation/domain code and should report the
  source file and violated boundary clearly.
- Do not weaken assertions or production safety checks to make a flaky test
  pass.

During development, run a focused filter when useful:

```bash
swift test --filter StartupValidationTests
```

Before handoff, run:

```bash
./check_code_line_lengths.sh
swift test
```

Run `./build_app.sh` when app packaging, resources, launch scripts, or release
build behavior changes.
