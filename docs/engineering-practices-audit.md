# Engineering Practices Audit

This audit maps the 50-item engineering-practices catalogue to this native
macOS Swift controller. It is intentionally pragmatic: web, database, and
cloud deployment practices are recorded as out of scope instead of being
introduced without a corresponding product need.

## Status key

- **Met** — the repository has an established implementation and tests.
- **Partial** — the principle applies, but automation, coverage, or hardening remains.
- **Out of scope** — it does not match this local native application.

## Catalogue mapping

| Practice | Status | Repository evidence or follow-up |
| --- | --- | --- |
| 1. Design for scale early | Partial | Bounded polling, model lists, and memory history exist; no server-scale requirement applies. |
| 2. Component-based architecture | Met | Focused Domain, Data, Application, and Presentation files. |
| 3. API-first design | Partial | Runtime launch contracts are deterministic; no public web API is owned by this app. |
| 4. Microservices by necessity | Out of scope | The app controls external local runtimes. |
| 5. SOLID principles | Met | Protocol seams and focused responsibilities are established. |
| 6. DRY/KISS/YAGNI | Met | Shared policy and launch construction avoid duplicated behavior. |
| 7. Consistent formatting | Partial | Style guidance and line gate exist; CI now runs `swift-format` when available. |
| 8. Semantic naming | Met | Domain names describe service, bind, ownership, and validation behavior. |
| 9. Centralized error handling | Partial | Typed validation and user guidance exist; operational logging is being centralized. |
| 10. Standardized patterns | Met | MVVM-like state ownership, protocol seams, and strategy-style policy builders are used. |
| 11. Decoupled configuration | Met | Configuration is persisted separately and translated into launcher environments. |
| 12. Contextual documentation | Met | Architecture, lifecycle, security, testing, and workflow guides explain constraints. |
| 13. Focused functions | Partial | Most policy is focused; remaining manager helpers are candidates for later extraction. |
| 14. Context-first AI prompting | Met | `AGENTS.md` and repository workflow guidance provide constraints and validation rules. |
| 15. Treat AI as a draft | Met | Human review and final validation are required by repository guidance and CI. |
| 16. AI architecture prototyping | Partial | Architecture documentation exists; diagrams are lightweight rather than generated. |
| 17. Automate boilerplate | Partial | Tests and contract builders are automated; no code generator is needed. |
| 18. AI-driven test generation | Partial | Broad XCTest coverage exists; generated tests still require review. |
| 19. Infrastructure as code | Out of scope | No deployable infrastructure is managed by this app. |
| 20. Automated CI/CD | Partial | Pull-request validation is added; deployment is intentionally local signing. |
| 21. Blue-green deployment | Out of scope | No production service deployment exists. |
| 22. Automated rollback | Out of scope | Release artifacts are local and manually opened. |
| 23. Versioned environments | Partial | SwiftPM and macOS requirements are documented; no staging environment exists. |
| 24. Immutable infrastructure | Out of scope | The app is a local executable, not a server fleet. |
| 25. Shift-left testing | Met | Unit, architecture, shell-contract, and preflight tests run before handoff. |
| 26. Chaos engineering | Out of scope | No staging service environment exists. |
| 27. Peer code reviews | Partial | Required as a process; enforcement belongs to the hosting repository. |
| 28. Zero-trust access | Partial | Local APIs have no app-managed auth; every broader bind requires explicit confirmation. |
| 29. Strict input validation | Met | Ports, tuning values, model metadata, bind modes, and launcher values are validated. |
| 30. Secrets management | Met | The app does not accept or persist credentials; logs exclude private environment data. |
| 31. Scan AI code | Partial | CI provides static validation; SAST tooling is not applicable without a supported scanner. |
| 32. Dependency scanning | Partial | SwiftPM has no external dependencies; runtime tools are checked, not installed. |
| 33. Output encoding | Out of scope | This is not a browser-rendered application. |
| 34. Session controls | Out of scope | There are no user sessions or remote accounts. |
| 35. File-upload limits | Out of scope | The app does not accept uploads. |
| 36. Encrypt everywhere | Partial | Tailscale supplies transport protection; localhost/LAN HTTP behavior is explicit and documented. |
| 37. Secure error logging | Partial | Structured, redacted OS logging is added alongside actionable local service logs. |
| 38. Least privilege | Met | No sudo, dependency installation, or privileged process is used. |
| 39. Built-in compliance | Out of scope | No regulated data store or account system is managed. |
| 40. Mobile-first layout | Out of scope | The product is a macOS desktop application. |
| 41. WCAG/accessibility | Partial | SwiftUI accessibility labels exist; broader control and announcement coverage remains. |
| 42. Keyboard navigation | Partial | Native controls provide baseline support; explicit focus coverage remains. |
| 43. Screen-reader support | Partial | Labels and values exist for key controls; dynamic launch status needs expansion. |
| 44. UI design system | Met | `AppTheme` and shared presentation components centralize appearance. |
| 45. Virtualize large datasets | Met | Lazy stacks/grids and bounded model/history collections are used. |
| 46. Performance budgets | Partial | Bounded work exists; explicit validation budgets are documented for follow-up. |
| 47. Intelligent caching | Met | Recommendation cache and installed-model inventory avoid repeated remote work. |
| 48. Database query optimization | Out of scope | No database is used. |
| 49. Progressive data loading | Partial | Recommendation fetches are capped and staged; no server pagination is needed. |
| 50. Comprehensive observability | Partial | Structured lifecycle events now complement logs; full metrics/tracing is not needed for v1. |

## Review triggers

Changes to process ownership, bind modes, launcher environments, persisted
configuration, runtime tuning, or credential handling require focused tests and
human review. CI must not install dependencies, elevate privileges, launch
external runtimes, or open network listeners.
