import SwiftUI

struct RecommendationsView: View {
  @ObservedObject var store: RecommendationStore
  @ObservedObject var manager: ServiceManager
  @ObservedObject var downloads: ModelDownloadCoordinator
  let guidance: [PerformanceGuidance]
  @State private var role: RecommendationRole?
  @State private var searchText = ""
  @AppStorage("recommendations.compatibilityFilter") private var compatibilityFilter:
    RecommendationCompatibilityFilter = .all
  private var isSearchingCatalog: Bool { !store.searchQuery.isEmpty }
  private var sourceModels: [ModelRecommendation] {
    isSearchingCatalog ? store.searchResults : store.recommendations
  }
  var filtered: [ModelRecommendation] { compatibilityFilter.apply(to: sourceModels, role: role) }
  private var hasFailure: Bool { store.status.hasPrefix("Unavailable") }
  private var hasActiveFilter: Bool { role != nil || compatibilityFilter != .all }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack {
          PageHeader(
            eyebrow: "Discover",
            title: "Model recommendations",
            subtitle: "Conservative suggestions sized for local use on this Mac.",
            symbol: "sparkles"
          )
          Spacer()
          Button {
            Task { await store.refresh() }
          } label: {
            if store.isRefreshing {
              HStack {
                ProgressView().controlSize(.small)
                Text("Checking…")
              }
            } else {
              Label("Check Now", systemImage: "arrow.clockwise")
            }
          }
          .buttonStyle(ApplePrimaryButtonStyle())
          .disabled(store.isRefreshing)
        }

        HardwareRecommendationsView(
          manager: manager, store: store, downloads: downloads, compact: false)

        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.secondaryText)
            TextField("Search Hugging Face models", text: $searchText)
              .textFieldStyle(.plain)
              .onSubmit { search() }
            if !searchText.isEmpty {
              Button("Clear") {
                searchText = ""
                store.clearSearch()
              }
              .buttonStyle(.plain)
              .foregroundStyle(AppTheme.secondaryText)
            }
            Button(store.isSearching ? "Searching…" : "Search") { search() }
              .buttonStyle(AppleSecondaryButtonStyle())
              .disabled(
                searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  || store.isSearching)
          }
          .padding(9)
          .background(
            Color(nsColor: .textBackgroundColor).opacity(0.72),
            in: RoundedRectangle(cornerRadius: 9))
          if isSearchingCatalog {
            HStack(spacing: 8) {
              Image(
                systemName: store.searchStatus.hasPrefix("Search unavailable")
                  ? "exclamationmark.triangle.fill" : "magnifyingglass"
              )
              .foregroundStyle(
                store.searchStatus.hasPrefix("Search unavailable") ? Color.orange : AppTheme.accent)
              Text(store.searchStatus)
              Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          HStack(spacing: 12) {
            Text("Role")
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(AppTheme.secondaryText)
            HStack(spacing: 4) {
              roleButton("All roles", value: nil)
              ForEach(RecommendationRole.allCases, id: \.self) { item in
                roleButton(item.rawValue, value: item)
              }
            }
            .padding(4)
            .background(
              AppTheme.pageBackground.opacity(0.72),
              in: RoundedRectangle(cornerRadius: 11, style: .continuous))
          }
          HStack(spacing: 12) {
            Text("Compatibility")
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(AppTheme.secondaryText)
            HStack(spacing: 4) {
              compatibilityButton("All", value: .all)
              compatibilityButton("Compatible only", value: .compatibleOnly)
            }
            .padding(4)
            .background(
              AppTheme.pageBackground.opacity(0.72),
              in: RoundedRectangle(cornerRadius: 11, style: .continuous))
          }
          HStack(spacing: 8) {
            Image(
              systemName: hasFailure ? "exclamationmark.triangle.fill" : "checkmark.shield.fill"
            )
            .foregroundStyle(hasFailure ? Color.orange : AppTheme.accent)
            Text(store.status)
            Spacer()
            if let lastChecked = store.lastChecked {
              Text("Updated \(lastChecked.formatted(date: .abbreviated, time: .shortened))")
            }
          }
          .font(.caption).foregroundStyle(.secondary)
        }
        .appCard(padding: 14)

        ForEach(guidance) { item in
          PerformanceGuidanceCard(guidance: item)
        }

        if filtered.isEmpty && !store.isRefreshing && !store.isSearching {
          FriendlyEmptyState(
            symbol: isSearchingCatalog
              ? "magnifyingglass" : (hasFailure ? "wifi.exclamationmark" : "sparkles"),
            title: isSearchingCatalog
              ? "No matching Hugging Face models"
              : (hasFailure
                ? "Recommendations unavailable"
                : (hasActiveFilter && !store.recommendations.isEmpty
                  ? "No matching recommendations" : "No recommendations yet")),
            message: isSearchingCatalog
              ? "Try a different search term."
              : (hasFailure
                ? "Check your connection and try again. Cached results will remain available."
                : (hasActiveFilter && !store.recommendations.isEmpty
                  ? "Change the role or compatibility filter to see more models."
                  : "Check the registries now to find models that fit this Mac."))
          )
        } else {
          LazyVStack(spacing: 12) {
            ForEach(filtered) { model in
              RecommendationCard(
                model: model,
                queued: downloads.isQueued(model),
                canQueue: model.compatibility != .incompatible,
                onQueue: { downloads.enqueue(model) }
              )
            }
          }
        }
      }
      .padding(.horizontal, 36)
      .padding(.vertical, 32)
    }
    .background(AppTheme.pageBackground)
  }

  private func search() {
    Task { await store.search(query: searchText) }
  }

  private func roleButton(_ title: String, value: RecommendationRole?) -> some View {
    let selected = role == value
    return Button {
      withAnimation(.easeOut(duration: 0.16)) { role = value }
    } label: {
      Text(title)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(selected ? Color.white : AppTheme.secondaryText)
        .frame(maxWidth: .infinity, minHeight: 30)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      selected ? AppTheme.accent : Color.clear,
      in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func compatibilityButton(_ title: String, value: RecommendationCompatibilityFilter)
    -> some View
  {
    let selected = compatibilityFilter == value
    return Button {
      withAnimation(.easeOut(duration: 0.16)) { compatibilityFilter = value }
    } label: {
      Text(title)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(selected ? Color.white : AppTheme.secondaryText)
        .frame(maxWidth: .infinity, minHeight: 30)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      selected ? AppTheme.accent : Color.clear,
      in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
