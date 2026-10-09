---
name: clean-architecture-swift
description: Design or refactor Swift and SwiftUI features using Clean Architecture, MVVM, dependency inversion, modern concurrency, and testable dependency injection.
---

# Clean Architecture Swift

Use this skill when creating or refactoring Swift application features. Adapt
the shape to the host platform and repository conventions; do not introduce
layers or modules without a distinct responsibility.

## Architecture

- Keep Domain code pure Swift: entities, domain-specific errors, use cases,
  and repository protocols. It must not import UI, persistence, or networking.
- Put API clients, DTOs, local data sources, mappers, and repository
  implementations in Data. Translate at boundaries rather than leaking DTOs.
- Keep Presentation declarative and state-driven. Views render state and send
  intent to ViewModels; ViewModels coordinate use cases and expose UI state.
- Apply dependency inversion: higher-level code depends on protocols, with
  concrete dependencies supplied through initializers or a feature factory.
- Treat an observable store/view model as a state facade, not an infrastructure
  container. Extract persistence, process, filesystem, networking, notification,
  and discovery behavior into focused async collaborators.
- Split by responsibility when a type combines state plus multiple effects,
  regardless of whether it is below the repository's line-count limit.

## Swift standards

- Prefer `async`/`await`, actors, and structured concurrency over completion
  handlers. Keep blocking process, file, and network work off `@MainActor`.
- Use `@MainActor` for observable UI state when required by the framework.
- Map infrastructure failures to domain-specific errors suitable for UI; do
  not expose generic transport or persistence errors as the UI contract.
- Define protocols and fakes/mocks for use cases, repositories, and clients so
  ViewModels and business rules can be tested in isolation.
- Inject environment-dependent policy inputs at composition boundaries. Keep
  production defaults such as `ProcessInfo.processInfo.physicalMemory`, the
  current date, and live URLs out of deterministic tests; pass explicit test
  values instead.
- Keep blocking filesystem/process work behind async or actor-backed protocols;
  do not call synchronous scans or waits from `@MainActor` state paths.

## Feature layout

```text
App/
├── Application/
├── Core/
├── Domain/{Entities,Repositories,UseCases}/
├── Data/{Repositories,Network,Local,Mappers}/
└── Presentation/Features/[FeatureName]/{Views,ViewModels,Navigation}/
```

In this repository, preserve the established `Sources/Mochi` and
`Tests/MochiTests` layout rather than mechanically creating an
`App/` tree. Add focused files for distinct responsibilities and keep authored
files within the repository's line-length gate.

## Output and wiring

When presenting generated code, label snippets with their layer and file path
in a comment. Include protocols alongside concrete implementations and show
dependency-injection composition at the application entry point or feature
factory.

Before changing persisted models, process ownership, networking exposure, or
configuration behavior, follow the repository's architecture and security
documentation; this skill does not override those constraints.
