# Local AI Controller

Local AI Controller is a native macOS menu-bar and desktop application for
starting, stopping, and monitoring the local model services configured in this
repository.

The app manages:

- Qwen chat through `llama.cpp`
- Qwen code autocomplete through `llama.cpp`
- Nomic workspace embeddings through `llama.cpp`
- Ollama and its configured local models

## Requirements

- Apple Silicon Mac running macOS 14 or later
- Xcode command-line tools or Xcode with Swift 6
- Tailscale installed and connected when using the default Tailscale bind mode
- `llama.cpp` for the three llama.cpp services
- Ollama for the Ollama service

Install runtime dependencies separately with Homebrew if needed:

```bash
brew install llama.cpp ollama tailscale
```

Port checks use the `lsof` utility included with macOS at `/usr/sbin/lsof`;
installing a separate Homebrew copy is not required.

Connect Tailscale before starting services:

```bash
tailscale up
```

The controller never installs dependencies or runs privileged commands. Each
service screen controls whether startup uses cached models only or explicitly
allows downloads for missing configured models.

## Build the app

From this repository, run:

```bash
./build_app.sh
```

The locally signed application will be created at:

```text
dist/Local AI Controller.app
```

## Open the app

Open it from Finder by double-clicking `dist/Local AI Controller.app`, or run:

```bash
open "dist/Local AI Controller.app"
```

If macOS blocks the first launch, Control-click the app in Finder, choose
**Open**, and confirm **Open**. The app is locally signed and is not notarized
for public distribution.

The app opens a management window and adds a CPU icon to the macOS menu bar.
If the main window is closed, use that menu-bar icon and select **Open
Controller**.

## Use the controller

The Services sidebar shows each runtime and its current state:

- **Start** launches one service with the configuration shown on its screen.
- **Stop** gracefully stops a service launched by the controller.
- **Start All** validates and uses the saved configuration for the three llama.cpp services; Ollama is started separately.
- **Stop All** stops all verified controller-managed services.
- **Copy Logs**, **Clear**, and **Reveal** manage each service's local log.

If a process is already using a configured port but was not launched by the
controller, it is marked **External** and will not be terminated.

When quitting with managed services active, choose whether to keep them
running, stop them, or cancel quitting.

## Launch configuration

The default ports are:

| Service | Port |
| --- | ---: |
| Ollama | `11434` |
| Code autocomplete | `11435` |
| Workspace embeddings | `11436` |
| llama.cpp chat | `11437` |

Select a service to configure its port, network binding, download policy, and
model selection directly above the Start button. Model menus combine locally
downloaded Ollama manifests and cached Hugging Face GGUF files with launchable
catalog recommendations; local, role-matched choices appear first. Use
**Rescan** after installing a model outside the app. Expand **Advanced** to tune
context size, GPU layers, Ollama runtime settings, or enter a custom model.
Configurations are saved
per service between launches, and **Reset to Defaults** restores the values
listed by the bundled launcher scripts.

Selecting a catalog model marks it as requiring a download. If the service is
set to **Cached only**, Start asks before switching that service to **Allow
downloads**; canceling leaves the configuration unchanged.

The available bind modes are **Tailscale**, **Localhost**, and **Local network**.
Local-network mode exposes an unauthenticated API and therefore requires an
explicit confirmation on every launch. Custom model identifiers also require
confirmation because their memory requirements have not been verified. Fields
are locked while their service is active; stop the service before editing its
next-launch configuration.

The Overview's **Test Tailscale** action selects an online peer and reports
whether connectivity is direct, relayed, or unreachable. Tailscale-bound
service launches run the same test first. Relayed or failed tests produce a
warning but do not prevent an acknowledged launch; a failed ping can indicate
a firewall, tailnet policy, or peer availability problem rather than proving a
specific cause.

When that warning appears, **Start Locally** launches Tailscale-configured
services on `127.0.0.1` for that run without changing their saved configuration.
A **Start on Wi-Fi** option is also shown when Wi-Fi has an active IPv4 address;
it listens on all local interfaces and displays the Wi-Fi address, so other
devices on that network can connect. This mode exposes the unauthenticated APIs
to the local network.
A Tailscale-bound service listens only on its `100.x.x.x` address and is not
also available through localhost. Running service cards, service details, and
logs show the complete endpoint where each model is available.

The separate Settings window provides the optional **Launch at Login** setting,
disabled by default.

## Model recommendations

Select **Recommendations** in the sidebar to view read-only suggestions from
the Ollama library and Hugging Face GGUF listings. The controller checks at
most once per day and also provides a manual **Check Now** button.

Only models with complete metadata, a known llama.cpp-compatible architecture,
and a conservative fit for this Mac can be labeled **Compatible**. Unknown,
oversized, and gated models are shown as **Unverified**. Cloud-only and
multimodal models are rejected and stay visible in the list with the reason.

Capability comes from signals that are actually read:

- **Hugging Face** — the model's `pipeline_tag` and tags, plus any `mmproj`
  projector file in a downloaded snapshot.
- **Ollama library** — the capability badges rendered on the library page
  (`vision`, `audio`, `embedding`, `tools`, `thinking`, `cloud`). Badge sizes
  such as `27b` are parameter counts, not byte sizes.
- **Installed Ollama models** — the projector manifest layer Ollama writes for
  vision models. This check needs no network access.

Models this controller manages are text-only, so an installed multimodal model
is reported as **Multimodal (not supported)** and is not offered in a launch
picker. A model already saved in a configuration is still listed, so switching
to a supported model is always possible.

Ollama model names are matched with the tag normalized for comparison only:
the library publishes `llava` while a local inventory reports `llava:latest`,
and both resolve to the same model. Saved configuration values are never
rewritten.

Recommendations are informational only. They do not include download, install,
or launch actions.

## Data locations

Service logs, process records, and the recommendation cache are stored under:

```text
~/Library/Application Support/Local AI Controller/
```

Per-service launch profiles and app preferences are stored through macOS user
defaults.

## Troubleshooting

- **Runtime not installed:** Install the named dependency outside the app and
  refresh the service status.
- **Tailscale not connected:** Run `tailscale up`, confirm it has an IPv4
  address, and retry, or select Localhost on the service screen.
- **Model missing:** Select **Allow downloads** on the service screen, or install
  the model outside the controller. **Cached only** uses llama.cpp offline mode
  and Ollama's no-pull mode.
- **Port occupied:** Stop the external process or choose another port on the
  service screen.
- **Service fails during startup:** Open that service and inspect its log for
  the exact runtime error. Preflight and launcher failures also display an
  immediate alert with corrective guidance and a **Reveal Log** button.
- **Recommendations unavailable:** Registry or network failures do not affect
  model controls. Use **Check Now** after connectivity returns.

Every start attempt appends timestamped diagnostics to the service log before
checking dependencies, ports, memory, disk space, or Tailscale. Earlier attempts
remain available after a retry or app relaunch.

For the detailed network and editor configuration, see [how_to.md](how_to.md).
