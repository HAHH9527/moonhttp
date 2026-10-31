# Feature Specification: 自动重定向 follow-up 循环（M1-P06）

**Feature Branch**: `006-m1-p06-redirects`

**Created**: 2026-10-27

**Status**: Draft

**Input**: User description: "仓库文件 docs/roadmap/M1/P06-redirects.md
的全文（speckit 输入种子，唯一功能描述输入）"。

## User Scenarios & Testing *(mandatory)*

<!--
  用户故事按重要性排序；每条故事独立可测——只实现其中一条也应产出可用价值。
  优先级继承种子文件：US-1/US-2/US-3/US-4/US-6 为 P1，US-5 为 P2。
  决策表行为均已对拍 OkHttp 5.5.0 源码（tag parent-5.5.0，取证见
  「宪法合规口径」映射表行注），两处种子口径修正（C2、300 跟随）在
  US-1-4 与 US-5-2 内体现，裁决记录见 Clarifications。
-->

### User Story 1 - 方法降级跟随（Priority: P1）

作为使用者，带体的请求收到 300/301/302/303 时自动降级为 GET 重放
（body 丢弃），最终拿到目标响应；prior 链记录中间响应。

**Why this priority**: 重定向最高频形态（POST 提交后的 30x 跳转）；
决策表「降级」半边与 prior 链机制（FR-006）在此首拆，是其余故事
共享的机制底座。

**Independent Test**: P03 重定向链夹具（任意状态码 + Location 组合）；
不依赖 P07/P08，单包可完整验收。

**Acceptance Scenarios**:

1. **Given** `POST /a` → `301 Location: /b`，**When** execute，
   **Then** follow-up 为 `GET /b`、无 body 与 Content-Length/
   Content-Type 头、终态响应正确、prior 链长度 1。
2. **Given** `POST /a` → `303 Location: /b`，**When** execute，
   **Then** 同场景 1。
3. **Given** `HEAD /a` → `303`，**Then** follow-up 保持 HEAD
   （GET/HEAD 全状态码保持，对齐 5.5.0 permitsRequestBody 门）。
4. **Given** `PUT /a` → `302 Location: /b`，**Then** follow-up 为
   `GET /b`、body 丢弃（5.5.0 对拍修正：非 GET/HEAD 一律降级，
   种子「仅 POST」口径作废，见 Clarifications Session 2026-10-27
   第 2 条）。
5. **Given** `DELETE /a` → `300 Location: /b`，**Then** follow-up 为
   `GET /b`（300 与 301/302 同分支，5.5.0 对拍；见同上第 3 条）。

---

### User Story 2 - 方法保持与可重放判定（Priority: P1）

作为使用者，307/308 保持方法与 body 重放；body 不可重放时收到原始
307/308 响应（不跟随）。

**Why this priority**: 307/308 是唯一「方法+体保持」路径，重放判定
是正确性红线（不可重放体的盲目跟随会造成二次消费）；与 US-1 共同
构成决策表全行覆盖。

**Independent Test**: P03 夹具（捕获对端两次字节比对 + Stream 体
不跟随断言）；不依赖 P07/P08。

**Acceptance Scenarios**:

1. **Given** `POST` + `Bytes` body → `307 Location: /b`，**Then**
   follow-up 为 `POST /b` 且 body 逐字节重放（对端两次捕获字节
   一致）。
2. **Given** `POST` + `Stream` body → `307`，**Then** 不跟随，调用方
   收到该 307 响应本体（中间响应语义同终态：body 未排干前连接不
   复用）。
3. **Given** `308`（Bytes/Stream 同上两形态），**Then** 行为与 307
   相同。

---

### User Story 3 - Location 解析（Priority: P1）

作为使用者，相对/绝对/畸形 Location 均得到定义良好的处理。

**Why this priority**: Location 解析是跟随的前置门（解析失败的回退
语义直接决定「是否安全地停在 3xx」）；畸形输入的确定性行为是
互操作正确性底线。

**Independent Test**: P03 夹具（Location 三形态 + 缺失/非法注入）；
不依赖 P07/P08。

**Acceptance Scenarios**:

1. **Given** 相对 `../b`、绝对 `/b`、网络路径 `//other.host/x`，
   **Then** 分别经 URL resolve 得到正确绝对 URL 后跟随。
2. **Given** 无 Location 头、或 Location 非法（resolve 失败），
   **Then** 返回原 3xx 响应作为终态（对齐 5.5.0：Location 缺失或
   不可解析即不跟随）。

---

### User Story 4 - 跨 host 头剥离（Priority: P1）

作为使用者，重定向到不同 scheme/host/port 时，`Authorization` 与
`Cookie` 头不出现在 follow-up。

**Why this priority**: 凭证跨域泄漏防线（安全面）；M1 无 CookieJar，
手设头是唯一凭证通道，剥离是唯一防线。

**Independent Test**: P03 捕获对端字节断言（跨 host/同 host 双向）；
不依赖 P07/P08。

**Acceptance Scenarios**:

1. **Given** 带 `Authorization: Bearer x` 与 `Cookie: a=1` 的请求 →
   `301` 跨 host，**Then** 捕获的 follow-up 字节不含这两个头。
2. **Given** 同 host 重定向，**Then** 头保留。

---

### User Story 5 - 跳数上限与不跟随集合（Priority: P2）

作为使用者，超过 20 跳得到可判别的 `TooManyFollowUps`；304/305/306
与无 Location 的 3xx 原样返回。

**Why this priority**: 资源保护与防御性边界（循环链、恶意服务端）；
不阻塞主链路价值，故列 P2。

**Independent Test**: P03 夹具（21 跳链、A→B→A 循环链、不跟随状态
码逐个注入）；不依赖 P07/P08。

**Acceptance Scenarios**:

1. **Given** 21 跳链夹具，**Then** raise `TooManyFollowUps`
   （`err is` 可判别，对齐 5.5.0 MAX_FOLLOW_UPS=20）。
2. **Given** `304`/`305`/`306` 响应，**Then** 不跟随、原样返回
   （M1 304 语义为终态透传，差异 D7——缓存层 M4 才存在）。
3. **Given** `300` 无 Location，**Then** 原样返回（与 5.5.0 一致：
   300 有 Location 才跟随，见 US-1-5）。

---

### User Story 6 - 中间响应排干与租约保持（Priority: P1）

作为使用者，同 host 多跳重定向复用同一连接，且中间响应 body 不污染
后续请求；跨 host 跳时旧连接被正确处置。

**Why this priority**: 宪法 II 性能防退化项（FR-002/FR-007）的验收
载体；排干缺失会造成连接态污染（下个请求读到脏数据），租约保持缺失
则退化为归还-重取往返。

**Independent Test**: P03 夹具（3 跳同 host 链 + 连接计数 + 干净流
断言；跨 host 跳 + 新建连接计数）；不依赖 P07/P08。

**Acceptance Scenarios**:

1. **Given** 3 跳同 host 链（每跳带 1KB body），**Then** 夹具侧仅见
   1 条新建连接、终态后的第 4 个请求读到干净流（中间 body 已排干）。
2. **Given** 跨 host 跳，**Then** 旧租约干净归还回池（同址后续租借
   可复用）、新 host 新建连接（新建连接计数 +1；`Connection: close`
   中间响应的关闭分支归 FR-009/Edge Cases，不在本场景）。

---

### Edge Cases

- Location 指回自身 host 但端口不同 → 视为跨 host（剥头，FR-004；
  scheme/host/port 任一不同即跨 host）。
- 重定向循环 A→B→A → 受 20 跳上限保护，raise `TooManyFollowUps`。
- 303 后再 307 → 降级后的 GET 无 body，307 保持 GET 重放 trivially
  成立（无体可重放）。
- HEAD/GET 带 body 的异常形态 → 301/302/303/307/308 全部保持方法；
  307/308 下按可重放判定（Bytes 重放 / Stream 不跟随）。**注**：该
  形态在 M1 构造面不可达——`RequestBuilder::build` 拒体组对
  Get/Head 带 body 一律 raise `MethodBodyMismatch`（core
  request.mbt:116-126），`Request` 非 `pub(all)`、包外不可字面构造；
  本条为防御性描述，implement 不为其建夹具用例。
- follow-up 轮间 cancel → 每轮前 guard，以 `CallCancelled` 终止
  （FR-001）；轮中（发送/收头中）取消复用 P05 既有取消语义。
- 中间响应 `Connection: close` → 该连接终态后关闭不回池，follow-up
  走新连接（P04/P05 既有处置语义在循环内的应用）。
- 21 跳链 → raise `TooManyFollowUps`。上限精确语义（对齐 5.5.0
  L93-120 循环结构）：每轮收到响应并算出 follow-up 后、发送前检查
  `++followUpCount > 20`——至多实际发出 20 个 follow-up（总请求数
  21），收到第 21 个仍需跟随的响应即抛出；检查点前的中间响应 body
  排干照常执行。

## Requirements *(mandatory)*

### 范围

**前置依赖**：P01（`HttpUrl::resolve` 相对引用解析）、P02
（Request/Response/HeadersV 有序头、`Response::prior` 访问器、
`to_http_request` 转换层）、P04（ConnectionPool 租约/毒化）、P05
（Call/exchange 接缝/`CallCancelled`/ResponseBody 收尾语义）；测试
依赖 P03 夹具。下游：P07（recover 插入同一循环）、P08（callTimeout
伞）、P10（重定向场景基准）。

**包含**：

- follow-up 主循环：每轮前 guard `call.cancelled`；中间响应 body
  排干；follow-up 计数上限 20；`TooManyFollowUps`。
- 决策表（M1 版，5.5.0 对拍，FR-003 五行）。
- Location 处理：相对/绝对/网络路径经 resolve；缺失/非法回退终态。
- 跨 host（scheme/host/port 任一不同）剥 `Authorization`/`Cookie`。
- `Response.prior` 链填充（P02 预留访问器，保序可遍历）。
- 同 host follow-up 租约保持（无归还-重取往返）。

**非目标（显式排除，含归属，clarify 不复议）**：

- stale-retry/路由失败恢复——归 P07（同一循环内的 recover 段）；
  408/503/421 重试语义一并归 P07（P06 对这些状态码一律终态返回；
  5.5.0 实况为 408 在默认 retryOnConnectionFailure 下会重试、503 按
  Retry-After、421 按连接合并——差异记入映射表，P07 对拍）；
- callTimeout 伞——归 P08 接线（本循环天然被其包裹）；
- Authenticator follow-up（401/407）——归 M2/08；
- 缓存条件 GET 改写——归 M4/05；
- `followRedirects`/`followSslRedirects` 关闭跟随开关——归 P08
  builder 配置位；M1 恒跟随、恒允许 scheme 变更（= OkHttp 默认
  true 的行为面）；
- js 自实现循环——不实现（浏览器已自动跟随且不可关，02 §5）；
  js 上 `priorResponse` 不可用；
- wasm-gc——上游 runtime 缺口，仅跟踪。

### Functional Requirements

- **FR-001**（种子）循环 MUST 每轮 follow-up 前检查取消标记；已取消
  或轮间取消 MUST 以裸 `CallCancelled` 终止（不包装于其他错误内，
  `err is CallCancelled` 为唯一判别式——P05 FR-003 先例）。
- **FR-002**（种子）中间响应 body MUST 排干（skip 语义，O(body)
  本地搬运）后连接方可复用；排干失败 MUST 毒化（P05 FR-005 收尾
  契约的循环内应用）；终态响应 body 保持 P05 惰性挂租约语义不变。
- **FR-003**（种子）决策表（M1 版，5.5.0 对拍）MUST 逐行可测：
  1. `300/301/302` + 有 Location：非 GET/HEAD 方法 → `GET`，去
     body 与 Transfer-Encoding/Content-Length/Content-Type；GET/
     HEAD 保持；
  2. `303` + 有 Location：非 GET/HEAD → `GET`，去 body 与同上三头；
     GET/HEAD 保持；
  3. `307/308` + 有 Location：保持方法与 body——可重放（Bytes）
     重放；不可重放（Stream）不跟随、原响应终态返回；
  4. `304/305/306`：不跟随，终态返回（304 的缓存条件改写归 M4/05，
     差异 D7）；
  5. `401/407/408` 及其余：终态返回（401/407 的 Authenticator 随
     M2/08；408 重试归 P07 对拍）。
- **FR-004**（种子）跨 host follow-up（目标 URL 与原请求 URL 的
  scheme/host/port 任一不同）MUST 剥除 `Authorization` 与 `Cookie`
  头；同 host MUST 保留（有意差异 vs 5.5.0 仅剥 Authorization——
  C1 裁决，依据见 Clarifications 第 1 条与映射表）。
- **FR-005**（种子）follow-up 计数上限 MUST 为 20（固定，不可配置
  ——C3 裁决，对齐 5.5.0 `MAX_FOLLOW_UPS = 20` 私有常量）；计数
  语义对齐 5.5.0：收到响应并判定仍需跟随后、发送 follow-up 前检查，
  超出 MUST raise `TooManyFollowUps` 显式错误变体（`err is` 判别；
  至多发出 20 个 follow-up、总请求数 21；5.5.0 为
  `ProtocolException` 消息判别，差异记映射表）。
- **FR-006**（种子）prior 链 MUST 保序可遍历：终态响应的 prior 指向
  上一跳响应、逐级回溯达最初响应（P02 `Response::prior` 访问器）；
  链深度 = 实际发生的跳数（如 2 跳跟随 → 终态.prior.prior = 最初
  3xx 响应）。
- **FR-007**（种子）Location 指向同 host（scheme/host/port 均同）时
  follow-up MUST 复用当前连接租约（同一次 execute 内不归还-重取）；
  跨 host 跳 MUST 干净归还旧租约（回池、同址后续租借可复用）并在
  新 host 建新连接；`Connection: close` 中间响应的关闭处置是另一
  分支，见 FR-009。
- **FR-008**（种子细则）Location MUST 全部经 `HttpUrl::resolve`
  解析（相对引用、绝对路径、网络路径 `//host/x` 三形态）；缺失或
  resolve 失败 MUST 返回原 3xx 响应作终态（不跟随，对齐 5.5.0）。
- **FR-009**（边界）中间响应携带 `Connection: close` 时，该连接
  MUST 在排干后关闭、MUST NOT 回池，follow-up MUST 走新连接。
- **FR-010**（L3 正确性）follow-up 视为新请求：其线上请求头 MUST 与
  头改写后的结果一致，MUST NOT 复用原请求的折叠头缓存产物（改写在
  HeadersV 层保序完成后经 P02 转换层重折叠；缓存代次粒度 C4 归
  plan 细化，见 Assumptions）。
- **FR-011**（target）native/wasm MUST 同一路径全量实现；js MUST NOT
  依赖本包循环完成重定向（浏览器 fetch `redirect:"follow"` 已自动跟随
  ⇒ execute 首响应即终态、循环首轮判定不跟随退出，`priorResponse`
  不可用）。实现形态＝循环代码零 `#cfg(js)` 分支同形编译、行为由浏览器
  短路保证（非代码分叉）——宪法 V 未验证面，欠账随 M5 收口
  （2026-10-28 review 修复批：按实现实况订正「MUST NOT 实现循环」的
  字面口径，语义不变）。
- **FR-012**（.mbti 冻结面，可验收）本包公开面新增 MUST 与「Key
  Entities」一致并冻结：`TooManyFollowUps` 错误变体；`Response::prior`
  访问器 P02 已公开、本包不新增公开项。实现完成后 `.mbti` 审视
  （宪法 VI）以其为对账面，计划外公开项为零。

### Key Entities

- **follow-up 循环**：P05 exchange 接缝上的包裹层（RetryAndFollowUp
  等价物）：单轮 exchange → 决策表判定 → 生成 follow-up 请求或
  终态返回；M2 拦截器链接入后平移为链上节点，接缝不变。
- **follow-up 请求（代次）**：每轮跟随产生的新 Request（方法/头/
  URL 改写产物）；代次是 L3 折叠缓存与 prior 链的共同计数单位。
- **决策表（M1 版）**：FR-003 五行状态码 × Location × 方法 × 可重放
  判定的行为矩阵；与 5.5.0 的差异在映射表显式登记。
- **prior 链**：`Response::prior` 逐级回溯的历史响应链（FR-006）。
- **TooManyFollowUps**：跳数超限的显式错误变体（FR-005）；与
  `CallCancelled`（P05）同为 client 包错误面成员。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: US-1–US-6 全部验收场景测试全绿，native 与 wasm 双
  target；决策表 FR-003 五行每行至少一个用例（含 300 有/无 Location
  双形态）（宪法 IV/V）。
- **SC-002**: 超限可判别——21 跳链与 A→B→A 循环链均以
  `err is TooManyFollowUps` 终止，无挂死、无静默终态。
- **SC-003**: 租约语义可证——3 跳同 host 链夹具侧新建连接数恰为 1
  （US-6-1）；跨 host 跳新建连接计数 +1 且旧连接干净回池、同址
  后续租借可复用（US-6-2，池/夹具计数双断言；语义收窄见
  Assumptions W1 裁决）。
- **SC-004**: 剥头可证——跨 host follow-up 捕获字节不含
  `Authorization`/`Cookie`（ScriptedPeer 原始字节捕获）；同 host
  follow-up 凭证头完整保留二者（US-4；2026-10-28 review 修复批按
  观测面实况分层：跨 host＝原始请求行/头字节，同 host＝T019 夹具
  请求行+头表观测面——解析后重建，重复头以 "," 合并、无版本行/体）。
- **SC-005**: prior 链可证——多跳链终态响应逐级回溯与夹具注入的
  3xx 序列逐项一致（深度 + 顺序 + 各级状态码三断言）。
- **SC-006**: 排干可证——同 host 链终态后同连接的下个请求读到干净流
  （无上一跳残帧/残体），连接状态无污染（US-6-1 后半）。
- **SC-007**: 外部网络依赖为 0——全部测试仅访问 P03 本地夹具
  （loopback），断网环境全套测试仍全绿。
- **SC-008**: 公开面零泄漏——实现完成后 `.mbti` 审视显示本包公开面
  与 FR-012 冻结面一致、计划外公开项为 0。

## Assumptions

- **C1 裁决（2026-10-27，本链路自主裁决）**：跨 host 剥
  `Authorization` + `Cookie`（遵种子/报告默认）。5.5.0 实测
  （buildRedirectRequest L329-331）：跨 host 仅
  `removeHeader("Authorization")`，无 Cookie 剥除——OkHttp 的 Cookie
  跨域安全由 BridgeInterceptor+CookieJar 按新域重算达成。M1 无
  CookieJar，手设 `Cookie` 是唯一凭证通道，「Jar 重算」的等价保守化
  即剥除手设 Cookie（否则其跨 host 泄漏，安全面劣于有 Jar 的
  OkHttp）。记为**有意差异**（映射表），M2/11-cookies CookieJar 落地后回改
  对齐（届时 Jar 按新域注入天然取代剥除语义）。种子预留的「对
  5.5.0 源码核对」义务已由本次取证完成并记录。
- **C2 裁决（2026-10-27，对拍修正）**：种子「301/302 仅 POST 降级、
  PUT 保持」作废。5.5.0 实测（`HttpMethod.redirectsToGet(method,
  code)` 两参版，tag parent-5.5.0）：300/301/302 对一切非 GET/HEAD
  方法（PROPFIND/QUERY 除外——M1 方法集不含二者）降级 GET；303 对
  非 GET/HEAD 降级；307/308 恒保持。宪法 III 基准为 5.5.0，US-1-4/
  US-1-5 已按对拍结果改写。
- **C3 裁决（2026-10-27）**：上限固定 20 不可配置，遵 OkHttp
  （`MAX_FOLLOW_UPS = 20` 私有常量，无公开配置面）。
- **C4 裁决（2026-10-27 plan 落地，research R3）**：L3 折叠缓存按
  call 内请求代次粒度——Call 增 `gen`/`folded_gen` 字段，缓存仅当
  `folded_gen == gen` 时复用（当前代次单槽，不建全代次 Map——P07
  重放同代次无回跳消费方，YAGNI）；换代后首次发送重折叠恰一次；
  同代次重放零重折叠（P05 SC-004 语义保持）。容器形状见
  plan/data-model 实体 2、contracts §1（全 priv 字段，公开面零变
  化）。
- **W1 裁决（2026-10-27，工单⑩ owner 批准，方案 B）**：跨 host 旧
  连接语义 =「干净回池、同址可复用」——与 INV-6/T013/data-model
  租约三态图既有口径对齐，不采用跨 host poison；SC-003/US-6-2/
  FR-007 已按此收窄为唯一语义并向下传导。
- `followRedirects`/`followSslRedirects` 开关不在 M1 公开面（恒跟随
  = OkHttp 两开关默认 true 的行为面），归 P08 builder 配置位。
- js target 仅 `moon check --target js`（循环代码同形编译、js 上首轮即 Terminal——浏览器已跟随）；
  不入合入门禁（宪法 V、差异 D14 先例）。
- 300 无 Location、以及 `mailto:` 等非 http(s) 绝对引用（若 P01
  resolve 拒绝）均按 FR-008 终态返回——P01 resolve 对非 http(s)
  scheme 的处置归 plan 核实（P01 契约为准）。

## 宪法合规口径（OkHttp 映射表 / Target 矩阵 / 性能影响 / 测试方案）

**OkHttp 映射表（宪法 III；证据基准 = tag `parent-5.5.0`
`okhttp/src/commonJvmAndroid/kotlin/okhttp3/internal/http/
RetryAndFollowUpInterceptor.kt` 与 `HttpMethod.kt`，2026-10-27 取证）**：

| OkHttp 5.5.0 行为 | moonhttp 本包对应 | 差异注记 |
| --- | --- | --- |
| 300/301/302 + Location：非 GET/HEAD（除 PROPFIND/QUERY）→ GET，去 Transfer-Encoding/Content-Length/Content-Type | 同义（FR-003 行 1；M1 方法集无 PROPFIND/QUERY） | 对齐；**种子「仅 POST」口径为过时事实，已按 5.5.0 修正**（C2） |
| 303 + Location：非 GET/HEAD → GET | 同义（FR-003 行 2） | 对齐 |
| 307/308 + Location：保持方法与 body；follow-up body 为 one-shot 时原样返回该 3xx 响应（L104-109） | 同义 + 可重放判定：Bytes 重放、Stream 不跟随原样返回（FR-003 行 3） | 对齐：moonhttp Stream（一次性消费）即 OkHttp one-shot 的等价物，双方均不盲目重放 |
| 300 属跟随分支（MULT_CHOICE 同 301/302） | 300 有 Location 即跟随（FR-003 行 1） | **种子「300 不跟随」为过时事实，已按 5.5.0 修正**（Clarifications 第 3 条） |
| 304 交给缓存层；305/306 终态 | M1：304/305/306 终态透传（FR-003 行 4） | **有意差异（D7）**：M1 无缓存层，304 无条件透传；M4 落缓存后回改 |
| 401/407 → Authenticator；408 默认重试（retryOnConnectionFailure=true）；503 按 Retry-After；421 连接合并重试 | M1：一律终态返回（FR-003 行 5） | **有意差异（D7）**：401/407 随 M2/08；408/503/421 重试归 P07 对拍（P07 spec 须消化本行 OkHttp 实况） |
| follow-up 上限 20（`MAX_FOLLOW_UPS`），超出 `ProtocolException("Too many follow-up requests: n")` | 上限 20，raise `TooManyFollowUps`（FR-005） | 对齐上限；**有意差异**：显式变体替代消息判别（P05 取消语义同款先例，判别性更强） |
| 跨 host（scheme/host/port 任一不同）`removeHeader("Authorization")`，Cookie 由 Jar 按新域重算 | 剥 `Authorization` + `Cookie`（FR-004） | **有意差异**：M1 无 CookieJar 的等价保守化（C1）；M2/11-cookies 回改对齐 |
| Location 缺失/不可解析 → 不跟随返回原响应 | 同义（FR-008） | 对齐 |
| `followRedirects`/`followSslRedirects` 开关（默认 true） | M1 无开关、恒跟随、恒允许 scheme 变更（**008 加注 2026-10-31：开关已由 008 交付**——builder 配置位缺省 true，关闭语义对齐本行 OkHttp 形态；缺省路径与本包行为面逐位一致） | **M1 范围差异**：开关归 P08 builder 配置位（行为面 = OkHttp 默认值） |
| priorResponse 链 | `Response::prior` 保序链（FR-006） | 对齐 |
| js：fetch 浏览器自动跟随且不可关 | js 上循环不激活：同形编译（零 `#cfg(js)`），浏览器已跟随 ⇒ 首轮判定 Terminal 直通终态（FR-011） | **target 差异**：宪法 V 未验证面，欠账随 M5 收口（2026-10-28 订正：实现形态＝同形编译＋浏览器行为短路） |

**Target 矩阵（宪法 V）**：

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 质量门双绿 target；同一路径 |
| js | ⭕ | **未验证**（差异 D14 先例）：浏览器自动跟随；循环同形编译、首轮判定 Terminal 直通终态、priorResponse 不可用；仅 `moon check --target js`，不入门禁，欠账随 M5 收口 |
| wasm-gc | ❌ | 上游 runtime 缺口（差异 D9），仅显式排除说明 |

**性能影响（宪法 II）**：防退化两项——中间 body 排干为本地内存搬运
O(body)（US-6-1 干净流断言）；同 host 租约保持消除归还-重取往返
（US-6-1 连接计数断言）。L3 在跟随路径生效：follow-up 头改写后重折叠
一次，属正确性必要成本非退化（FR-010；量化归 P10 重定向场景基准）。
本包测试不断言延迟数字（避免基准抖动侵蚀测试稳定性）。

**测试方案（宪法 IV）**：决策表逐行基于 P03 重定向链夹具构造全部
状态码 × Location 形态 × 方法组合；跨域剥头用捕获对端字节断言；
跳数上限/循环保护/取消交互逐项；prior 链深度与顺序
（`assert_true(prior is Some(...))` 风格）；native + wasm 双绿；
js 仅编译检查。

## 包级 DoD（验收判据）

1. US-1–US-6 验收场景测试全绿（native/wasm 双 target）；决策表每行
   至少一个用例。
2. `TooManyFollowUps`/`CallCancelled` 错误变体进 `.mbti` 并有判别
   测试（`err is` 形态）。
3. `moon info && moon fmt` 干净；`.mbti` diff 审视（FR-012 冻结面
   对账：新增公开项仅 `TooManyFollowUps`）。
4. 与 OkHttp 的 M1 语义差异表（D7 相关行 + C1/C2 对拍修正）保留于
   本 spec（即上文映射表），implement 阶段不回改语义。

## 待澄清项（移交 /speckit.clarify）

种子澄清问题 C1–C4 已于 2026-10-27 链路内按「种子默认 + 5.5.0 源码
对拍」自主裁决并回记（无 [NEEDS CLARIFICATION] 标记，无待 owner
裁决的未决项）：C1 剥头范围（有意差异，M2/11-cookies 回改）、C2 降级集合
（按 5.5.0 修正种子）、C3 上限固定、C4 代次粒度方向（plan 细化）。
裁决全文见 Assumptions 与 Clarifications；C4 已由 plan 落地回记
（代次单槽缓存，research R3）。owner 如推翻任一裁决，
须回改本 spec 后再向下传导（宪法「先审后跑」）。

## Clarifications

### Session 2026-10-27（specify/clarify 合并裁决，工单①授权自主推进）

1. **C1 手设 Cookie 跨 host 命运** → 剥除（遵种子默认）。5.5.0
   实测仅剥 Authorization（buildRedirectRequest L329-331）；剥
   Cookie 为 M1 无 Jar 的等价保守化，有意差异记录于映射表，
   M2/11-cookies CookieJar 落地后回改对齐。
2. **C2 301/302 降级集合** → 按 5.5.0 对拍修正：非 GET/HEAD 一律
   降级（`redirectsToGet(method, code)` 两参版，tag parent-5.5.0）；
   种子「仅 POST、PUT 保持」与宪法 III 基准（5.5.0）不符，US-1-4
   改写为 PUT→302→GET，新增 US-1-5（DELETE→300→GET）固化。
3. **300 是否跟随** → 跟随（5.5.0 将 MULT_CHOICE 与 301/302 同分支，
   followUpRequest L228）；种子「300 不跟随」修正，US-5 场景 2 收窄
   为 304/305/306，US-5 场景 3 补 300 无 Location 终态形态。
4. **C3 上限可配置性** → 固定 20 不可配置（对齐 OkHttp 私有常量）。
5. **C4 L3 缓存代次粒度** → 每 follow-up 代次独立折叠缓存（正确性
   下限已入 FR-010）；容器形状归 plan 核实 P05 结构后回记本 spec
   Assumptions。
6. **跳数上限精确语义**（源码取证补充，非 owner 议题）→ 5.5.0 的
   上限检查位于「响应到达 + followUp 已算出」之后、「发送 follow-up」
   之前（RetryAndFollowUpInterceptor L113-116）：至多发出 20 个
   follow-up（总请求数 21），收到第 21 个仍需跟随的响应即抛出；
   FR-005/Edge Cases 已按此精确化。
7. **307/308 one-shot 对拍修正**（源码取证补充，非 owner 议题）→
   5.5.0 对 one-shot body 同样原样返回 3xx 响应（L104-109）；映射表
   该行由「有意差异」改为「对齐」（moonhttp Stream = one-shot
   等价物）。

**owner 待裁决项：无。** C1/C2/300 三项对拍修正在工单①授权下按
宪法 III（5.5.0 基准）自主裁决并已记录理由；如 owner 推翻，回改本
spec 后再向下传导。

## 参考

- `docs/roadmap/M1/P06-redirects.md`（本包唯一规格种子）
- `proj-init-docs/okhttp-on-async-http/02-redirects-retries/README.md`
  §1（OkHttp 规格）、§3.1（循环伪代码）、§3.2（决策表）、§3.4（与
  取消/超时交互）、§8（测试方案）
- OkHttp 5.5.0 取证（tag `parent-5.5.0`，2026-10-27）：
  `RetryAndFollowUpInterceptor.kt`（followUpRequest L206-294、
  buildRedirectRequest L296-334、MAX_FOLLOW_UPS L355）、
  `HttpMethod.kt`（redirectsToGet 两参版、permitsRequestBody）
- `specs/005-m1-p05-call-engine/spec.md`（exchange 接缝/
  CallCancelled/ResponseBody 收尾契约——本包循环的承载底座）
- `specs/002-m1-p02-request-response/spec.md`（Response::prior 预留
  访问器、HeadersV 有序头、to_http_request 转换层）
- `specs/004-m1-p04-connection-pool/spec.md`（租约/毒化契约侧）
- `.specify/memory/constitution.md`（原则 I/II/III/IV/V/VI/VII）
- 下游引用方：P07（recover 插入同一循环；408/503/421 对拍消化）、
  P08（callTimeout 伞 + follow 开关配置位）、P10（重定向场景基准）
