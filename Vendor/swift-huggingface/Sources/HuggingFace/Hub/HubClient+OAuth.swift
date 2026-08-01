import Foundation

extension HubClient {
    /// Gets OAuth user information.
    ///
    /// Only available through OAuth access tokens. Information varies depending on the scope
    /// of the OAuth app and what permissions the user granted to the OAuth app.
    ///
    /// - Returns: OAuth user information.
    /// - Throws: An error if the request fails or the response cannot be decoded.
    public func getOAuthUserInfo() async throws -> OAuth.UserInfo {
        return try await httpClient.fetch(.get, "/oauth/userinfo")
    }
}
