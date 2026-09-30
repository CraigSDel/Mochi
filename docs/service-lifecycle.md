# Service Lifecycle

Service control is the highest-risk area of this application. Changes must
preserve ownership checks, auditable diagnostics, and recoverable state.

## State and ownership

- Treat `ServiceState` as a state machine. Update state, status text, PID,
  endpoint, process record, and log output consistently on every path.
- A listening port without a verified managed-process record is `.external`.
  Never stop or signal it.
- Before signaling a recorded PID, confirm the process is running and its
  command matches the expected command. PID reuse makes an unverified record
  unsafe.
- Stop gracefully first and bound polling/retry work. Failure to stop must be
  visible rather than reported as success.
- Preserve managed process records when the app quits with services running;
  remove stale records only after verification.

## Launching

- Validate executable availability, configuration, port, disk, memory, and
  required network state before launch.
- Log timestamped preflight and launch diagnostics before returning a failure.
  Guidance should name the corrective action without installing or elevating.
- Construct arguments and environments in deterministic functions so their
  security-relevant behavior can be tested directly.
- Cached-only mode must not download. Changing download policy requires an
  explicit user action or confirmation.
- Health checks use the effective bind host for that launch, not necessarily
  the saved bind mode.
- One-time localhost or Wi-Fi fallback affects only that launch. Do not persist
  the override over the user's selected configuration.

Shell scripts use `set -Eeuo pipefail`, quote expansions, validate required
values, and use `exec` for the final long-running process when appropriate.
Keep shell and Swift defaults synchronized and cover changed environment or
argument mappings with tests.
