


---



```
   │  SyncCoordinator.buildProviderUsageSnapshot()   ← fork-owned bridge
   ▼
   ▼  JSON(ISO8601) → zlib(PayloadCompression)
CKRecord "DeviceProviderSnapshot".payload (blob)  in zone "DeviceProvidersZone"
   ▼  CloudKit push (CKRecordZoneSubscription)
```


|---|---|---|---|



---





```swift
public struct SyncDeepSeekUsage: Codable, Sendable, Equatable {
    public let todayTokens: Int
    public let monthTokens: Int
    public let todayCost: Double?
    public let monthCost: Double?
    public let todayRequests: Int
    public let monthRequests: Int
    public let topModel: String?
    public let currency: String
    public let totalBalanceUSD: Double?
    public let grantedBalanceUSD: Double?
    public let toppedUpBalanceUSD: Double?
    public let daily: [SyncDeepSeekDaily]
    public let updatedAt: Date
}
public struct SyncDeepSeekDaily: Codable, Sendable, Equatable {
    public let dayKey: String        // "yyyy-MM-dd"
    public let totalTokens: Int
    public let cost: Double?
    public let requestCount: Int
}
```












|---|---|---|---|





```swift
public let requestCount: Int?
public let requestCount: Int?
```

---


`SyncCoordinator.swift:535`：
```swift
if let metadata, metadata.supportsOpus, let t = snapshot?.tertiary {
    rateWindows.append(SyncRateWindow(label: metadata.opusLabel ?? "Sonnet", ... ))
}
```



---


|---|---|---|


---


- `"Tokens"` · `"Requests"` · `"Cost"` · `"Balance"` · `"Granted"` · `"Topped Up"` · `"Top model"`



---


|---|---|


---


|---|---|---|
