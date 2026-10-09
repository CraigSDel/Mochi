# Architecture

The app uses a pragmatic separation of responsibilities rather than formal
framework layers.

| Area | Responsibility | Must not |
| --- | --- | --- |
| `*View.swift`, `ConfigurationControls.swift` | Render state, collect intent, present confirmations | Probe the system, launch processes, or duplicate policy |
| `ServiceManager.swift`, `LaunchActions.swift` | Orchestrate service state and lifecycle on `@MainActor` | Hide blocking work in synchronous UI paths |
| `ServiceModels.swift`, `RecommendationModels.swift` | Value types, enums, validation and compatibility policy | Import SwiftUI for presentation concerns |
| `SystemProbe.swift`, model inventory, diagnostics/monitoring files | Isolate OS, filesystem, process, and network observations | Mutate view state directly |
| `Recommendations.swift` | Fetch, cache, and normalize external recommendation data | Make recommendations required for core service control |
| launcher scripts | Translate validated configuration into runtime commands | Install software, use privilege elevation, or silently broaden network exposure |

## Dependency flow

```text
SwiftUI view -> observable manager/store -> protocols for system/process/data access
                    |                         |
                    v                         v
              value models              live implementations
                                             ^
                                             |
                                      test fakes/stubs
```

- Views send user intent to an observable owner and derive presentation from
  published state. They do not become a second source of business truth.
- External effects should sit behind small protocols when tests need to
  control time, processes, filesystem discovery, networking, or remote data.
- Keep policy calculations deterministic and side-effect free where possible;
  this makes memory, compatibility, validation, and routing rules cheap to test.
- Add an abstraction after a real boundary or variation exists. Do not create
  protocols solely to mirror every concrete type.
- Preserve one authoritative path for state transitions, endpoint formation,
  launch arguments, and environment construction.

Persisted schemas are compatibility boundaries. New optional/defaultable fields
are safer than changing or removing existing fields; add a regression test for
legacy data whenever decoding behavior changes.
