<!--
遗留 TODO（承继自 1.0.0/1.1.0 修订审阅，均未处理）：
- 不安全配置 opt-in 条款（后期补充，与 F12 一并考虑）
- OkHttp 能力全景按 5.5.0 的 delta 核对（重点 DNS）
- `okhttp-capabilities-summary.md` 等被引文档缺失待补
- EventListener 对取消的回调归属待对 5.5.0 源码核对
v1.1.0 修订详情见 git 历史（docs(constitution) v1.1.0 提交）。
-->

# moonhttp 项目宪法

## 核心原则

### I. 非侵入底座（不可妥协）

moonhttp 必须只通过 `moonbitlang/async` 的公开 API 与底座耦合，
禁止 fork、复制或 vendor 上游源码。

- 需要上游改动时，必须以 PR 回馈 `moonbitlang/async`
  （可行性报告侵入点 I1–I7，如发送缓冲 16KB、DNS 缓存）；PR 合并前必须采用
  非侵入替代方案，或在文档中显式声明能力降级。
- 对上游仓库（`moonbitlang/async` 及其他依赖上游）的任何代码改动、issue 或
  PR 提交，必须事先获得人工批准；未获批准时不得执行，agent 不得自主发起。
- ALPN、TLS 会话复用、ConnectionSpec 等深水区侵入（I10–I12）必须单列里程碑
  管理，不得阻塞主线能力。
- 理由：零 fork 保住底座升级路径；任何 fork 都会把上游演进变成永久维护负担；
  上游改动与 issue/PR 影响共享社区状态，决定权必须保留在人工。

### II. 性能优先

性能是与功能同等级的一等交付物，不是事后优化。

- 性能相关改动必须附带基准数据（复刻 round2/round3 等既有基准或新增基准）。
- 已实测的杠杆（连接池化 47–56×、定长帧、头块缓存、DNS 缓存等）必须保持不回归。
- 优化路径优先级：非侵入 ≥ 性能 > 简洁；“性能优先”仅在热路径成立，
  冷路径（配置、日志、工具）仍简洁优先。
- 侵入性性能改动（回馈上游的 PR 类改动）必须重点报告：在 plan/analyze 中
  单列章节，附侵入方案与非侵入方案的基准对比与理由。
- 性能基准以 async/http 中 Client 复用（连接池化后）为对比基线，
  证明 moonhttp 自身价值；同时保留 moonhttp 自身历史基线防回归。
- 理由：在 async/http 之上提升请求性能是本项目的立项动机之一。

### III. OkHttp 语义对齐

以 OkHttp 5.5.0 的能力全景为行为规范基准（升基准版本走 spec 变更流程）。

- 每项能力必须先写清 OkHttp 行为规格（参照 proj-init-docs 对应章节），再实现。
- 与 OkHttp 的语义差异必须显式记录并给出理由，不得悄悄偏移。
- OkHttp recipes 与测试场景（如 CacheTest）应当作为验收用例来源。
- Java/Android 特有能力（安全提供者体系、R8/ProGuard、版本支持窗口等）
  标记为 N/A，不构成工作项。
- 错误分类、超时归属与取消传播语义同样以 OkHttp 5.5.0 为基准；映射表及
  有意差异（如取消以显式 `Canceled` 变体而非错误消息区分）在 spec 中显式记录。
- 能力全景与 OkHttp 5.5.0 的差异须做一次 delta 核对（重点：DNS 新 API
  `Dns.newCall`/HTTPS RR、mockwebserver3 拆分、ECH 新能力标记远期）。

### IV. 验收场景与测试先行（不可妥协）

- 每项能力在动工前必须先有可审的验收场景（spec 用户故事/场景）与测试方案；
  实现以测试通过为完成判据，不允许"先写完再补测试"。
- 新行为与 bug 修复优先采用红-绿-重构循环：先写失败测试，再实现，再重构。
- `moon test` 必须全绿才能合入；断言优先 `assert_eq` / `assert_true`；
  结构化调试输出用 `derive(Debug)` + `debug_inspect` 快照。
- 关键子系统（缓存、cookie、URL 解析等）必须移植 OkHttp 对应测试场景对拍。
- 网络行为测试必须基于可控本地服务端，不得依赖外部网络环境。

### V. Target 策略

target 优先级固定为 native ≥ wasm > js = wasm-gc；js 与 wasm-gc
均不在验证面内，只要求显式标注与欠账跟踪。

- native 与 wasm 共享同一路径，能力必须等价（P0）。
- js 走 fetch 适配层，不在验证面内；能力状态记为「未验证」而非
  「已降级」（P1）。
- wasm-gc 被 async runtime（`@http` 编译图）阻塞，M5 之前不建 stub，
  仅跟踪上游进度并保留显式排除说明（P2）。
- 每项能力设计时必须显式标注 target 矩阵（native/wasm/js/wasm-gc）。

### VI. 简洁与接口纪律

- 从简单开始，遵循 YAGNI：不为假设的未来需求引入抽象。
- 每片改动后必须运行 `moon info && moon fmt`，并检查 `.mbti` diff——
  对外接口的任何变化必须是有意识的决定，而非意外泄漏。
- MoonBit 代码按 block 组织（`///|` 分隔，块序无关）；废弃代码移入 `deprecated.mbt`。
- 三行相似代码优于一个过早的抽象。

### VII. 中文表达（不可妥协）

- 本项目全部文档（宪法/spec/plan/tasks/README/设计文档）必须使用中文。
- Agent 输出必须使用中文；代码注释中文优先。
- Commit message 采用 Conventional Commits 格式，描述可用中文。

## 技术约束与合规

- 实现语言 MoonBit；唯一底座 `moonbitlang/async`
  （`@http`/`@socket`/`@tls`/`@io`/`@gzip`/`@websocket` 及 async 原语包），
  经 moon.mod `import` 使用 registry 版本（钉 0.22.x）。上游修复一律等待发版；
  确需验证上游改动时，本地 pull 一份上游副本、在其上修改、经本地包引用联调，
  该本地引用与改动不得进入主分支，仅限本地实验分支；`.mooncakes` 覆盖方案弃用。
- 分层与依赖方向（严格单向向下）：
  门面包（拦截器链、Dispatcher、EventListener、Logger、Timeouts）
  → core 包（HttpUrl、Request/Response/RequestBody、HeadersV 有序头、Call 与取消）
  → `moonbitlang/async`。
  可行性报告中的工作名 `easyhttp` 即本项目的门面/core 包。
- 请求发射统一走流式 `Client`；便捷 `get/post`（每请求新建连接且恒 chunked）弃用；
  已知长度 body 经 `extra_headers~{Content-Length}` 触发定长帧（SendingFixed）。
- 拦截器链序固定：
  [应用拦截器] → RetryAndFollowUp → Bridge → Cache → Connect（池租借/证书固定）
  → [网络拦截器] → CallServer/WebSocket。
- 对 reqbest（Apache-2.0）的移植（HPACK、br/zstd 协商参考等）必须按署名合规
  清单执行；本项目许可证为 Apache-2.0。
- 敏感信息默认不展示：日志与一切用户可见输出（调试输出、EventListener、
  错误消息与错误上下文等）默认不得出现 Authorization、Proxy-Authorization、
  Cookie、Set-Cookie、URL 用户信息等敏感信息（自动掩码只是达成「不展示」的
  可选手段之一，不作机制性强制）；当某项开发或设计确需展示敏感信息时，
  MUST 事先主动汇报项目所有者、经人工确认后方可实现。
  （不安全配置 opt-in 等安全条款留待后期补充，暂不立条。）
- 实验阶段（0.x）不保证对外 API 兼容；但 `.mbti` diff 仍须逐次审视——
  不保证兼容 ≠ 允许意外泄漏，破坏性变化须在 spec 与 changelog 显式记录。

## 开发工作流与质量门

- SDD 最小闭环：`specify → clarify → plan → tasks → implement`；
  `analyze`/`converge` 按需插入。每份文档先审后跑；改需求必须回改 spec 再向下
  重新生成，不得手改 tasks 使其与 spec 脱节。
- 按里程碑交付（M1 性能核心 → M2 完整门面 → M3 可观测与安全 → M4 缓存 →
  M5 WebSocket 与 target 收口 → M6 HTTP/2），每期必须独立可用。
- 特性设计文档统一结构：OkHttp 规格 → async/http 现状（行号证据）→ 实现方案 →
  侵入性清单 → target 矩阵 → 性能影响 → 工作量/依赖 → 测试方案。
- 合入前质量门：`moon info && moon fmt` 干净、`moon test --target native` 与
  `moon test --target wasm` 双双全绿、`.mbti` diff 已审视、性能改动附
  基准数据、宪法合规已自查。js 与 wasm-gc 不作为合入门禁，仅要求每项
  能力的 target 矩阵显式标注「暂不验证」并挂欠账跟踪。
- agent 可在合适时机主动 commit（Conventional Commits、中文描述、不含秘密
  文件，汇报中列明 commit 范围）；一切 push 与分支合并（merge/rebase 进主分支）
  须事先人工批准。

## 治理

- 本宪法是项目最高治理文档，效力高于其他一切实践约定；所有 plan 与 analyze
  必须对照宪法检查，违背核心原则处必须显式说明理由并记录（例外跟踪）。
- 修订流程：提出修订（动机 + 影响范围）→ 更新版本行 → 在文件顶部生成
  Sync Impact Report → 人工审阅通过后提交（提交前删除该报告）。
- 版本策略（语义化）：MAJOR = 原则删除或重新定义；MINOR = 新增原则或实质性
  扩充；PATCH = 措辞澄清、笔误修正等非语义调整。
- 合规审查：每次 code review 与 `/speckit-analyze` 必须验证宪法符合性；
  复杂度引入必须能被理由辩护。
- 运行时开发指引：项目根 `agents.md`（MoonBit 工程约定）、
  `proj-init-docs/speckit-tutorial.md`（Spec Kit 流程）、
  `proj-init-docs/okhttp-on-async-http/`（可行性研究报告全集）。

**版本**：1.2.0 | **批准日期**：2026-10-12 | **最近修订**：2026-10-14
