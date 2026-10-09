# Troubleshooting

- **Runtime not installed:** Install the named dependency outside the app and
  refresh the service status.
- **Tailscale not connected:** Run `tailscale up`, confirm it has an IPv4
  address, and retry, or select Localhost on the service screen.
- **Model missing:** Select **Allow downloads** on the service screen, or
  install the model outside the controller. **Cached only** uses llama.cpp
  offline mode.
- **Port occupied:** Stop the external process or choose another port on the
  service screen.
- **Service fails during startup:** Open that service and inspect its log for
  the exact runtime error. Preflight and launcher failures also display an
  immediate alert with corrective guidance and a **Reveal Log** button.
- **Recommendations unavailable:** Registry or network failures do not affect
  model controls. Use **Check Now** after connectivity returns.

Every start attempt appends timestamped diagnostics to the service log before
checking dependencies, ports, memory, disk space, or Tailscale. Earlier
attempts remain available after a retry or app relaunch.
