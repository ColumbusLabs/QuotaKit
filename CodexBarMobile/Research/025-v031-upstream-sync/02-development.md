


---




|---|---|---|---|



```
ProviderUsageEnvelope { deviceID, deviceName, appVersion, mobileVersion,
                        syncTimestamp, notificationPushEnabled, provider }
  → JSONEncoder(.iso8601)            // CloudConstants.makeJSONEncoder()
```



```
   → SyncCoordinator.buildProviderUsageSnapshot (fork bridge)
   → ProviderUsageSnapshot → Envelope → JSON → zlib → CKRecord.payload
   → CloudSyncManager.pushPerProviderRecords  →→ CloudKit
```

---



|---|---|---|






---


```bash
git merge v0.31.0
```




---


### 4.1 `Shared/`（wire schema，fork-owned）

|---|---|


### 4.2 Mac bridge（`Sources/CodexBar/Sync/`，fork-owned）

|---|---|

### 4.3 iOS（`CodexBarMobile/`，fork-owned）

|---|---|


|---|---|
| `version.env` | `MARKETING_VERSION=0.31.0.1` · `BUILD_NUMBER=73.1` · `MOBILE_VERSION=1.10.0` · `UPSTREAM_VERSION=v0.31.0` · `UPSTREAM_SYNC_DATE=2026-05-30` |

---




---




---
