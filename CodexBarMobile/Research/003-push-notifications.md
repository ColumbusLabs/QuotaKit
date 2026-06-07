
- **Created**: 2026-04-01
- **Superseded by**: [004-alert-push-cloudkit.md](004-alert-push-cloudkit.md)







---






|------|------|

- **depleted**: session remaining ≤ 0.01% → `"{Provider} session depleted"`

- `wasDepleted && !isDepleted` → `.restored`
- `!wasDepleted && isDepleted` → `.depleted`


|----------|------|------|



```
Mac (UsageStore) → SyncCoordinator → CloudKit (DeviceSnapshot)
                                         ↓ CKQuerySubscription
```




```
```







### Step 3: SessionQuotaMonitor

### Step 4: LocalNotificationManager
