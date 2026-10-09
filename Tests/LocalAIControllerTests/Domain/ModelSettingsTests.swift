import XCTest
@testable import LocalAIController

final class ModelSettingsTests: XCTestCase {
    func testAssignmentKeyIncludesRuntimeModelServiceAndRole() {
        let first = ModelAssignmentKey(runtime: .ollama, modelID: "ollama:qwen", serviceID: .ollama, role: .chat)
        let second = ModelAssignmentKey(runtime: .ollama, modelID: "ollama:qwen", serviceID: .ollama, role: .coding)
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first.id, second.id)
    }

    func testDefaultsAreRoleAwareAndDoNotCopyLegacyServiceTuning() {
        var legacy = ServiceLaunchConfiguration.defaultValue(for: .llamaChat)
        legacy.llama?.contextSize = 65_536
        let profile = ModelSettingsProfile.defaults(runtime: .llamaCpp, role: .chat)
        XCTAssertEqual(legacy.llama?.contextSize, 65_536)
        XCTAssertEqual(profile.llama?.contextSize, 16_384)
        XCTAssertEqual(ModelSettingsProfile.defaults(runtime: .llamaCpp, role: .coding).llama?.generation, .autocompleteBalanced)
    }

    func testEmbeddingProfileHasNoGenerationControlsInProviderExport() {
        let configuration = ServiceLaunchConfiguration.defaultValue(for: .embeddings)
        let key = ModelAssignmentKey(runtime: .llamaCpp, modelID: "llama:nomic-ai/nomic-embed-text-v1.5-GGUF:nomic-embed-text-v1.5.Q8_0.gguf", serviceID: .embeddings, role: .embedding)
        let settings = [key: ModelSettingsProfile.defaults(runtime: .llamaCpp, role: .embedding)]
        let record = ProviderExportBuilder.records(configurations: [.embeddings: configuration], modelSettings: settings)["embeddings"]
        XCTAssertNil(record?.temperature)
        XCTAssertNil(record?.maxOutputTokens)
    }

    func testLaunchEnvironmentUsesAssignmentProfileForEachLlamaRole() {
        let configuration = ServiceLaunchConfiguration.defaultValue(for: .autocomplete)
        var profile = ModelSettingsProfile.defaults(runtime: .llamaCpp, role: .coding)
        profile.llama?.contextSize = 4_096
        profile.llama?.generation.temperature = 0.15
        let environment = LaunchInvocation.environment(id: .autocomplete, configuration: configuration, modelSettings: profile, base: [:])
        XCTAssertEqual(environment["LLAMA_AUTOCOMPLETE_CONTEXT"], "4096")
        XCTAssertEqual(environment["LLAMA_AUTOCOMPLETE_TEMPERATURE"], "0.15")
    }

    func testSettingsStoreRoundTripsAssignmentProfiles() async {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsModelSettingsStore(defaults: defaults)
        let key = ModelAssignmentKey(runtime: .ollama, modelID: "ollama:qwen", serviceID: .ollama, role: .chat)
        let profile = ModelSettingsProfile.defaults(runtime: .ollama, role: .chat)
        await store.save([key: profile])
        let loaded = await store.load()
        XCTAssertEqual(loaded[key], profile)
    }
}
