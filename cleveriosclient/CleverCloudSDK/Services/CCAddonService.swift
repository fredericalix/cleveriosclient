import Foundation
import Combine

/// Service for managing Clever Cloud add-ons (databases, caches, etc.)
public class CCAddonService: ObservableObject {
    
    // MARK: - Properties
    
    private let httpClient: CCHTTPClient
    
    // MARK: - Initialization
    
    public init(httpClient: CCHTTPClient) {
        self.httpClient = httpClient
    }
    
    // MARK: - Add-on CRUD Operations
    
    /// Get all add-ons for the current user
    /// - Returns: Publisher with array of CCAddon objects
    public func getUserAddons() -> AnyPublisher<[CCAddon], CCError> {
        debugLog("🚀 CCAddonService.getUserAddons() called")
        // Try personal space first, then fallback to user addons
        return httpClient.get("/self/addons", apiVersion: .v2)
            .catch { error -> AnyPublisher<[CCAddon], CCError> in
                debugLog("⚠️ /self/addons failed, trying profile space...")
                return self.httpClient.get("/self/addons", apiVersion: .v2)
            }
            .eraseToAnyPublisher()
    }
    
    /// Get add-ons for a specific organization
    /// - Parameter organizationId: The organization ID
    /// - Returns: Publisher with array of CCAddon objects
    public func getAddons(forOrganization organizationId: String) -> AnyPublisher<[CCAddon], CCError> {
        return httpClient.get("/organisations/\(organizationId)/addons", apiVersion: .v2)
    }
    
    /// Get a specific add-on by ID
    /// - Parameters:
    ///   - addonId: The add-on ID
    ///   - organizationId: Optional organization ID (nil for user add-ons)
    /// - Returns: Publisher with CCAddon object
    public func getAddon(addonId: String, organizationId: String? = nil) -> AnyPublisher<CCAddon, CCError> {
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/addons/\(addonId)"
        } else {
            endpoint = "/self/addons/\(addonId)"
        }
        return httpClient.get(endpoint, apiVersion: .v2)
    }
    
    // MARK: - Add-on Creation (providers methods already exist above)
    
    /// Preorder an add-on to validate configuration and get pricing
    /// - Parameters:
    ///   - request: The add-on creation request
    ///   - organizationId: Optional organization ID
    /// - Returns: Publisher with CCAddonPreorderResponse object
    public func preorderAddon(
        request: CCAddonCreationRequest,
        organizationId: String? = nil
    ) -> AnyPublisher<CCAddonPreorderResponse, CCError> {
        debugLog("🚀 CCAddonService.preorderAddon(name: \(request.name)) called")
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/addons/preorders"
        } else {
            endpoint = "/self/addons/preorders"
        }
        return httpClient.post(endpoint, body: request, apiVersion: .v2)
    }
    
    /// Create a new add-on using the new creation request model
    /// - Parameters:
    ///   - request: The add-on creation request
    ///   - organizationId: Optional organization ID
    /// - Returns: Publisher with created CCAddon object
    public func createAddon(
        request: CCAddonCreationRequest,
        organizationId: String? = nil
    ) -> AnyPublisher<CCAddon, CCError> {
        debugLog("🚀 CCAddonService.createAddon(name: \(request.name)) called")
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/addons"
        } else {
            endpoint = "/self/addons"
        }
        return httpClient.post(endpoint, body: request, apiVersion: .v2)
    }
    
    /// Create a new add-on (legacy method)
    /// - Parameters:
    ///   - addon: CCAddonCreate object with add-on details
    ///   - organizationId: Optional organization ID (defaults to user add-ons)
    /// - Returns: Publisher with created CCAddon object
    public func createAddon(
        _ addon: CCAddonCreate,
        organizationId: String? = nil
    ) -> AnyPublisher<CCAddon, CCError> {
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/addons"
        } else {
            endpoint = "/self/addons"
        }
        return httpClient.post(endpoint, body: addon, apiVersion: .v2)
    }
    
    /// Update an existing add-on
    /// - Parameters:
    ///   - addonId: The add-on ID to update
    ///   - update: CCAddonUpdate object with changes
    ///   - organizationId: Optional organization ID (nil for user add-ons)
    /// - Returns: Publisher with updated CCAddon object
    public func updateAddon(
        addonId: String,
        update: CCAddonUpdate,
        organizationId: String? = nil
    ) -> AnyPublisher<CCAddon, CCError> {
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/addons/\(addonId)"
        } else {
            endpoint = "/self/addons/\(addonId)"
        }
        return httpClient.put(endpoint, body: update, apiVersion: .v2)
    }
    
    /// Delete an add-on
    /// - Parameters:
    ///   - addonId: The add-on ID to delete
    ///   - organizationId: Optional organization ID (nil for user add-ons)
    /// - Returns: Publisher indicating completion
    public func deleteAddon(addonId: String, organizationId: String? = nil) -> AnyPublisher<EmptyResponse, CCError> {
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/addons/\(addonId)"
        } else {
            endpoint = "/self/addons/\(addonId)"
        }
        return httpClient.delete(endpoint, apiVersion: .v2)
    }
    
    // MARK: - Add-on Environment Variables
    
    /// Get environment variables for an add-on
    /// - Parameters:
    ///   - addonId: The add-on ID
    ///   - organizationId: Optional organization ID (nil for user add-ons)
    /// - Returns: Publisher with dictionary of environment variables
    public func getAddonEnvironmentVariables(
        addonId: String,
        organizationId: String? = nil
    ) -> AnyPublisher<[String: String], CCError> {
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/addons/\(addonId)/env"
        } else {
            endpoint = "/self/addons/\(addonId)/env"
        }
        
        debugLog("🔍 [CCAddonService] Getting environment variables from endpoint: \(endpoint)")
        
        // First try to decode as array of environment variable objects
        let arrayPublisher: AnyPublisher<[EnvironmentVariable], CCError> = httpClient.get(endpoint, apiVersion: .v2)
        
        return arrayPublisher
            .map { envArray -> [String: String] in
                var dict: [String: String] = [:]
                for env in envArray {
                    dict[env.name] = env.value
                }
                debugLog("✅ [CCAddonService] Converted \(envArray.count) environment variables to dictionary")
                return dict
            }
            .catch { error -> AnyPublisher<[String: String], CCError> in
                debugLog("⚠️ [CCAddonService] Failed to decode as array, trying as dictionary: \(error)")
                // If array fails, try as dictionary
                return self.httpClient.get(endpoint, apiVersion: .v2)
            }
            .handleEvents(
                receiveOutput: { variables in
                    debugLog("✅ [CCAddonService] Final result: \(variables.count) environment variables")
                    for (key, value) in variables {
                        debugLog("   - \(key): \(value.prefix(50))...")
                    }
                },
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        debugLog("❌ [CCAddonService] Failed to get environment variables: \(error)")
                    }
                }
            )
            .eraseToAnyPublisher()
    }
    
    // MARK: - Add-on Providers & Plans
    
    /// Get all available add-on providers
    /// - Returns: Publisher with array of CCAddonProvider objects
    public func getAddonProviders() -> AnyPublisher<[CCAddonProvider], CCError> {
        return httpClient.get("/products/addonproviders", apiVersion: .v2)
    }
    
    /// Get add-on provider details including plans
    /// - Parameter providerId: The provider ID (e.g., "postgresql", "redis")
    /// - Returns: Publisher with CCAddonProvider object
    public func getAddonProvider(providerId: String) -> AnyPublisher<CCAddonProvider, CCError> {
        return httpClient.get("/products/addonproviders/\(providerId)", apiVersion: .v2)
    }
    
    /// Get available plans for a provider
    /// - Parameter providerId: The provider ID
    /// - Returns: Publisher with array of CCAddonPlan objects
    public func getAddonPlans(forProvider providerId: String) -> AnyPublisher<[CCAddonPlan], CCError> {
        return httpClient.get("/products/addonproviders/\(providerId)/plans", apiVersion: .v2)
    }
    
    // MARK: - Add-on Application Links
    
    /// Get applications linked to an add-on
    /// - Parameters:
    ///   - addonId: The add-on ID
    ///   - organizationId: Optional organization ID (nil for user add-ons)
    /// - Returns: Publisher with array of linked application information
    public func getLinkedApplications(
        addonId: String,
        organizationId: String? = nil
    ) -> AnyPublisher<[CCAddonApplicationLink], CCError> {
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/addons/\(addonId)/applications"
        } else {
            endpoint = "/self/addons/\(addonId)/applications"
        }
        
        debugLog("🔗 [CCAddonService] Getting linked applications from endpoint: \(endpoint)")
        
        // Try first as array of strings
        return httpClient.get(endpoint, apiVersion: .v2)
            .catch { error -> AnyPublisher<[String], CCError> in
                debugLog("⚠️ [CCAddonService] Failed to decode as strings, trying as objects: \(error)")
                
                // If strings fail, try as array of objects
                return self.httpClient.get(endpoint, apiVersion: .v2)
                    .catch { _ -> AnyPublisher<[CCAddonApplicationLink], CCError> in
                        debugLog("⚠️ [CCAddonService] Failed to decode as objects, returning empty")
                        return Just([])
                            .setFailureType(to: CCError.self)
                            .eraseToAnyPublisher()
                    }
                    .map { (links: [CCAddonApplicationLink]) -> [String] in
                        return links.map { $0.appId }
                    }
                    .eraseToAnyPublisher()
            }
            .map { (appIds: [String]) -> [CCAddonApplicationLink] in
                debugLog("📱 [CCAddonService] Received \(appIds.count) app IDs")
                return appIds.map { appId in
                    debugLog("   - App ID: \(appId)")
                    return CCAddonApplicationLink(
                        appId: appId,
                        name: "Application",
                        realId: nil
                    )
                }
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Add-on Tags Management
    
    /// Get tags for an add-on
    /// - Parameters:
    ///   - addonId: The add-on ID
    ///   - organizationId: Optional organization ID (nil for user add-ons)
    /// - Returns: Publisher with array of tags
    public func getAddonTags(
        addonId: String,
        organizationId: String? = nil
    ) -> AnyPublisher<[String], CCError> {
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/addons/\(addonId)/tags"
        } else {
            endpoint = "/self/addons/\(addonId)/tags"
        }
        return httpClient.get(endpoint, apiVersion: .v2)
    }
    
    /// Add a tag to an add-on
    /// - Parameters:
    ///   - addonId: The add-on ID
    ///   - tag: Tag to add
    ///   - organizationId: Optional organization ID (nil for user add-ons)
    /// - Returns: Publisher indicating completion
    public func addAddonTag(
        addonId: String,
        tag: String,
        organizationId: String? = nil
    ) -> AnyPublisher<EmptyResponse, CCError> {
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/addons/\(addonId)/tags/\(tag)"
        } else {
            endpoint = "/self/addons/\(addonId)/tags/\(tag)"
        }
        return httpClient.put(endpoint, body: EmptyRequest(), apiVersion: .v2)
    }
    
    /// Remove a tag from an add-on
    /// - Parameters:
    ///   - addonId: The add-on ID
    ///   - tag: Tag to remove
    ///   - organizationId: Optional organization ID (nil for user add-ons)
    /// - Returns: Publisher indicating completion
    public func removeAddonTag(
        addonId: String,
        tag: String,
        organizationId: String? = nil
    ) -> AnyPublisher<EmptyResponse, CCError> {
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/addons/\(addonId)/tags/\(tag)"
        } else {
            endpoint = "/self/addons/\(addonId)/tags/\(tag)"
        }
        return httpClient.delete(endpoint, apiVersion: .v2)
    }
    
    /// Replace all tags for an add-on
    /// - Parameters:
    ///   - addonId: The add-on ID
    ///   - tags: Array of new tags
    ///   - organizationId: Optional organization ID (nil for user add-ons)
    /// - Returns: Publisher with updated tags
    public func replaceAddonTags(
        addonId: String,
        tags: [String],
        organizationId: String? = nil
    ) -> AnyPublisher<[String], CCError> {
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/addons/\(addonId)/tags"
        } else {
            endpoint = "/self/addons/\(addonId)/tags"
        }
        return httpClient.put(endpoint, body: tags, apiVersion: .v2)
    }
    
    // MARK: - Add-on Migration & Plan Changes
    
    /// Change add-on plan (upgrade/downgrade)
    /// - Parameters:
    ///   - addonId: The add-on ID
    ///   - newPlanId: New plan ID
    ///   - organizationId: Optional organization ID (nil for user add-ons)
    /// - Returns: Publisher indicating completion
    public func changeAddonPlan(
        addonId: String,
        newPlanId: String,
        organizationId: String? = nil
    ) -> AnyPublisher<EmptyResponse, CCError> {
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/addons/\(addonId)/plan"
        } else {
            endpoint = "/self/addons/\(addonId)/plan"
        }
        
        let body = AddonPlanChangeRequest(plan: newPlanId)
        return httpClient.put(endpoint, body: body, apiVersion: .v2)
    }
    
    // MARK: - Add-on SSO & Authentication
    
    /// Get single sign-on data for an add-on
    /// - Parameters:
    ///   - addonId: The add-on ID
    ///   - organizationId: Optional organization ID (nil for user add-ons)
    /// - Returns: Publisher with SSO data
    public func getAddonSSOData(
        addonId: String,
        organizationId: String? = nil
    ) -> AnyPublisher<CCAddonSSOData, CCError> {
        let endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/addons/\(addonId)/sso"
        } else {
            endpoint = "/self/addons/\(addonId)/sso"
        }
        return httpClient.get(endpoint, apiVersion: .v2)
    }
    
    // MARK: - Add-on Logs
    
    /// Get logs for an add-on (v4 SSE).
    ///
    /// Migrates off the deprecated `/v2/logs/{addonId}` endpoint (sunset 2026-05-23). The v4 logs API
    /// uses a dedicated `resources` route — distinct from the `applications` route — keyed on the
    /// add-on's `realId` (e.g. `postgresql_xxx`, `redis_xxx`, …) and the owner ID. Mirrors what
    /// clever-tools does via `ResourceLogStream`. External SaaS add-ons (Mailpace, Mailtrap, etc.)
    /// have a `nil` realId and surface as a 404.
    ///
    /// - Parameters:
    ///   - addon: The add-on. Its `realId` is used as the resource ID.
    ///   - ownerId: Owner ID for the add-on. For personal add-ons this is the `user_xxx` id; for
    ///              org add-ons the `orga_xxx` id. Required — v4 has no `/self/` form for resources.
    ///   - limit: Maximum number of logs to retrieve (default: 100).
    ///   - since: Earliest log timestamp; defaults to 24h ago.
    /// - Returns: Publisher with array of log entries (newest-first).
    public func getAddonLogs(
        addon: CCAddon,
        ownerId: String?,
        limit: Int = 100,
        since: Date? = nil
    ) -> AnyPublisher<[CCLogEntry], CCError> {
        debugLog("🔍 [CCAddonService] getAddonLogs called for addon.id=\(addon.id) name=\(addon.name) provider=\(addon.provider.id) realId=\(addon.realId ?? "nil") owner=\(ownerId ?? "nil")")

        guard let realId = addon.realId, !realId.isEmpty else {
            debugLog("⚠️ [CCAddonService] Add-on \(addon.id) has no realId; returning 404 (logs unavailable)")
            return Fail(error: CCError.httpError(
                statusCode: 404,
                message: "Logs not available for this add-on type"
            )).eraseToAnyPublisher()
        }

        guard let ownerId = ownerId, !ownerId.isEmpty else {
            debugLog("⚠️ [CCAddonService] Missing ownerId for addon \(addon.id); v4 resources route requires it")
            return Fail(error: CCError.httpError(
                statusCode: 404,
                message: "Logs not available (missing owner context)"
            )).eraseToAnyPublisher()
        }

        let sinceDate = since ?? Date().addingTimeInterval(-24 * 3600)
        let sinceStr = ISO8601DateFormatter().string(from: sinceDate)

        let endpoint = "/logs/organisations/\(ownerId)/resources/\(realId)/logs?limit=\(limit)&since=\(sinceStr)"

        debugLog("🔍 [CCAddonService] SSE endpoint: \(endpoint)")

        return httpClient.getSSEData(endpoint, apiVersion: .v4, timeout: 10.0)
            .handleEvents(
                receiveOutput: { data in
                    debugLog("📦 [CCAddonService] SSE response received: \(data.count) bytes")
                    if let preview = String(data: data.prefix(800), encoding: .utf8), !preview.isEmpty {
                        debugLog("📄 [CCAddonService] SSE preview (first 800 bytes):\n\(preview)")
                    } else {
                        debugLog("📄 [CCAddonService] SSE response is empty or non-UTF8")
                    }
                },
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        debugLog("❌ [CCAddonService] SSE failure: \(error)")
                    }
                }
            )
            .map { data -> [CCLogEntry] in
                let sseText = String(data: data, encoding: .utf8) ?? ""
                let entries = CCLogEntry.parseSSEStream(sseText)
                debugLog("✅ [CCAddonService] Parsed \(entries.count) log entries from SSE stream (input \(sseText.count) chars)")
                return entries
            }
            .eraseToAnyPublisher()
    }

    /// Open a persistent SSE stream of add-on resource logs. The connection stays alive until the
    /// subscriber cancels — the server first emits a short replay of recent history, then live
    /// entries as they are produced. Each `CCLogEntry` is delivered on the main queue.
    /// - Parameters:
    ///   - addon: The add-on. Must have a non-empty `realId` (e.g. `postgresql_…`).
    ///   - ownerId: Owner ID (`user_xxx` for personal, `orga_xxx` for org). Required.
    public func streamAddonLogs(
        addon: CCAddon,
        ownerId: String?
    ) -> AnyPublisher<CCLogEntry, CCError> {
        debugLog("🔍 [CCAddonService] streamAddonLogs called for addon.id=\(addon.id) realId=\(addon.realId ?? "nil") owner=\(ownerId ?? "nil")")

        guard let realId = addon.realId, !realId.isEmpty else {
            return Fail(error: CCError.httpError(statusCode: 404, message: "Logs not available for this add-on type")).eraseToAnyPublisher()
        }
        guard let ownerId = ownerId, !ownerId.isEmpty else {
            return Fail(error: CCError.httpError(statusCode: 404, message: "Logs not available (missing owner context)")).eraseToAnyPublisher()
        }

        // 15-minute replay window so the view isn't empty on open; the live tail continues from there.
        let sinceStr = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-15 * 60))
        let endpoint = "/logs/organisations/\(ownerId)/resources/\(realId)/logs?since=\(sinceStr)"
        return httpClient.streamSSE(endpoint, apiVersion: .v4)
            .compactMap { event -> CCLogEntry? in
                guard event.name == "RESOURCE_LOG" else { return nil }
                return CCLogEntry.parseSSEEventData(event.data)
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Add-on Metrics
    
    /// Get metrics for an add-on
    /// - Parameters:
    ///   - addonId: The add-on ID
    ///   - organizationId: Optional organization ID (nil for user add-ons)
    ///   - period: Time period for metrics (e.g., "PT1H", "PT24H", "P7D", "P30D")
    /// - Returns: Publisher with add-on metrics
    public func getAddonMetrics(
        addonId: String,
        organizationId: String? = nil,
        period: String = "PT24H"
    ) -> AnyPublisher<CCAddonMetrics, CCError> {
        
        guard let orgId = organizationId else {
            // Can't get metrics without organization ID
            return Fail(error: CCError.invalidParameters("Organization ID required for metrics"))
                .eraseToAnyPublisher()
        }
        
        debugLog("📊 [CCAddonService] Getting metrics for addon: \(addonId)")
        debugLog("📊 [CCAddonService] Step 1: Getting metrics token...")
        
        // First get the metrics token
        return getMetricsToken(organizationId: orgId)
            .flatMap { [weak self] tokenResponse -> AnyPublisher<CCAddonMetrics, CCError> in
                guard let self = self else {
                    return Fail(error: CCError.unknown(NSError(domain: "CCAddonService", code: 0)))
                        .eraseToAnyPublisher()
                }
                
                guard let token = tokenResponse["token"] as? String else {
                    debugLog("❌ [CCAddonService] No token in response")
                    return Fail(error: CCError.invalidResponse)
                        .eraseToAnyPublisher()
                }
                
                debugLog("✅ [CCAddonService] Got metrics token: \(token.prefix(20))...")
                debugLog("📊 [CCAddonService] Step 2: Getting metrics with token...")
                
                // Now use the token to get metrics from v4 API
                // Try the standard endpoint but with token as query parameter
                let v4Endpoint = "/stats/organisations/\(orgId)/resources/\(addonId)/metrics"
                
                // Add period and token as query parameters
                let queryItems = [
                    URLQueryItem(name: "interval", value: period),
                    URLQueryItem(name: "token", value: token)  // Try passing token as query param
                ]
                var urlComponents = URLComponents()
                urlComponents.queryItems = queryItems
                let queryString = urlComponents.query ?? ""
                let fullEndpoint = queryString.isEmpty ? v4Endpoint : "\(v4Endpoint)?\(queryString)"
                
                debugLog("🔍 [CleverMetrics] Requesting v4 metrics with token [endpoint=\(fullEndpoint), addonId=\(addonId), organizationId=\(orgId), period=\(period), tokenPrefix=\(token.prefix(20))]")
                
                // Create custom request with Bearer token
                return self.httpClient.requestWithBearerToken(
                    method: .GET,
                    endpoint: fullEndpoint,
                    token: token,
                    apiVersion: .v4
                )
                .handleEvents(
                    receiveOutput: { (metrics: CCAddonMetrics) in
                        debugLog("✅ [CCAddonService] Successfully received metrics from v4 API")
                        debugLog("🔍 [CleverMetrics] Successfully received v4 metrics [addonId=\(addonId), endpoint=\(fullEndpoint)]")
                    },
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            debugLog("❌ [CCAddonService] Failed to get v4 metrics: \(error)")
                            debugLog("❌ [CleverMetrics] Failed to get v4 metrics [error=\(error.localizedDescription), endpoint=\(fullEndpoint), addonId=\(addonId), organizationId=\(orgId)]")
                        }
                    }
                )
                .eraseToAnyPublisher()
            }
            .catch { error -> AnyPublisher<CCAddonMetrics, CCError> in
                // If metrics token or v4 fails, try v2 endpoint as fallback
                debugLog("⚠️ [CCAddonService] Metrics token or V4 failed, trying v2 fallback: \(error)")
                let v2Endpoint = "/organisations/\(orgId)/applications/\(addonId)/metrics?span=\(period)"
                
                debugLog("🔍 [CleverMetrics] Falling back to v2 endpoint [endpoint=\(v2Endpoint), reason=\(error.localizedDescription)]")
                
                return self.httpClient.get(v2Endpoint, apiVersion: .v2)
            }
            .eraseToAnyPublisher()
    }
    
    /// Get consumption statistics for an add-on
    /// - Parameters:
    ///   - addonId: The add-on ID
    ///   - organizationId: Optional organization ID (nil for user add-ons)
    ///   - from: Start date for statistics
    ///   - to: End date for statistics
    /// - Returns: Publisher with consumption statistics
    public func getAddonConsumption(
        addonId: String,
        organizationId: String? = nil,
        from: Date? = nil,
        to: Date? = nil
    ) -> AnyPublisher<CCAddonConsumption, CCError> {
        var endpoint: String
        if let orgId = organizationId {
            endpoint = "/organisations/\(orgId)/addons/\(addonId)/consumption"
        } else {
            endpoint = "/self/addons/\(addonId)/consumption"
        }
        
        // Add date parameters if provided
        var queryParams: [String] = []
        if let fromDate = from {
            let formatter = ISO8601DateFormatter()
            queryParams.append("from=\(formatter.string(from: fromDate))")
        }
        if let toDate = to {
            let formatter = ISO8601DateFormatter()
            queryParams.append("to=\(formatter.string(from: toDate))")
        }
        
        if !queryParams.isEmpty {
            endpoint += "?" + queryParams.joined(separator: "&")
        }
        
        debugLog("💰 [CCAddonService] Getting consumption from endpoint: \(endpoint)")
        
        return httpClient.get(endpoint, apiVersion: .v2)
            .eraseToAnyPublisher()
    }
    
    /// Get time series metrics for an add-on (for charts)
    /// - Parameters:
    ///   - addonId: The add-on ID
    ///   - organizationId: Optional organization ID (nil for user add-ons)
    ///   - metric: Metric type (e.g., "cpu", "memory", "connections", "queries")
    ///   - interval: Data point interval (e.g., "5m", "1h", "1d")
    ///   - from: Start time
    ///   - to: End time
    /// - Returns: Publisher with time series data
    public func getAddonTimeSeries(
        addonId: String,
        organizationId: String? = nil,
        metric: String,
        interval: String = "5m",
        from: Date? = nil,
        to: Date? = nil
    ) -> AnyPublisher<[CCAddonMetricPoint], CCError> {
        var endpoint: String
        if let orgId = organizationId {
            endpoint = "/stats/organisations/\(orgId)/resources/\(addonId)/metrics"
        } else {
            endpoint = "/stats/organisations/self/resources/\(addonId)/metrics"
        }
        
        // Build query parameters for v4 API
        var queryParams: [String] = []
        
        // Add metric filter
        queryParams.append("only=\(metric)")
        
        // Add interval
        queryParams.append("interval=\(interval)")
        
        // Calculate span based on from/to dates
        if let fromDate = from, let toDate = to {
            let timeInterval = toDate.timeIntervalSince(fromDate)
            let hours = Int(timeInterval / 3600)
            if hours < 24 {
                queryParams.append("span=\(hours)h")
            } else {
                let days = hours / 24
                queryParams.append("span=\(days)d")
            }
            
            // Add end date
            let formatter = ISO8601DateFormatter()
            queryParams.append("end=\(formatter.string(from: toDate))")
        } else {
            // Default to 24h if no dates provided
            queryParams.append("span=24h")
        }
        
        // Add fill parameter to handle missing data points
        queryParams.append("fill=null")
        
        endpoint += "?" + queryParams.joined(separator: "&")
        
        debugLog("📈 [CCAddonService] Getting time series for metric '\(metric)' from: \(endpoint)")
        
        // Log detailed request info
        debugLog("🔍 [CleverMetrics] Requesting time series [endpoint=\(endpoint), addonId=\(addonId), organizationId=\(organizationId ?? "nil"), metric=\(metric), interval=\(interval), span=\(queryParams.first { $0.contains("span=") } ?? "unknown"), apiVersion=v4]")
        
        return httpClient.get(endpoint, apiVersion: .v4)
            .handleEvents(
                receiveOutput: { dataPoints in
                    debugLog("🔍 [CleverMetrics] Successfully received time series [metric=\(metric), dataPointsCount=\(dataPoints.count), endpoint=\(endpoint)]")
                },
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        debugLog("❌ [CleverMetrics] Failed to get time series [error=\(error.localizedDescription), endpoint=\(endpoint), metric=\(metric), addonId=\(addonId)]")
                    }
                }
            )
            .eraseToAnyPublisher()
    }
    
    // MARK: - Convenience Methods
    
    /// Get all add-ons with provider details (enriched data)
    /// - Parameter organizationId: Optional organization ID
    /// - Returns: Publisher with enriched add-on data
    public func getAddonsWithProviderDetails(organizationId: String? = nil) -> AnyPublisher<[CCAddonWithProvider], CCError> {
        let addonsPublisher = organizationId != nil 
            ? getAddons(forOrganization: organizationId!)
            : getUserAddons()
            
        return addonsPublisher
            .flatMap { [weak self] addons -> AnyPublisher<[CCAddonWithProvider], CCError> in
                guard let self = self else {
                    return Fail(error: CCError.invalidParameters("Service instance not available"))
                        .eraseToAnyPublisher()
                }
                
                let enrichedPublishers = addons.map { addon in
                    self.getAddonProvider(providerId: addon.provider.id)
                        .map { provider in
                            CCAddonWithProvider(addon: addon, provider: provider)
                        }
                        .catch { _ in
                            // If provider fetch fails, create addon with nil provider
                            Just(CCAddonWithProvider(addon: addon, provider: nil))
                                .setFailureType(to: CCError.self)
                        }
                        .eraseToAnyPublisher()
                }
                
                return Publishers.MergeMany(enrichedPublishers)
                    .collect()
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Metrics Token (Experimental)
    
    /// Get metrics token for organization (experimental - undocumented endpoint)
    /// - Parameter organizationId: Organization ID
    /// - Returns: Publisher with metrics token response
    public func getMetricsToken(organizationId: String) -> AnyPublisher<[String: Any], CCError> {
        // Remove the /v2/ prefix since httpClient.get will add it
        let endpoint = "/metrics/read/\(organizationId)"
        
        return httpClient.requestRaw(
            method: .GET,
            endpoint: endpoint,
            apiVersion: .v2
        )
        .tryMap { data in
            // First, try to get the raw string response
            if let rawString = String(data: data, encoding: .utf8) {
                // If it's a plain text token, wrap it in a dictionary
                if !rawString.hasPrefix("{") && !rawString.hasPrefix("[") {
                    return ["token": rawString.trimmingCharacters(in: .whitespacesAndNewlines)]
                }
                
                // Otherwise try to parse as JSON
                if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    return json
                }
            }
            
            throw CCError.parsingError(NSError(domain: "CCAddonService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to parse metrics response"]))
        }
        .mapError { error in
            if let ccError = error as? CCError {
                return ccError
            }
            return CCError.networkError(error)
        }
        .eraseToAnyPublisher()
    }
}

// MARK: - Supporting Models

/// Enriched add-on model with provider information
public struct CCAddonWithProvider: Identifiable {
    public let id: String
    public let addon: CCAddon
    public let provider: CCAddonProvider?
    
    public init(addon: CCAddon, provider: CCAddonProvider?) {
        self.id = addon.id
        self.addon = addon
        self.provider = provider
    }
}

/// Model for add-on application links
public struct CCAddonApplicationLink: Codable, Identifiable {
    public let id = UUID()
    public let appId: String
    public let name: String
    public let realId: String?
    
    enum CodingKeys: String, CodingKey {
        case appId = "app_id"
        case name
        case realId = "real_id"
    }
    
    // Public initializer
    public init(appId: String, name: String, realId: String? = nil) {
        self.appId = appId
        self.name = name
        self.realId = realId
    }
    
    // Custom decoder to handle different API response formats
    public init(from decoder: Decoder) throws {
        // Try to decode from a single string value (just app ID)
        if let singleValue = try? decoder.singleValueContainer(),
           let appIdString = try? singleValue.decode(String.self) {
            self.appId = appIdString
            self.name = "Application"
            self.realId = nil
            return
        }
        
        // Try to decode from a dictionary
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Standard decoding
        self.appId = try container.decode(String.self, forKey: .appId)
        self.name = (try? container.decode(String.self, forKey: .name)) ?? "Unknown App"
        self.realId = try? container.decode(String.self, forKey: .realId)
    }
}

/// Model for add-on SSO data
public struct CCAddonSSOData: Codable {
    public let url: String?
    public let token: String?
    public let nav_data: String?
    
    public init(url: String? = nil, token: String? = nil, nav_data: String? = nil) {
        self.url = url
        self.token = token
        self.nav_data = nav_data
    }
}

/// Request model for changing add-on plan
private struct AddonPlanChangeRequest: Codable {
    let plan: String
}

/// Model for environment variable from API
private struct EnvironmentVariable: Codable {
    let name: String
    let value: String
} 