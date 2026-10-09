# Architecture

The app uses pragmatic Clean Architecture boundaries rather than formal
framework layers. Observable owners coordinate state and intent; use cases
coordinate behavior; protocols isolate real effect boundaries; live adapters
own OS, persistence, networking, and runtime details.

| Area | Responsibility | Must not |
| --- | --- | --- |
| `*View.swift`, `ConfigurationControls.swift` | Render state, collect intent, present confirmations | Probe the system, launch processes, persist data, or duplicate policy |
| Observable stores/view models | Publish state and translate user intent into use-case calls | Own blocking filesystem, process, or network work |
| Application use cases/coordinators | Orchestrate workflows and state transitions | Contain low-level persistence or OS implementation details |
| `ServiceModels.swift`, `RecommendationModels.swift` | Value types, enums, validation and compatibility policy | Import SwiftUI for presentation concerns |
| System/runtime adapters, model inventory, diagnostics/monitoring files | Isolate OS, filesystem, process, and network observations | Mutate observable view state directly |
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
- Split a type when it combines observable state with multiple effectful
  responsibilities, even when it is under 300 lines. Prefer a small facade
  over several focused collaborators with default live implementations.
- Keep effectful collaborator methods async or actor-isolated when they can
  block. Synchronous methods are limited to deterministic policy and cheap
  in-memory transformations.
- Preserve one authoritative path for state transitions, endpoint formation,
  launch arguments, and environment construction.

Persisted schemas are compatibility boundaries. New optional/defaultable fields
are safer than changing or removing existing fields; add a regression test for
legacy data whenever decoding behavior changes.
