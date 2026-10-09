# Mochi

<p align="center">
  <img src="AppResources/AppIcon.png" alt="Mochi icon" width="128">
</p>

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-0B83FF?style=flat-square&logo=apple&labelColor=141414)
![Swift 6](https://img.shields.io/badge/Swift-6.0-FA7343?style=flat-square&logo=swift&labelColor=141414)

Mochi is a native macOS menu-bar and desktop application for
starting, stopping, configuring, and monitoring three local `llama.cpp` model
services.

The app manages:

- Qwen chat through `llama.cpp`
- Qwen code autocomplete through `llama.cpp`
- Nomic workspace embeddings through `llama.cpp`

## Table of contents

- [Screenshots](#screenshots)
- [Requirements](#requirements)
- [Build the app](#build-the-app)
- [Open the app](#open-the-app)
- [Usage](docs/usage.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Setup guide](docs/setup-guide.md)
- [Default ports](#default-ports)
- [Data locations](#data-locations)
- [Repository structure](#repository-structure)
- [Development](#development)
- [Documentation](#documentation)
- [License](#license)

## Screenshots

The controller exposes llama.cpp endpoints over your chosen network binding.
This overview is a real capture of the app with all three services stopped;
it shows the control center, memory dashboard, service cards, and navigation.

![Mochi overview showing the control center, memory dashboard, and three llama.cpp service cards.](docs/images/controller-overview.png)

## Requirements

- Apple Silicon Mac running macOS 14 or later
- Xcode command-line tools or Xcode with Swift 6
- Tailscale installed and connected when using the default Tailscale bind mode
- `llama.cpp` for the three llama.cpp services

Install runtime dependencies separately with Homebrew if needed:

```bash
brew install llama.cpp tailscale
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
dist/Mochi.app
```

## Open the app

Open it from Finder by double-clicking `dist/Mochi.app`, or run:

```bash
open "dist/Mochi.app"
```

If macOS blocks the first launch, Control-click the app in Finder, choose
**Open**, and confirm **Open**. The app is locally signed and is not notarized
for public distribution.

The app opens a management window and adds a CPU icon to the macOS menu bar.
If the main window is closed, use that menu-bar icon and select **Open
Controller**.

## Default ports

The default ports are:

| Service | Port |
| --- | ---: |
| Code autocomplete | `11435` |
| Workspace embeddings | `11436` |
| llama.cpp chat | `11437` |

## Data locations

Service logs, process records, and the recommendation cache are stored under:

```text
~/Library/Application Support/Mochi/
```

Per-service launch profiles and app preferences are stored through macOS user
defaults.

## Repository structure

```text
Sources/Mochi/     SwiftUI + AppKit application code
Tests/MochiTests/  Unit and integration-style tests with fakes
AppResources/                  Info.plist and application icon
docs/                          Architecture, style, and workflow guides
start_llama_network.sh         llama.cpp launcher
build_app.sh                   Release build and app-bundle packaging
check_code_line_lengths.sh     250-line authored-file quality gate
```

## Development

The package is built and tested with Swift Package Manager:

```bash
swift build                    # build the app
swift test                     # run the test suite
./check_code_line_lengths.sh   # 250-line authored-file quality gate
./scripts/validate_repository.sh # full local validation and contract checks
```

Run `swift test --filter <TestClassName>` to iterate on a focused test. `./build_app.sh` (see [Build the app](#build-the-app)) produces the signed `dist/Mochi.app` bundle.

## Documentation

Detailed guidance lives in [`docs/`](docs/):

- [`architecture.md`](docs/architecture.md) — MVVM + Clean Architecture layout and dependency boundaries.
- [`swift-style.md`](docs/swift-style.md) — Swift and file-size conventions.
- [`swiftui.md`](docs/swiftui.md) — SwiftUI/AppKit and theming rules.
- [`service-lifecycle.md`](docs/service-lifecycle.md) — service state machine and process-ownership safety.
- [`security-and-networking.md`](docs/security-and-networking.md) — bind modes and exposure controls.
- [`usage.md`](docs/usage.md) — controller operation, launch configuration, and model recommendations.
- [`troubleshooting.md`](docs/troubleshooting.md) — runtime, connectivity, model, port, and startup diagnostics.
- [`setup-guide.md`](docs/setup-guide.md) — network and editor client setup.
- [`testing.md`](docs/testing.md) — test conventions and pre-handoff gates.
- [`agentic-workflows.md`](docs/agentic-workflows.md) — how agents should work in this repository.
- [`engineering-practices-audit.md`](docs/engineering-practices-audit.md) — applicability and status of the 50 engineering practices.

## License

This repository is not currently under an explicit license. Copyright remains
with its author, and no rights beyond local, personal use are granted. If you
want to publish or share it, add a `LICENSE` file and update this section to
name the chosen license.
