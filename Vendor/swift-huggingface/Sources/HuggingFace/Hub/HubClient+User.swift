import Foundation

extension HubClient {
    /// Gets information about the authenticated user.
    ///
    /// Requires authentication with a Bearer token.
    ///
    /// - Returns: Information about the authenticated user.
    /// - Throws: An error if the request fails or the response cannot be decoded.
    public func whoami() async throws -> User {
        return try await httpClient.fetch(.get, "/api/whoami-v2")
    }
}
