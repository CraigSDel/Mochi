import Foundation

enum DownloadComposition {
  static func queueStore() -> any ModelDownloadQueueStoring {
    UserDefaultsModelDownloadQueueStore()
  }
}
