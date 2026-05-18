# 版本号命名规则

> 任何看这个项目的新 agent，3 分钟看完这一页就够了。

## 4 个版本变量，全在 `version.env`

```
MARKETING_VERSION=0.26.1     # Mac fork 版本，对外可见
BUILD_NUMBER=63.2            # Mac CFBundleVersion，单调递增
MOBILE_VERSION=1.7.0         # 配套的 iOS 版本，独立轨道
UPSTREAM_VERSION=v0.26.1     # 最后一次同步的上游 tag
```

## 每个怎么定

### `MARKETING_VERSION` —— 跟着上游走

| 情况 | 版本号 |
|------|--------|
| Fork 同步到 upstream v0.26.1，没有 fork 端用户可感知的额外功能 | `0.26.1` |
| 同步到 upstream v0.26.1，**但 fork 在它上面又改了 Mac UI（用户能看到的）** | `0.26.2` |
| 同步到 upstream v0.26.1，**fork 又在 0.26.2 上面继续改 Mac UI** | `0.26.3` |

**核心规则**：fork-private 的"iOS bridge / 内部 plumbing / 测试"**不算** Mac UI 改动，**不 bump** MARKETING_VERSION。只有 Mac 菜单/Settings/Provider 卡片这些用户能看到的地方真的变了，才 +.1。

### `BUILD_NUMBER` —— subdecimal patch level

Upstream v0.26.1 的 BUILD_NUMBER 是 `63`。Fork 在上面打 patch 用 `63.1` / `63.2` / `63.3`。

| 情况 | BUILD_NUMBER |
|------|--------------|
| 刚 merge 上游 v0.26.1，没动 | 63 |
| Fork 第 1 次在 v0.26.1 上 commit（fix/bridge/test 都算） | 63.1 |
| Fork 第 2 次再改 | 63.2 |
| Upstream 出了 v0.27.0（BUILD_NUMBER 例如 65），fork 再次 sync | 65（然后下次 fork 改成 65.1） |

**关键**：fork 的 BUILD_NUMBER 永远是 `<upstream 整数>.<fork 计数器>`。`Mac BUILD_NUMBER scheme — fork patches use subdecimal (61.2), never advance upstream's integer`（来源：项目 memory）。

### `MOBILE_VERSION` —— iOS 自己的节奏

跟 Mac MARKETING_VERSION **完全独立**。它只表示"这个 Mac release 配的 iOS 版本是哪个"。

| 情况 | MOBILE_VERSION |
|------|----------------|
| 用户 iPhone 上目前是 1.6.0，Mac 现在出新版本但 iOS 没动 | `1.6.0` |
| iOS 也 ship 了新版本 1.7.0 | `1.7.0` |
| iOS bump 到 1.7.1（小修） | `1.7.1` |

**关键**：发 Mac release 前问一下：用户 iPhone 上现在装的是哪个版本？写那个版本。如果发 Mac 之后才要发 iOS 新版本，写 iOS 当前已发版本，等 iOS 新版本上 TestFlight/App Store 后，再发一次 Mac release（把 MOBILE_VERSION 改成新的）。

### `UPSTREAM_VERSION` —— 只是个 bookmark

记录"我们最后一次 merge 到的 upstream tag"。每次跑 merge 时手动改成新的（如 `v0.26.1` → `v0.27.0`）。不影响任何 binary 行为，只是给 agent 看的。

## 拼起来 —— release artifact 名字

```
Tag:        v{MARKETING_VERSION}-mobile.{MOBILE_VERSION}
            → v0.26.1-mobile.1.7.0

Zip:        CodexBar-{MARKETING_VERSION}-mobile.{MOBILE_VERSION}.zip
            → CodexBar-0.26.1-mobile.1.7.0.zip
```

## Sparkle appcast 里的版本号

Appcast `<item>` 里有两个版本字段：

```xml
<sparkle:version>63.2.1.7.0</sparkle:version>            <!-- 见下 -->
<sparkle:shortVersionString>0.26.1</sparkle:shortVersionString>  <!-- = MARKETING_VERSION -->
```

`sparkle:version` 是 Sparkle 用来做"新版本 vs 老版本"比较的，**必须单调递增**。我们的规则：

```
sparkle:version = BUILD_NUMBER + "." + MOBILE_VERSION
                = 63.2 + . + 1.7.0
                = 63.2.1.7.0
```

5 段数字，从前往后比，前面越大越新：
- 第 1 段 (`63`) = upstream 的 BUILD_NUMBER 整数
- 第 2 段 (`2`) = fork 在该 upstream 上的 patch 编号
- 第 3-5 段 (`1.7.0`) = MOBILE_VERSION

例子（按时间顺序，Sparkle 都认为后面 > 前面）：
```
61.2.1.5.3   ← upstream 0.25.1 base + fork 第 2 次 patch, 配 iOS 1.5.3
61.2.1.6.0   ← 同一个 Mac binary 但配套 iOS 升到了 1.6.0 (发新 release)
63.0.1.6.0   ← upstream 0.26.1 刚 merge, fork 没改, 配 iOS 1.6.0
63.2.1.6.0   ← fork 在 v0.26.1 上 patch 了 2 轮, 配 iOS 1.6.0
63.2.1.7.0   ← 同 Mac binary, 配 iOS 1.7.0 (发新 release)
```

> **Sparkle 6.1.x 是什么**：不是这个项目的版本号格式。Sparkle 这个**框架**自己有个版本（目前是 2.x），跟我们 binary 完全无关。我们项目里 `sparkle:version` 永远是上面那个 5 段格式。

## About 窗口显示什么

```
版本 0.26.1 (63.2.1.7.0) · Mobile 1.7.0
     ↑      ↑              ↑
     MARKETING_VERSION  sparkle:version  MOBILE_VERSION
                       (= BUILD_NUMBER+MOBILE_VERSION)
```

## 决策树 —— 我要发新 release，每个版本怎么填？

```
1. 上游有新 tag？(check `git fetch upstream --tags && git log v{current}..upstream/main`)
   ├─ 是 → merge 上游, 把 UPSTREAM_VERSION 改成新 tag
   │      把 MARKETING_VERSION 改成 upstream 的 (例如 v0.27.0 → MARKETING_VERSION=0.27.0)
   │      把 BUILD_NUMBER 改成 upstream 的 BUILD_NUMBER (整数, 不带 .X)
   └─ 否 → MARKETING_VERSION 不动, UPSTREAM_VERSION 不动

2. Fork 这次有改 Mac UI 用户能看到的东西吗？
   ├─ 是 → MARKETING_VERSION + .1  (0.26.1 → 0.26.2)
   │      BUILD_NUMBER 在 upstream 整数上 +.1  (63 → 63.1, 或 63.1 → 63.2)
   └─ 否（只改了 iOS bridge / 测试 / 文档） → MARKETING_VERSION 不动
          BUILD_NUMBER 在 upstream 整数上 +.1

3. iOS 这次也 ship 了新版本？
   ├─ 是 → MOBILE_VERSION 改成新 iOS 版本号
   └─ 否 → MOBILE_VERSION 保持上一个发的 Mac release 用的值
```

## 例子 —— 最近几次 release 怎么命名的

| Release tag | 上游同步到 | Fork 改了 Mac UI? | iOS 这次 ship 了? | 结果 |
|---|---|---|---|---|
| `v0.23.6-mobile.1.5.2` | v0.23 | 是 (mock injector) | 是 (1.5.2) | MARKETING=0.23.6, BUILD=58.6, MOBILE=1.5.2 |
| `v0.25.1-mobile.1.5.3` | v0.25.1 | 否 (只 fold-in) | 是 (1.5.3) | MARKETING=0.25.1, BUILD=61.1, MOBILE=1.5.3 |
| `v0.25.2-mobile.1.6.0` | v0.25.1 | 是 (quota warning push) | 是 (1.6.0) | MARKETING=0.25.2, BUILD=61.2, MOBILE=1.6.0 |
| `v0.26.1-mobile.1.7.0` | v0.26.1 | 否 (只是 iOS bridge) | 是 (1.7.0) | MARKETING=0.26.1, BUILD=63.2, MOBILE=1.7.0 |

## 一句话总结

- `MARKETING_VERSION` = 上游版本 + 可选 .N（fork 自己改 Mac UI 的次数）
- `BUILD_NUMBER` = 上游 BUILD_NUMBER 整数 + `.N`（fork patch 计数器，包括只有 iOS bridge 的 patch）
- `MOBILE_VERSION` = 这次 Mac release 对应的 iOS 当前版本
- `sparkle:version` = `{BUILD_NUMBER}.{MOBILE_VERSION}`（5 段单调递增）
