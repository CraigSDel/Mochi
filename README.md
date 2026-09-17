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
- Tailscale installed and connected
- `llama.cpp` for the three llama.cpp services
- Ollama for the Ollama service

Install runtime dependencies separately with Homebrew if needed:

```bash
brew install llama.cpp ollama tailscale lsof
```

Connect Tailscale before starting services:

```bash
tailscale up
```

The controller never installs dependencies or runs privileged commands. Before
starting services, it asks whether to use cached models only or explicitly
allow downloads for missing configured models.

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

- **Start** asks whether to use cached models only or allow missing models to be
  downloaded before starting one service.
- **Stop** gracefully stops a service launched by the controller.
- **Start All** shows the same download confirmation, then starts Ollama and the
  three compatible llama.cpp services.
- **Stop All** stops all verified controller-managed services.
- **Copy Logs**, **Clear**, and **Reveal** manage each service's local log.

If a process is already using a configured port but was not launched by the
controller, it is marked **External** and will not be terminated.

When quitting with managed services active, choose whether to keep them
running, stop them, or cancel quitting.

## Ports and settings

The default ports are:

| Service | Port |
| --- | ---: |
| Ollama | `11434` |
| Code autocomplete | `11435` |
| Workspace embeddings | `11436` |
| llama.cpp chat | `11437` |

The llama.cpp chat port can be changed under **Local AI Controller → Settings**.
The same screen provides an optional **Launch at Login** setting, disabled by
default.

## Model recommendations

Select **Recommendations** in the sidebar to view read-only suggestions from
the Ollama library and Hugging Face GGUF listings. The controller checks at
most once per day and also provides a manual **Check Now** button.

Only models with complete metadata, a known llama.cpp-compatible architecture,
and a conservative fit for this Mac can be labeled **Compatible**. Unknown,
oversized, gated, cloud-only, or unsupported multimodal models are rejected or
shown as **Unverified**.

Recommendations are informational only. They do not include download, install,
or launch actions.

## Data locations

Service logs, process records, and the recommendation cache are stored under:

```text
~/Library/Application Support/Local AI Controller/
```

App preferences, including the chat port, are stored through macOS user
defaults.

## Troubleshooting

- **Runtime not installed:** Install the named dependency outside the app and
  refresh the service status.
- **Tailscale not connected:** Run `tailscale up`, confirm it has an IPv4
  address, and retry.
- **Model missing:** Start again and choose **Allow Downloads**, or install the
  model outside the controller. **Cached Only** uses llama.cpp offline mode and
  Ollama's no-pull mode.
- **Port occupied:** Stop the external process or choose another llama.cpp chat
  port in Settings.
- **Service fails during startup:** Open that service and inspect its log for
  the exact runtime error.
- **Recommendations unavailable:** Registry or network failures do not affect
  model controls. Use **Check Now** after connectivity returns.

For the detailed network and editor configuration, see [how_to.md](how_to.md).
