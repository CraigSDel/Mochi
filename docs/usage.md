# Usage

## Use the controller

The Services sidebar shows each runtime and its current state:

- **Start** launches one service with the configuration shown on its screen.
- **Stop** gracefully stops a service launched by the controller.
- **Start All** validates and uses the saved configuration for the three llama.cpp services.
- **Stop All** stops all verified controller-managed services.
- **Copy Logs**, **Clear**, and **Reveal** manage each service's local log.

If a process is already using a configured port but was not launched by the
controller, it is marked **External** and will not be terminated. See
[Service Lifecycle](service-lifecycle.md) for the state and process-ownership
rules.

When quitting with managed services active, choose whether to keep them
running, stop them, or cancel quitting.

## Launch configuration

The default ports are:

| Service | Port |
| --- | ---: |
| Code autocomplete | `11435` |
| Workspace embeddings | `11436` |
| llama.cpp chat | `11437` |

Select a service to configure its port, network binding, download policy, and
model selection directly above the Start button. Model menus combine cached
Hugging Face GGUF files with launchable catalog recommendations; local,
role-matched choices appear first. Use **Rescan** after installing a model
outside the app. Expand **Advanced** to tune context size, GPU layers, or
enter a custom model. Configurations are saved per service between launches,
and **Reset to Defaults** restores the values listed by the bundled launcher
scripts.

Selecting a catalog model marks it as requiring a download. If the service is
set to **Cached only**, Start asks before switching that service to **Allow
downloads**; canceling leaves the configuration unchanged.

The available bind modes are **Tailscale**, **Localhost**, and **Local
network**. Local-network mode exposes an unauthenticated API and therefore
requires an explicit confirmation on every launch. Custom model identifiers
also require confirmation because their memory requirements have not been
verified. Fields are locked while their service is active; stop the service
before editing its next-launch configuration. See [Security and
Networking](security-and-networking.md) for exposure and bind-mode guidance.

The Overview's **Test Tailscale** action selects an online peer and reports
whether connectivity is direct, relayed, or unreachable. Tailscale-bound
service launches run the same test first. Relayed or failed tests produce a
warning but do not prevent an acknowledged launch; a failed ping can indicate
a firewall, tailnet policy, or peer availability problem rather than proving a
specific cause.

When that warning appears, **Start Locally** launches Tailscale-configured
services on `127.0.0.1` for that run without changing their saved
configuration. A **Start on Wi-Fi** option is also shown when Wi-Fi has an
active IPv4 address; it listens on all local interfaces and displays the Wi-Fi
address, so other devices on that network can connect. This mode exposes the
unauthenticated APIs to the local network.

A Tailscale-bound service listens only on its `100.x.x.x` address and is not
also available through localhost. Running service cards, service details, and
logs show the complete endpoint where each model is available.

The separate Settings window provides the optional **Launch at Login** setting,
disabled by default.

## Model recommendations

Select **Recommendations** in the sidebar to view read-only suggestions from
Hugging Face GGUF listings. The controller checks at most once per day and
also provides a manual **Check Now** button.

Only models with complete metadata, a known llama.cpp-compatible architecture,
and a conservative fit for this Mac can be labeled **Compatible**. Unknown,
oversized, and gated models are shown as **Unverified**. Cloud-only and
multimodal models are rejected and stay visible in the list with the reason.

Capability comes from signals that are actually read:

- **Hugging Face** — the model's `pipeline_tag` and tags, plus any `mmproj`
  projector file in a downloaded snapshot.

Models this controller manages are text-only, so an installed multimodal model
is reported as **Multimodal (not supported)** and is not offered in a launch
picker. A model already saved in a configuration is still listed, so switching
to a supported model is always possible.

Recommendations are informational only. They do not include download, install,
or launch actions.
