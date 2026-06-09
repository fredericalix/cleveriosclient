//
//  cleveriosclientTests.swift
//  cleveriosclientTests
//
//  Created by Frédéric Alix on 17/06/2025.
//

import Testing
import Foundation
@testable import mycleverclient

// MARK: - OAuth 1.0a Signer (highest-ROI: single point of failure for all API auth)

@Suite("CCOAuthSigner")
struct CCOAuthSignerTests {

    private func makeSigner(nonce: String = "testnonce", timestamp: String = "1700000000") -> CCOAuthSigner {
        let config = CCConfiguration(
            consumerKey: "ck",
            consumerSecret: "cs",
            accessToken: "at",
            accessTokenSecret: "ats"
        )
        return CCOAuthSigner(configuration: config,
                             nonceProvider: { nonce },
                             timestampProvider: { timestamp })
    }

    @Test("Signature base string is canonical (sorted params, %2F-encoded path)")
    func signatureBaseStringIsCanonical() {
        let signer = makeSigner()
        let url = URL(string: "https://api.clever-cloud.com/v2/self")!
        let base = signer.createSignatureBaseString(
            httpMethod: "GET",
            requestURL: url,
            parameters: [
                "oauth_consumer_key": "ck",
                "oauth_token": "at",
                "oauth_signature_method": "HMAC-SHA512",
                "oauth_timestamp": "1700000000",
                "oauth_nonce": "testnonce",
                "oauth_version": "1.0"
            ]
        )
        let expected = "GET&" +
            "https%3A%2F%2Fapi.clever-cloud.com%2Fv2%2Fself&" +
            "oauth_consumer_key%3Dck%26oauth_nonce%3Dtestnonce%26oauth_signature_method%3DHMAC-SHA512" +
            "%26oauth_timestamp%3D1700000000%26oauth_token%3Dat%26oauth_version%3D1.0"
        #expect(base == expected)
    }

    @Test("HMAC-SHA512 matches a precomputed openssl vector")
    func hmacMatchesVector() {
        let signer = makeSigner()
        // openssl: printf '%s' 'GET&clever' | openssl dgst -sha512 -hmac 'cs&ats' -binary | base64
        let sig = signer.generateHMACSHA512Signature(baseString: "GET&clever", signingKey: "cs&ats")
        #expect(sig == "4Pa0i6O9ZlqZX2NnBLML5UGUthbXisRWUYF4gDqgK6qz8kSbQcuLvQ/JMMzz2i+fMFRv7PrPXdJbeE1hLWxDUQ==")
    }

    @Test("Signed Authorization header is deterministic and well-formed")
    func headerIsDeterministic() throws {
        let signer = makeSigner()
        var request = URLRequest(url: URL(string: "https://api.clever-cloud.com/v2/self")!)
        request.httpMethod = "GET"

        let header = try signer.signRequest(request).value(forHTTPHeaderField: "Authorization")
        let header2 = try signer.signRequest(request).value(forHTTPHeaderField: "Authorization")

        let unwrapped = try #require(header)
        #expect(unwrapped.hasPrefix("OAuth "))
        #expect(unwrapped.contains("oauth_consumer_key=\"ck\""))
        #expect(unwrapped.contains("oauth_token=\"at\""))
        #expect(unwrapped.contains("oauth_nonce=\"testnonce\""))
        #expect(unwrapped.contains("oauth_signature_method=\"HMAC-SHA512\""))
        #expect(unwrapped.contains("oauth_signature="))
        // Same fixed nonce/timestamp ⇒ identical signature.
        #expect(header == header2)
    }

    @Test("Missing OAuth tokens throws authenticationFailed")
    func missingTokensThrows() {
        let config = CCConfiguration(consumerKey: "ck", consumerSecret: "cs") // no access token/secret
        let signer = CCOAuthSigner(configuration: config)
        let request = URLRequest(url: URL(string: "https://api.clever-cloud.com/v2/self")!)
        #expect(throws: CCError.self) {
            _ = try signer.signRequest(request)
        }
    }
}

// MARK: - RFC 3986 percent-encoding (OAuth-signature critical)

@Suite("oauthPercentEncoded")
struct OAuthPercentEncodingTests {

    @Test("Unreserved characters are preserved, everything else is encoded")
    func encodesReservedKeepsUnreserved() {
        #expect("abc".oauthPercentEncoded() == "abc")
        #expect("a b".oauthPercentEncoded() == "a%20b")
        #expect("/".oauthPercentEncoded() == "%2F")
        #expect(":".oauthPercentEncoded() == "%3A")
        #expect("&".oauthPercentEncoded() == "%26")
        #expect("=".oauthPercentEncoded() == "%3D")
        // Unreserved per RFC 3986: A-Z a-z 0-9 - _ . ~
        #expect("-._~".oauthPercentEncoded() == "-._~")
    }
}

// MARK: - Application status precedence (single source of truth)

@Suite("ApplicationStatus.compute")
struct ApplicationStatusComputeTests {

    // CCApplicationInstance has no memberwise init exposed and a required `flavor`; decode minimal JSON.
    private func instances(_ states: [String]) -> [CCApplicationInstance] {
        states.enumerated().map { idx, state in
            let json = "{\"id\":\"i\(idx)\",\"appId\":\"app\",\"state\":\"\(state)\",\"flavor\":{\"name\":\"nano\"}}"
            return try! JSONDecoder().decode(CCApplicationInstance.self, from: Data(json.utf8))
        }
    }

    @Test("Empty instances → Stopped")
    func emptyIsStopped() {
        #expect(ApplicationStatus.compute(from: []) == .stopped)
    }

    @Test("Any UP instance wins, even alongside FAILED (rolling deploy)")
    func upWinsOverFailed() {
        #expect(ApplicationStatus.compute(from: instances(["FAILED", "UP"])) == .running)
        #expect(ApplicationStatus.compute(from: instances(["UP"])) == .running)
    }

    @Test("Deploying when deploying present and none up")
    func deploying() {
        #expect(ApplicationStatus.compute(from: instances(["DEPLOYING", "FAILED"])) == .deploying)
    }

    @Test("Failed only when no UP/DEPLOYING")
    func failed() {
        #expect(ApplicationStatus.compute(from: instances(["FAILED"])) == .failed)
    }

    @Test("DOWN / SHOULD_BE_DOWN → Stopped")
    func down() {
        #expect(ApplicationStatus.compute(from: instances(["DOWN"])) == .stopped)
        #expect(ApplicationStatus.compute(from: instances(["SHOULD_BE_DOWN"])) == .stopped)
    }
}
