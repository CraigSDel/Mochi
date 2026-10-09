import XCTest
@testable import Mochi

final class HuggingFaceProviderTests: XCTestCase {
    private func summary(id: String, pipelineTag: String = "text-generation", tags: [String] = ["gguf"], siblings: [HFModel.Sibling] = []) -> String {
        let files = siblings.map { sibling in
            "{\"rfilename\":\"\(sibling.rfilename)\"" + (sibling.size.map { ",\"size\":\($0)" } ?? "") + "}"
        }.joined(separator: ",")
        return """
        {"id":"\(id)","pipeline_tag":"\(pipelineTag)","tags":\(Self.json(tags)),"gated":false,"private":false,"siblings":[\(files)]}
        """
    }

    private func sizedDetail(for id: String, bytes: Int64 = 4_000_000_000) -> String {
        """
        {"id":"\(id)","pipeline_tag":"text-generation","tags":["gguf"],"gated":false,"private":false,
         "siblings":[{"rfilename":"model-Q4_K_M.gguf","size":\(bytes)}]}
        """
    }

    func testEveryPrefilteredCandidateGetsADetailRequest() async throws {
        let summaries = (0..<25).map { summary(id: "qwen3-model-\($0)") }.joined(separator: ",")
        let fetcher = StubFetcher()
        fetcher.stub(pathSuffix: "/api/models", data: Data(("[" + summaries + "]").utf8))
        for index in 0..<25 { fetcher.stub(pathSuffix: "/api/models/qwen3-model-\(index)", data: Data(sizedDetail(for: "qwen3-model-\(index)").utf8)) }

        let recommendations = try await HuggingFaceProvider(fetcher: fetcher).fetch()

        // The old implementation capped detail requests at the first 20 rows, so
        // anything below the cut-off could never be verified.
        XCTAssertEqual(fetcher.requestCount(matching: "/api/models/qwen3-model-24"), 1)
        XCTAssertEqual(recommendations.count, 25)
        XCTAssertTrue(recommendations.allSatisfy { $0.compatibility == .compatible })
        XCTAssertEqual(recommendations.map(\.name), (0..<25).map { "qwen3-model-\($0)" })
    }

    func testVisionAndUnknownArchitecturesConsumeNoDetailRequest() async throws {
        let summaries = [
            summary(id: "owner/qwen2-vl-vision", pipelineTag: "image-text-to-text"),
            summary(id: "owner/moondream-vision", tags: ["gguf", "vision"]),
            summary(id: "owner/exotic-arch", tags: ["gguf"])
        ].joined(separator: ",")
        let fetcher = StubFetcher()
        fetcher.stub(pathSuffix: "/api/models", data: Data(("[" + summaries + "]").utf8))
        fetcher.stub(pathSuffix: "/api/models/owner/qwen2-vl-vision", data: Data(sizedDetail(for: "owner/qwen2-vl-vision").utf8))
        fetcher.stub(pathSuffix: "/api/models/owner/moondream-vision", data: Data(sizedDetail(for: "owner/moondream-vision").utf8))
        fetcher.stub(pathSuffix: "/api/models/owner/exotic-arch", data: Data(sizedDetail(for: "owner/exotic-arch").utf8))

        let recommendations = try await HuggingFaceProvider(fetcher: fetcher).fetch()

        XCTAssertEqual(fetcher.requestCount(matching: "/api/models/qwen2-vl-vision"), 0)
        XCTAssertEqual(fetcher.requestCount(matching: "/api/models/moondream-vision"), 0)
        XCTAssertEqual(fetcher.requestCount(matching: "/api/models/exotic-arch"), 0)
        XCTAssertEqual(recommendations[0].compatibility, .incompatible)
        XCTAssertEqual(recommendations[1].compatibility, .incompatible)
        XCTAssertEqual(recommendations[2].compatibility, .unverified)
        XCTAssertEqual(recommendations[0].rationale, "Multimodal models are excluded from this text-only controller.")
        XCTAssertEqual(recommendations[2].rationale, "Architecture is not on the maintained llama.cpp allowlist.")
        XCTAssertTrue(recommendations.allSatisfy { $0.filename == nil && $0.repository == nil })
    }

    func testFailedDetailRequestFallsBackToTheSummary() async throws {
        let summaries = [
            summary(id: "owner/llama-text"),
            summary(id: "owner/mistral-flaky")
        ].joined(separator: ",")
        let fetcher = StubFetcher()
        fetcher.stub(pathSuffix: "/api/models", data: Data(("[" + summaries + "]").utf8))
        fetcher.stub(pathSuffix: "/api/models/owner/llama-text", data: Data(sizedDetail(for: "owner/llama-text").utf8))
        fetcher.stubFailure(pathSuffix: "/api/models/owner/mistral-flaky")

        let recommendations = try await HuggingFaceProvider(fetcher: fetcher).fetch()

        XCTAssertEqual(recommendations.map(\.name), ["owner/llama-text", "owner/mistral-flaky"])
        XCTAssertEqual(recommendations[0].compatibility, .compatible)
        XCTAssertEqual(recommendations[1].compatibility, .unverified)
        XCTAssertEqual(recommendations[1].rationale, "No supported, sized Q4/Q5 GGUF variant was reported.")
    }

    func testNonSuccessDetailResponseFallsBackToTheSummary() async throws {
        let summaries = summary(id: "owner/llama-text")
        let fetcher = StubFetcher()
        fetcher.stub(pathSuffix: "/api/models", data: Data(("[" + summaries + "]").utf8))
        fetcher.stub(pathSuffix: "/api/models/owner/llama-text", data: Data(sizedDetail(for: "owner/llama-text").utf8), statusCode: 503)

        let recommendations = try await HuggingFaceProvider(fetcher: fetcher).fetch()

        XCTAssertEqual(recommendations.map(\.compatibility), [.unverified])
    }

    func testFailedSummaryRequestThrowsSoTheStoreCanFallBack() async {
        let fetcher = StubFetcher()
        fetcher.stub(pathSuffix: "/api/models", data: Data("[]".utf8), statusCode: 500)

        do {
            _ = try await HuggingFaceProvider(fetcher: fetcher).fetch()
            XCTFail("Expected a non-success response to fail the fetch.")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    func testRequestsCarryAPerRequestTimeout() async throws {
        let fetcher = StubFetcher()
        fetcher.stub(pathSuffix: "/api/models", data: Data("[\(summary(id: "owner/llama-text"))]".utf8))
        fetcher.stub(pathSuffix: "/api/models/owner/llama-text", data: Data(sizedDetail(for: "owner/llama-text").utf8))

        _ = try await HuggingFaceProvider(fetcher: fetcher).fetch()

        XCTAssertEqual(Set(fetcher.timeouts), [HuggingFaceProvider.requestTimeout])
    }

    func testSearchUsesEncodedQueryAndResolvesDetails() async throws {
        let fetcher = StubFetcher()
        fetcher.stub(pathSuffix: "/api/models", data: Data(("[" + summary(id: "owner/qwen3-model") + "]").utf8))
        fetcher.stub(pathSuffix: "/api/models/owner/qwen3-model", data: Data(sizedDetail(for: "owner/qwen3-model").utf8))

        let results = try await HuggingFaceProvider(fetcher: fetcher).search(query: "qwen 3")

        let components = try XCTUnwrap(fetcher.requestedURLs.first.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "search" })?.value, "qwen 3")
        XCTAssertEqual(results.map(\.name), ["owner/qwen3-model"])
        XCTAssertEqual(results.first?.compatibility, .compatible)
    }

    func testMmprojFileAloneMarksAModelMultimodal() {
        let model = try? JSONDecoder().decode(HFModel.self, from: Data(summary(id: "owner/qwen3-vl", siblings: [
            .init(rfilename: "model-Q4_K_M.gguf", size: 4_000_000_000),
            .init(rfilename: "mmproj-model-f16.gguf", size: 900_000_000)
        ]).utf8))

        XCTAssertEqual(model?.isMultimodal, true)
        XCTAssertEqual(model?.needsDetail, false)
    }

    private static func json(_ values: [String]) -> String {
        "[" + values.map { "\"\($0)\"" }.joined(separator: ",") + "]"
    }
}
