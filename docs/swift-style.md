# Swift Style

- Follow the Swift API Design Guidelines and the conventions already present
  in adjacent files. Prefer clarity at the call site over terse names.
- Use four-space indentation, UTF-8, and no wildcard-style re-exports.
- Keep authored Swift, shell, and configuration files at or below 300 lines.
  A new cohesive type or extension belongs in a focused file when a file grows.
- Prefer value types for models and configuration. Use a class when identity,
  observable state, delegation, or reference semantics are required.
- Use `let` by default and narrow visibility (`private` or `private(set)`) when
  mutation is an implementation detail.
- Model finite states with enums and use exhaustive switches. Avoid parallel
  booleans that can represent contradictory service states.
- Preserve `Sendable` conformance for values that cross concurrency boundaries.
  Do not add `@unchecked Sendable` without documenting and testing the safety
  argument.
- Use `async`/`await` for asynchronous workflows. Avoid detached tasks unless
  the work truly has no actor or lifetime relationship to its caller.
- Prefer `guard` for invalid state and early exits. Surface operational errors
  with enough context for the UI or log to tell the user what to do next.
- Use comments to explain constraints or non-obvious safety decisions, not to
  narrate straightforward code. Do not leave commented-out implementations.
- Keep formatting changes scoped to touched code. Do not mix broad cleanup
  with a behavioral change.

Long expressions should be expanded into named intermediate values when that
improves debugging or makes policy decisions visible. Do not pack unrelated
statements onto one line merely to satisfy the line-count gate.
