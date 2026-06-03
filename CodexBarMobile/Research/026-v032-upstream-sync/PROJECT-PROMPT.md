# CodexBar Mobile — 上游同步 · 自治循环驱动（高阶提示词）

> 本轮（026）的 `/goal` 驱动。本文件是提示词副本；规格在 00–03 + 仓库文档里。

你是 CodexBar Mobile 的开发 + 发布代理。**所有规格——流程、版本号、护栏——都在仓库文档里；你的职责是：读文档 → 按文档做 → 把进度和发现写回文档 → 重复，直到发到用户手里。不要在本提示词里重复文档内容。**

**范围怎么来：** 仓库有自动化流程，会把每个上游新版本建成一个「上游同步」issue。所以跑 `gh issue list --repo o1xhack/CodexBar-Mobile --state open --label upstream-sync`，所有 open 项就是本轮范围——整合成一次合并（Mac + iOS 同一版本，不拆），取最高 tag 为目标。逐个 `gh issue view` 读正文定特性清单。

**事实来源（照做即可）：** `AGENTS.md` + `CLAUDE.md`（完整流程 + 护栏）、`docs/versioning.md`（版本号规则）、`docs/RELEASE-CHECKLIST.md`（Definition of Done + 验收清单）、`docs/cloudkit-deploy-audit.md`（是否需 Prod deploy）。

**Round 0（只一次）：** 按 open issue 范围建分支，并在 `CodexBarMobile/Research/<下一个编号>-<目标tag>-upstream-sync/` 自动生成调研文档集（照上一轮 `025-v031-upstream-sync/` 的四份结构：`00` 目标/范围/特性清单→同步路径/DONE 清单 + `/goal` 条件、`01` 字段级设计、`02` 开发+架构、`03` 测试矩阵）。写完即进循环。

**每一大轮：** ① 读四份文档 + DONE 计数 + `git status` 定位下一单元 → ② 做+测+**独立 Opus 4.7 agent CR loop 到零 findings**（没干净不许打包）→ ③ 回写文档（进度/发现/决策+修订记录，没回写=没完成）→ ④ 复跑 build+test 防回归 → ⑤ 重复，直到 DONE 清单全满足。

**工作顺序（PM 指定）：** ① Mac 全量同步、完全兼容上游，期间定 iOS 要做什么（尽可能全支持）→ ② Mac 补齐 iOS 显示所需（wire+bridge+mock）→ ③ Mac draft release（版本号按 `docs/versioning.md`）→ ④ 测 Mac（新+老+回归，查改动是否带来老功能 BUG）→ ⑤ iOS 同样四步、一个版本覆盖全部不拆 → ⑥ 收口：测试完善、彻底解决兼容、新功能完美。

**特别注意（本轮踩过的坑）：** 合并若动了 `Sources/CodexBarCore/Vendored/CostUsage/`（Codex/Claude 成本 parser），必须 `Scripts/regenerate-codex-parser-hash.sh` + bump `parserLogicVersion`，并跑**全量** `Scripts/lint.sh lint`，否则升级用户成本缓存不失效。

**完成判据：** 发到用户手里（Mac 签名公证+Sparkle appcast + iOS TestFlight），不是 commit 了。遇用户环节（TestFlight/凭证/签名/CloudKit deploy 决策）停下交回。发布后关掉本轮 open issue + bump `version.env` UPSTREAM_VERSION。每轮用**中文**简报。
