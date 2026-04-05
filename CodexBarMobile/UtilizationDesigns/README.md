# Utilization Chart Design Exploration

## 调研来源
- Apple WWDC22-24 Chart 设计指南
- Dribbble: NeuChart, TRATA Analytics, Mood Insights, Anearmala Stacked Bar
- Behance: iOS Charts Patterns, Dashboards & Data Visualization
- Mac 端 PlanUtilizationHistoryChartMenuView.swift 设计语言

## 设计原则
1. 横滑用 `.chartScrollableAxes(.horizontal)` + `.chartXVisibleDomain()`
2. Y 轴固定 0-100%，不自动缩放
3. 条形宽度固定 6pt，间距均匀
4. 深色/浅色模式兼容（neutral surface + semantic accent）
5. 下方详情行而不是弹窗（遵循 Mac 设计语言）
6. 多 Provider 用 stacked bar，限制 3-5 色 + Others
7. 选中用虚线 RuleMark + 底部文字

## Provider 内图表 — 10 套方案

| # | 风格 | 特点 |
|---|------|------|
| 1 | Mac 复刻 | 双层 bar（track+fill），index-based，固定宽度 |
| 2 | 渐变填充 | 单层 bar，provider color gradient，圆角 |
| 3 | 极简线条 | 折线图 + 面积填充，无 bar |
| 4 | 胶囊式 | 粗圆角 bar，大间距，暗色 track |
| 5 | 信号强度 | 细 bar 密排，类似音频波形 |
| 6 | 热力色阶 | 单层 bar，颜色从绿→黄→红映射使用率 |
| 7 | 圆点式 | 每个数据点用圆点大小+颜色表示使用率 |
| 8 | 阶梯式 | step line chart，强调阶段变化 |
| 9 | 双色对比 | 已用（彩色）+ 剩余（灰色）双层 bar |
| 10 | 迷你火花 | 超紧凑版，低高度，配合文字摘要 |

## Cost 总图表 — 10 套方案

| # | 风格 | 特点 |
|---|------|------|
| 1 | 堆叠柱状 | 每根柱子分段显示各 Provider |
| 2 | 分组柱状 | 每个时间点并排多根柱子 |
| 3 | 堆叠面积 | 面积图，各 Provider 颜色叠加 |
| 4 | 百分比堆叠 | 每根柱子满高 100%，内部比例 |
| 5 | 环形仪表 | 圆环显示总利用率，分段着色 |
| 6 | 总分线 | 总利用率折线 + 各 Provider 小折线 |
| 7 | 热力网格 | 日×Provider 矩阵，颜色深浅表示使用率 |
| 8 | 条纹进度 | 水平条纹，每行一个 Provider |
| 9 | 气泡散点 | X=时间，Y=Provider，气泡大小=使用率 |
| 10 | 仪表盘式 | 大数字总和 + 小柱状趋势 |
