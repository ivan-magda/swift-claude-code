import AsyncHTTPClient
import Foundation
import NIOCore
import NIOFoundationCompat

public protocol APIClientProtocol {
  func createMessage(request: APIRequest) async throws -> APIResponse
}

public struct APIClient: APIClientProtocol, Sendable {
  private static let requestTimeout = TimeAmount.seconds(300)
  private static let maxResponseBodySize = 10 * 1024 * 1024

  private let apiKey: String
  private let baseURL: String
  private let httpClient: HTTPClient

  public init(
    apiKey: String,
    baseURL: String = "https://api.anthropic.com",
    httpClient: HTTPClient = .shared
  ) {
    self.apiKey = apiKey
    self.baseURL = baseURL
    self.httpClient = httpClient
  }

  public func createMessage(request: APIRequest) async throws -> APIResponse {
    let body = try JSONEncoder().encode(request)

    var httpRequest = HTTPClientRequest(url: "\(baseURL)/v1/messages")
    httpRequest.method = .POST
    httpRequest.headers.add(name: "x-api-key", value: apiKey)
    httpRequest.headers.add(name: "anthropic-version", value: "2023-06-01")
    httpRequest.headers.add(name: "content-type", value: "application/json")
    httpRequest.body = .bytes(ByteBuffer(data: body))

    let response = try await httpClient.execute(httpRequest, timeout: Self.requestTimeout)
    let responseBody = try await response.body.collect(upTo: Self.maxResponseBodySize)
    let data = Data(buffer: responseBody)

    guard (200..<300).contains(Int(response.status.code)) else {
      if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
        throw errorResponse.error
      }
      throw APIClientError.httpError(
        statusCode: Int(response.status.code),
        body: String(data: data, encoding: .utf8) ?? "")
    }

    return try JSONDecoder().decode(APIResponse.self, from: data)
  }
}

public enum APIClientError: Error, CustomStringConvertible {
  case httpError(statusCode: Int, body: String)

  public var description: String {
    switch self {
    case .httpError(let code, let body):
      return "HTTP \(code): \(body)"
    }
  }
}
