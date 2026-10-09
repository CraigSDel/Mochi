import ServiceManagement
import SwiftUI

struct LaunchAtLoginSection: View {
  @ObservedObject var manager: ServiceManager
  @State private var loginError = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle(isOn: launchAtLoginBinding) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Launch at Login").font(.headline)
          Text("Open the controller automatically when you sign in to this Mac.").font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      if !loginError.isEmpty {
        Label(loginError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(
          .caption)
      }
    }
    .appCard()
    .onAppear { manager.launchAtLogin = SMAppService.mainApp.status == .enabled }
  }

  private var launchAtLoginBinding: Binding<Bool> {
    Binding(
      get: { manager.launchAtLogin },
      set: { enabled in updateLogin(enabled) }
    )
  }

  private func updateLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      manager.launchAtLogin = enabled
      loginError = ""
    } catch { loginError = error.localizedDescription }
  }
}
