import Foundation

/// Builds the runtime command line and environment for a managed service.
///
/// Kept apart from `ServiceManager` so the launch contract can be asserted
/// directly, without constructing a manager or touching the process table.
enum LaunchInvocation {
    static func arguments(id: ServiceID, script: URL, modelChoice: String?, configuration: ServiceLaunchConfiguration) -> [String] {
        var arguments = [script.path]
        if id != .ollama { arguments += ["--model", modelChoice!] }
        arguments += ["--bind", configuration.bindMode.rawValue]
        if id == .ollama { arguments += ["--port", String(configuration.port)] }
        arguments += ["--no-install", "--no-tailscale-up"]
        if configuration.downloadPolicy == .cachedOnly { arguments.append(id == .ollama ? "--no-pull" : "--offline") }
        return arguments
    }

    static func environment(id: ServiceID, configuration: ServiceLaunchConfiguration, base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base; environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        if let llama = configuration.llama {
            environment.merge(llamaVariables(id: id, llama: llama, port: configuration.port)) { _, new in new }
        } else if let ollama = configuration.ollama {
            environment.merge(ollamaVariables(ollama: ollama, port: configuration.port)) { _, new in new }
        }
        return environment
    }

    private static func llamaVariables(id: ServiceID, llama: LlamaLaunchConfiguration, port: Int) -> [String: String] {
        let prefix: String
        switch id {
        case .llamaChat: prefix = "LLAMA_CHAT"
        case .autocomplete: prefix = "LLAMA_AUTOCOMPLETE"
        case .embeddings: prefix = "LLAMA_EMBEDDING"
        case .ollama: prefix = ""
        }
        return [
            "\(prefix)_PORT": String(port),
            "\(prefix)_REPO": llama.repository,
            "\(prefix)_FILE": llama.filename,
            "\(prefix)_ALIAS": llama.alias,
            "\(prefix)_CONTEXT": String(llama.contextSize),
            "LLAMA_GPU_LAYERS": String(llama.gpuLayers)
        ]
    }

    private static func ollamaVariables(ollama: OllamaLaunchConfiguration, port: Int) -> [String: String] {
        [
            "OLLAMA_PORT": String(port),
            "OLLAMA_CHAT_MODEL": ollama.chatModel,
            "OLLAMA_AUTOCOMPLETE_MODEL": ollama.autocompleteModel,
            "OLLAMA_EMBEDDING_MODEL": ollama.embeddingModel,
            "OLLAMA_FLASH_ATTENTION": ollama.flashAttention ? "1" : "0",
            "OLLAMA_KV_CACHE_TYPE": ollama.kvCacheType,
            "OLLAMA_CONTEXT_LENGTH": String(ollama.contextLength),
            "OLLAMA_NUM_PARALLEL": String(ollama.parallelRequests),
            "OLLAMA_MAX_LOADED_MODELS": String(ollama.maxLoadedModels)
        ]
    }
}