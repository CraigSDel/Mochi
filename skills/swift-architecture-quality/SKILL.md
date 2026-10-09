---
name: swift-architecture-quality
description: Create or review Swift XCTest and SwiftSyntax architecture checks for Clean Architecture and MVVM boundaries, including async unit tests and reusable mocks.
---

# Swift Architecture Quality

Use this skill when creating or reviewing tests and static rules for layered
Swift code. Match the repository's actual target layout before assuming a
Domain/Data/Presentation directory tree.

## Static architecture checks

When the project has layered directories, add XCTest checks that:

- scan Domain source files and fail on imports of SwiftUI, UIKit, Combine for
  UI state, SwiftData, CoreData, or networking frameworks;
- verify Data repository implementations correspond to Domain repository
  protocols;
- detect DTO or persistence entity types crossing into Domain without a
  mapper;
- detect Views reaching into repositories or data sources directly;
- detect ViewModels retaining SwiftUI Views or UIKit controllers.
- detect observable application/presentation types directly using `Process`,
  `FileManager`, `Data(contentsOf:)`, `URLSession`, or `UserDefaults` for
  effectful work instead of an injected collaborator;
- detect source files that combine multiple unrelated effect boundaries and
  report them for responsibility-based review, even below 250 lines.

Prefer SwiftSyntax for source inspection when it is available in the package.
Keep architecture tests deterministic, explain the violated boundary in the
failure message, and scope scans to source roots rather than generated files.
If SwiftSyntax is not already a dependency, do not silently add a large
dependency for a repository that does not have layered source roots; document
the limitation or use a small, clearly bounded fallback only when appropriate.

## Behavioral tests

- Test UseCases against mock Domain repositories.
- Test ViewModels against mock UseCases, including success, domain failure,
  loading/empty states, cancellation where relevant, and `@MainActor`
  behavior.
- Keep mocks reusable and protocol-shaped; do not test through real network,
  database, process, or UI dependencies in unit tests.
- Make fakes deterministic across developer machines and CI runners. Inject
  physical memory, clocks, filesystem locations, and network clients instead
  of reading host state from the code under test. For URL fakes, normalize
  percent-encoded paths before matching and assert both request counts and
  resulting domain state.
- For persistence, process, and runtime collaborators, include failure,
  cancellation, missing dependency, and compatibility cases in addition to
  happy-path tests.
- Prefer async XCTest APIs and name tests as
  `test_[subject]_[scenario]_[expectedResult]`.

## Output conventions

Label generated test snippets with their layer and file path, for example:

```swift
// Tests/ArchitectureTests/DomainDependencyTests.swift
```

Include the protocol, mock, and composition needed to run the test. Report
which checks were actually run. Preserve existing macOS lifecycle, security,
and process-ownership rules; architecture tests must not encourage unsafe
termination or dependency installation.
