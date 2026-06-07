

|---|---|---|---|



```bash
cd CodexBarMobile && xcodegen generate

# iOS build
cd CodexBarMobile && xcodebuild -project CodexBarMobile.xcodeproj \
    -scheme CodexBarMobile \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug build > /tmp/cb_build.log 2>&1
echo "EXIT=$?"; grep -E 'BUILD (SUCCEEDED|FAILED)|error:' /tmp/cb_build.log | tail
```



```bash
cd CodexBarMobile
xcodebuild test -project CodexBarMobile.xcodeproj \
    -scheme CodexBarMobile \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -only-testing:CodexBarMobileTests/CWLSchemaTests \
    -only-testing:CodexBarMobileTests/CWLMigrationTests \
    2>&1 | grep -E 'Test Suite|passed|failed|error:'

swift test --no-parallel 2>&1 | tail -3
```


```bash
./Scripts/lint.sh lint    # swiftformat + swiftlint --strict + i18n audit + parser audit
```



   - `ContentView.swift:690` `contributionSection`(top 5 + Others + NavigationLink)
   - `ContentView.swift:741` `budgetSection`
   - `Models/CostShareService.swift:76` `displayProviders`

```bash
killall CodexBar 2>/dev/null
launchctl setenv CODEXBAR_MOCK_PROVIDERS 0
open -a /Applications/CodexBar.app
```




- ❌ `Sources/CodexBarCore/`
- ❌ secrets / `~/.codexbar-secrets/` / `.p8` / `.env`
- ❌ Mac `BUILD_NUMBER`
