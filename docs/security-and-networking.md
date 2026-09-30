# Security and Networking

- Localhost binds to `127.0.0.1` and is the safest fallback.
- Tailscale binds to the selected `100.x.x.x` address. A Tailscale-bound service
  is not assumed to be available through localhost.
- LAN/Wi-Fi binding listens beyond the local machine and exposes an
  unauthenticated model API. Require confirmation for every launch and display
  the reachable address clearly.
- A failed or relayed Tailscale diagnostic is a warning about connectivity, not
  proof of one specific firewall, policy, or peer failure.
- Never silently fall back from Tailscale to LAN. Localhost and Wi-Fi fallbacks
  are explicit one-time user choices.
- Validate ports in the non-privileged range and detect collisions across a
  multi-service start before launching any member of the group.
- Treat custom model identifiers and remote metadata as untrusted input. Pass
  process arguments as arrays and environment entries, never by constructing a
  shell command string.
- Do not log secrets, tokens, complete private environment data, or sensitive
  file content. Logs should contain service IDs, endpoints, process state, and
  actionable failures needed for diagnosis.
- The application never runs privileged commands and never installs runtime
  dependencies on the user's behalf.

Any change that broadens exposure, weakens a confirmation, changes process
identity checks, or introduces credential handling needs focused tests and an
explicit security note in the handoff.
