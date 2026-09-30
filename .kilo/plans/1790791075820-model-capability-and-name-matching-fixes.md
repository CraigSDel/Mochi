# Fix model capability detection and Ollama name matching

## Context

The original request ("cannot read image.png") came from the Kilo session, not this
repo. Investigating the repo surfaced three real, confirmed bugs in the
recommendation / model-selection layer. All three are in the path between
"model exists" and "model is launchable", and all three contradict README.md:145-148.

### Bug 1 — Ollama names are compared with and without tags

- Installed names are tagged: `RecommendationModels.swift:158` builds
  `llava:latest` / `acme/model:latest`.
- Catalog names are tagless: `Recommendations.swift:120-127` sets
  `modelName: name` straight from the scraped href (`llava`).
- `ModelOptionBuilder.selectionKey` for `.ollama` is the raw name
  (`RecommendationModels.swift:243`).

Consequences:
- The installed/catalog dedupe at `RecommendationModels.swift:220` never matches, so
  every installed Ollama model appears **twice** in the picker.
- Selecting the catalog copy writes `llava` into config. `ServiceManager.swift:118-119`
  compares that against `{"llava:latest"}` exactly, so
  `modelsRequiringDownload` reports it as missing forever. `LaunchActions.swift:37-47`
  then shows "Download required models?" on **every** launch, and
  `ServiceManager.swift:161` launches with `--no-pull` under `cachedOnly`.
- `ServiceViews.swift:265` resolves the selection by raw string, so a config holding
  `llava` shows as `.missing` even when `llava:latest` is installed.

`ModelDiscoveryTests.swift:45-48` misses this because its fixture uses
`modelName: "embed:latest"` — already tagged.

### Bug 2 — Hugging Face models past rank 20 can never be verified

`Recommendations.swift:44` fetches `files_metadata=true` only for
`summaries.prefix(20)`, and the guard at `:46-47` skips the detail fetch for any
model whose id/tags fail the architecture check or contain `vision`/`multimodal`.
Without a detail response, `siblings[].size` is nil, so `candidate` is nil
(`:69-72`), `architectureKnown: false` or `sizeBytes == nil` yields `.unverified`
(`ServiceModels.swift:234`), and `repository` is set to nil (`:87`) — which makes
`ModelOptionBuilder` drop it at `:214`. A perfectly good known-architecture model at
rank 21 is silently invisible in every llama.cpp picker, forever.

### Bug 3 — Vision / cloud models are never actually detected

- `scanHuggingFace` drops `mmproj-*.gguf` at `RecommendationModels.swift:181` and
  records no flag, so a vision repo is reported as an ordinary text model.
- HF detection is two substrings, `vision` and `multimodal`
  (`Recommendations.swift:74`, `:77`). `llava`, `moondream`, `minicpm-v`,
  `qwen2-vl`, `internvl`, `idefics2` all pass. `ControllerPolicy.supportedArchitectures`
  (`ServiceModels.swift:221-223`) actively **whitelists** `qwen2`/`qwen3`/`gemma`,
  which are exactly the families whose VL variants leak through.
- `OllamaLibraryProvider` hardcodes `compatibility: .unverified`
  (`Recommendations.swift:125`) and never checks capability at all. Since
  `ModelOptionBuilder` blocks only `.incompatible` (`:211`), all ~30 scraped models —
  including `llava`, `minicpm-v`, `gemma3` — are selectable.
- `cloudOnly` is hardcoded `false` at all three call sites
  (`Recommendations.swift:74`, `:165`, `ServiceModels.swift:232`), so that parameter
  is dead code.

**Capability data is available and unused.** The Ollama library list page already
renders a per-model badge row, verified against `https://ollama.com/library?sort=newest`:

```html
<span class="... bg-indigo-50 ...">vision</span>
<span class="... bg-indigo-50 ...">tools</span>
<span class="... bg-cyan-50 ...">cloud</span>
<span class="... bg-[#ddf4ff] ...">27b</span>
```

So `vision`, `audio`, `embedding`, `tools`, `thinking`, and `cloud` are all readable
from the page the provider already fetches — no extra network calls. Separately,
Ollama writes an `application/vnd.ollama.image.projector` manifest layer for vision
models, so installed models can be classified with **zero** network access.

## Decisions

1. **Gating semantics.** Multimodal and cloud-only models become `.incompatible`
   (catalog) / a new `.unsupported` availability (installed inventory). They stay
   visible in the Recommendations list with an explicit rationale and are excluded
   from the launch pickers. This is what README.md:145-148 already promises.
2. **No rewrite of persisted user configuration.** `OllamaModelReference` normalizes
   for *comparison only*. A config holding `llava` keeps working (Ollama resolves the
   bare name to `:latest`); it simply stops being misreported. This honours the
   AGENTS.md rule that saved configuration is not silently rewritten.
3. **No persisted `Codable` schema change.** `ModelRecommendation` and
   `DiscoveredModel` gain no new stored fields, so `recommendations.json` and the
   existing `ModelRecommendationStoreTests` cache fixtures stay valid.
4. **Injectable HTTP for providers** so the prefilter, ordering and failure fallback
   are unit-testable without the network.

## Implementation

### 1. New `Sources/LocalAIController/OllamaModelReference.swift`

- `static func canonical(_ raw: String) -> String` — trim; split the tag at the last
  `:` **that occurs after the last `/`**; append `:latest` when there is no tag.
  (`acme/model` → `acme/model:latest`, `qwen3:8b` unchanged.)
- `static func key(_ raw: String) -> String` — `canonical(...).lowercased()`, for
  case-insensitive matching.

Use `key` at every Ollama comparison site:
- `RecommendationModels.swift:243` — `selectionKey` for `.ollama`
- `ServiceManager.swift:118-119` — `installedKeys = Set(installed.map { OllamaModelReference.key($0.name) })`, then test `!installedKeys.contains(OllamaModelReference.key($0))`
- `ServiceViews.swift:265` — `ollamaSelector` selection resolution
- `ServiceViews.swift:268` — no change needed; `option.name` is still written verbatim

### 2. New `Sources/LocalAIController/ModelCapability.swift`

Single source of truth for capability derivation, replacing the three divergent
copies (`RecommendationModels.swift:29-34`, `Recommendations.swift:91-95`, `:132-136`):

- `enum ModelCapability` with `static func role(inferringFrom:) -> RecommendationRole`
- `static func isMultimodal(pipelineTag:tags:filenames:)` — true when
  `pipeline_tag` is `image-text-to-text` / `video-text-to-text`, **or** any tag is in
  a known multimodal set (`vision`, `image-text-to-text`, `video-text-to-text`,
  `multimodal`, `vlm`, `llava`, `idefics`, `internvl`, `moondream`), **or** any
  `.gguf` filename contains `mmproj`.
- `static func isCloudOnly(badges:)` — true when the badge set contains `cloud`.

### 3. New `Sources/LocalAIController/OllamaLibraryParser.swift`

Pure, synchronous, no networking, so it is directly unit-testable:

```swift
struct OllamaLibraryEntry { let name: String; let badges: Set<String> }
enum OllamaLibraryParser { static func entries(html: String) -> [OllamaLibraryEntry] }
```

Implementation notes:
- Split on `<li` … `</li>` blocks; take the name from `href="/library/<name>"`.
- Collect badge text from every `<span …rounded-md…>text</span>` in the block.
  Do **not** depend on the Tailwind class strings (`bg-indigo-50` / `bg-cyan-50`)
  for semantics — match on `rounded-md` and read the inner text.
- First implementation step: fetch `https://ollama.com/library?sort=newest` once and
  confirm the badge vocabulary, then restrict the recognized set to
  `vision`, `audio`, `embedding`, `tools`, `thinking`, `cloud`. Size badges (`27b`)
  are parameter counts, **not** bytes — never map them to `sizeBytes`.
- Fail soft: an unparseable block yields no entry rather than aborting the fetch, and
  a model with no badges keeps today's tagless `.unverified` behaviour.

### 4. Split the providers out of `Recommendations.swift` (currently 276 lines)

Move into new files, leaving `RecommendationProvider` + `RecommendationStore` in
`Recommendations.swift`:
- `HuggingFaceProvider.swift` — `HFModel`, `FlexibleGated`, `HuggingFaceProvider`
- `OllamaLibraryProvider.swift` — uses `OllamaLibraryParser`; per entry:
  `multimodal: ModelCapability.isMultimodal(badges:)`, `cloudOnly: …isCloudOnly`,
  `role: …` (prefer an `embedding` badge over name substrings), `compatibility:`
  from `ControllerPolicy.compatibility` instead of the hardcoded `.unverified` at
  `:125`, and `modelName:` still tagless. Keep the 30-model cap.
- `CuratedLlamaCppProvider.swift`

Also move `ModelOptionBuilder` out of `RecommendationModels.swift` into
`ModelOptionBuilder.swift`, and `ControllerPolicy.launchArguments` /
`launchEnvironment` out of `ServiceManager.swift` (294 lines — leaves headroom for the
`modelsRequiringDownload` change).

### 5. `HuggingFaceProvider` — real capability data + full detail coverage

In `HuggingFaceProvider.swift`:
- Add `pipelineTag: String?` (`pipeline_tag`) to `HFModel`.
- Replace the `prefix(20)` loop with a bounded-concurrency `TaskGroup` (limit **4**)
  over **all** summaries that pass the prefilter
  (`ControllerPolicy.supportedArchitectures` match **and** `!isMultimodal`).
  Prefilter hits never consume a detail request.
- Carry the original index through the group and re-sort on it, so output order is
  deterministic.
- Keep the existing per-item fallback: a failed or non-200 detail request appends
  the summary unchanged (`:57-59`).
- Use a per-request timeout (20s) so one hung request cannot stall `refresh()`.
- In `classify`, drive `multimodal` from `ModelCapability.isMultimodal(pipelineTag:tags:filenames:)`
  instead of the two substrings, and set the rationale accordingly. Because
  multimodal now short-circuits, `architectureKnown` can no longer be starved of
  metadata by its own gate.

### 6. Record installed-model capability

`RecommendationModels.swift`:
- Add `supportsVision: Bool` to `DiscoveredModel` and `ModelOption`.
- `scanOllama` (`:143-165`): set it when any layer's `mediaType` is
  `application/vnd.ollama.image.projector`. (`image.adapter` is a LoRA, not vision.)
- `scanHuggingFace` (`:167-188`): currently `continue`s past `mmproj` files at `:181`.
  Instead, record that a projector exists in the snapshot and set `supportsVision` on
  the base model.
- Add `case unsupported = "Multimodal (not supported)"` to `ModelAvailability` (line 37).
- In `ModelOptionBuilder.options`, map `supportsVision == true` installed models to
  `.unsupported` and exclude them from the returned list, exactly as `.incompatible`
  catalog items are excluded at `:211`. An already-assigned vision model still
  surfaces through the `current` fallback at `:234-236`, so an existing configuration
  is never silently lost.

### 7. Docs

- README.md:145-148 — describe the actual signals (HF `pipeline_tag` + tags, Ollama
  library capability badges, Ollama projector manifest layer) instead of implying a
  check that does not exist.
- Leave `how_to.md:1` alone; it makes no claim this change needs to touch.

## Tests

New/extended, all network-free:

- `Tests/LocalAIControllerTests/OllamaModelReferenceTests.swift`
  `llava` == `llava:latest` == `LLAVA:Latest`; `acme/model` == `acme/model:latest`;
  `acme/model:8b` does not split on a colon inside the namespace; `qwen3:8b` != `qwen3`.
- `Tests/LocalAIControllerTests/OllamaLibraryParserTests.swift`
  Fixture `<li>` HTML with `vision`, `cloud`, `embedding`, and size badges → correct
  entries; a malformed block is skipped rather than throwing; 30-model cap respected.
- `Tests/LocalAIControllerTests/ModelDiscoveryTests.swift` (extend)
  Manifest with an `image.projector` layer → `supportsVision == true`;
  HF snapshot containing `mmproj-*.gguf` alongside a base GGUF → base model has
  `supportsVision == true` and the projector is still not offered as a model (the
  existing `count == 3` assertion at `:29` must be updated for the new base-model flag).
- `Tests/LocalAIControllerTests/ModelDiscoveryTests.swift` (extend)
  Installed `llava:latest` + catalog `modelName: "llava"` → **one** option, not two.
  This is the regression test that Bug 1 currently lacks (the fixture at `:45` is
  wrongly tagged).
- `Tests/LocalAIControllerTests/RecommendationModelTests.swift` (extend)
  `cloudOnly: true` and `multimodal: true` each yield `.incompatible`;
  `ModelCapability.isMultimodal` returns true for `image-text-to-text` pipeline tags
  and `mmproj` filenames, false for plain text models.
- `Tests/LocalAIControllerTests/DownloadPolicyTests.swift` (extend)
  Using the existing `FakeProbe` harness: config `chatModel: "llava"` with
  `probe.discoveredModels = [.init(runtime: .ollama, name: "llava:latest", …)]` →
  `manager.modelsRequiringDownload(for: .ollama)` is empty.
- New `HuggingFaceProviderTests` using an injected stub fetcher
  (`protocol HTTPFetching`, `URLSessionFetching` default, `StubFetcher` added to
  `TestSupport.swift`): every prefiltered candidate gets a detail request; vision and
  unknown-architecture candidates do not; a failing detail request falls back to the
  summary; output order matches input order.

## Risks

- **HTML scraping** (`OllamaLibraryParser`) is the fragile part. Mitigate with the
  fail-soft contract and by parsing badge *text*, not Tailwind class names.
- **Request volume** rises from ≤20 to ≤50 HF detail calls, at most once per 24h
  (`Recommendations.swift:201`, `:202`). Bounded concurrency of 4 plus the 20s timeout
  keeps this bounded; failure of any single request degrades to the previous summary.
- **Behavior change:** anyone currently running a vision model will see it drop out of
  the picker. This is the documented intent (README.md:145-148). The `.missing`
  fallback keeps the saved configuration intact and visible.
- **New `.unsupported` availability** changes `ModelOption.availability`. It is not
  `Codable` and not persisted, so no cache or defaults migration is required.

## Validation

```bash
./check_code_line_lengths.sh
swift test
```

`./build_app.sh` is **not** required — no packaging, entitlement, or launch-script
change.

Manual spot-check after implementation: with `llava` installed, confirm the Chat
picker lists `llava:latest` once, selecting it persists the tagged name, and
`cachedOnly` start no longer prompts for a download.

## Out of scope

- Rewriting already-persisted user configuration values.
- Real byte sizes for Ollama library catalog entries (library badges are parameter
  counts).
- The `compatibility.rawValue` string sort at the old `Recommendations.swift:238`,
  which orders Incompatible before Unverified.
- Consolidating the three role-inference copies beyond the shared
  `ModelCapability.role` used by the providers.
- Adding the `README.md:145-148` claim about `cloudOnly` to the *curated* provider,
  which stays `multimodal: false, cloudOnly: false` by construction.