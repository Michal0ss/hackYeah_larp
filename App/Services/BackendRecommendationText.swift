import API
import Contracts
import Foundation
import Insights

/// Reaches the model through the backend (`POST /v1/texts/recommendation`). Only the finished recommendation from
/// the rule engine is sent, never raw health samples, video or images. The backend checks the text and answers with
/// its own template when the model is unavailable; `RecommendationTexter` decides what to show.
struct BackendRecommendationFetcher: RecommendationTextFetching {
    let api: FormaAPI

    func fetch(_ recommendation: DailyRecommendation) async throws -> RemoteRecommendationText {
        let response = try await api.recommendationText(for: recommendation)
        return RemoteRecommendationText(headline: response.headline, explanation: response.explanation,
                                        fromModel: response.source == "ai", warnings: response.warnings)
    }
}
