import Combine
import Foundation

@MainActor
final class ModelDownloadCoordinator: ObservableObject {
    struct Failure: Identifiable, Equatable {
        let id: String
        let recommendation: ModelRecommendation
        let message: String
    }

    @Published private(set) var queued: [ModelRecommendation]
    @Published private(set) var active: (recommendation: ModelRecommendation, progress: ModelDownloadProgress)?
    @Published private(set) var completed: [ModelRecommendation] = []
    @Published private(set) var failures: [Failure] = []
    @Published private(set) var cancelled: [ModelRecommendation] = []

    private weak var manager: (any ModelDownloadExecuting)?
    private let queueStore: any ModelDownloadQueueStoring
    private var task: Task<Void, Never>?

    init(
        manager: any ModelDownloadExecuting,
        queueStore: any ModelDownloadQueueStoring
    ) {
        self.manager = manager
        self.queueStore = queueStore
        queued = []
        Task { @MainActor [weak self] in
            guard let self else { return }
            let stored = await self.queueStore.load()
            guard self.queued.isEmpty else { return }
            self.queued = stored
            self.processNext()
        }
        processNext()
    }

    deinit { task?.cancel() }

    func isQueued(_ recommendation: ModelRecommendation) -> Bool {
        queued.contains { identity($0) == identity(recommendation) } || active.map { identity($0.recommendation) == identity(recommendation) } == true
    }

    func enqueue(_ recommendation: ModelRecommendation) {
        guard !queued.contains(where: { identity($0) == identity(recommendation) }),
              active?.recommendation.id != recommendation.id else { return }
        queued.append(recommendation)
        persistQueue()
        removeFailure(for: recommendation)
        processNext()
    }

    func retry(_ failure: Failure) {
        removeFailure(for: failure.recommendation)
        enqueue(failure.recommendation)
    }

    func remove(_ recommendation: ModelRecommendation) {
        queued.removeAll { identity($0) == identity(recommendation) }
        persistQueue()
    }

    func cancelActive() {
        guard active != nil else { return }
        task?.cancel()
    }

    func dismissCompleted(_ recommendation: ModelRecommendation) {
        completed.removeAll { identity($0) == identity(recommendation) }
    }

    private func processNext() {
        guard active == nil, task == nil, let recommendation = queued.first, let manager else { return }
        queued.removeFirst()
        persistQueue()
        active = (recommendation, .init(completedBytes: 0, expectedBytes: recommendation.sizeBytes))
        task = Task { [weak self, weak manager] in
            do {
                guard let manager else { return }
                try await manager.downloadModel(recommendation) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.active?.recommendation.id == recommendation.id else { return }
                        self.active = (recommendation, progress)
                    }
                }
                try Task.checkCancellation()
                self?.finish(recommendation, result: .success(()))
            } catch is CancellationError {
                self?.finish(recommendation, result: .failure(CancellationError()))
            } catch let error as URLError where error.code == .cancelled {
                self?.finish(recommendation, result: .failure(CancellationError()))
            } catch {
                self?.finish(recommendation, result: .failure(error))
            }
        }
    }

    private func finish(_ recommendation: ModelRecommendation, result: Result<Void, Error>) {
        guard active?.recommendation.id == recommendation.id else { return }
        active = nil
        task = nil
        switch result {
        case .success:
            completed.append(recommendation)
        case .failure(let error) where error is CancellationError:
            cancelled.append(recommendation)
        case .failure(let error):
            failures.append(.init(id: identity(recommendation), recommendation: recommendation, message: error.localizedDescription))
        }
        processNext()
    }

    private func persistQueue() {
        let snapshot = queued
        Task { await queueStore.save(snapshot) }
    }

    private func identity(_ recommendation: ModelRecommendation) -> String {
        if let repository = recommendation.repository, let filename = recommendation.filename {
            return "llama:\(repository):\(filename)"
        }
        return "\(recommendation.runtime.lowercased()):\(recommendation.modelName ?? recommendation.name)"
    }

    private func removeFailure(for recommendation: ModelRecommendation) {
        failures.removeAll { identity($0.recommendation) == identity(recommendation) }
    }
}
