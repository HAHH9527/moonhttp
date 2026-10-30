# Feature Specification: 连接失败重试 stale-retry（M1-P07）

**Feature Branch**: `007-m1-p07-stale-retry`

**Created**: 2026-10-30

**Status**: Draft

**Input**: User description: "仓库文件 docs/roadmap/M1/P07-stale-retry.md
的全文（speckit 输入种子，唯一功能描述输入）"。

## User Scenarios & Testing *(mandatory)*

<!--
  用户故事按重要性排序；每条故事独立可测。
  优先级继承种子文件：US-1/US-3 为 P1，US-2/US-4 为 P2。
  全部判定分支的行为均已对拍 OkHttp 5.5.0（锚点转引自 P07 种子与
  specs/003 澄清 D3/证据 E4，取证注记见「宪法合规口径」映射表）。
  上游可观测性约束（@http 不暴露 bytes_written、写失败可推迟到
  flush/end_request、Windows 部分 EOF 折算为 ReaderClosed）已消化进
  FR-002/FR-003 与 Clarifications C2/R1。
-->

### User Story 1 - 陈旧连接自动恢复（Priority: P1）

作为使用者，从池中取出的连接已被服务端静默关闭；我的请求自动换新
连接重放成功，全程无错误暴露。

**Why this priority**: M1 交付判据之二「stale-retry 闭环」的载体
（03 §6：池化不配 stale-retry 会让长闲连接场景错误率上升）；池化
正确性的必要配套，非优化项。

**Independent Test**: P03 夹具（应答后静默关闭 + 二次 accept 组合
脚本；B-09 accept 后 close 供证）；不依赖 P08，单包可完整验收。

**Acceptance Scenarios**:

1. **Given** 预热连接入池后服务端静默关闭它（响应无
   `Connection: close`，连接正常回池），**When** execute，
   **Then** 首次尝试在读响应头阶段以陈旧连接形态失败，自动换新
   连接重放、终态响应正确、调用方无感知错误。
2. **Given** 上述场景，**Then** `pool.stale_evictions` 递增恰 1、
   旧连接未回池（close）、池计数守恒（借出+空闲+已关＝累计新建，
   004 INV-5）。

---

### User Story 2 - 连接建立失败重试（Priority: P2）

作为使用者，connect 阶段的瞬时失败在重试预算内自动恢复或按预算
耗尽透传原始错误。

**Why this priority**: 六条件判定式的「连接建立失败」分支载体
（02 §3.3）；M1 直连单地址下为「整体重来一次」语义
（connect_to_host 内部已含 Happy Eyeballs 多地址竞速
，happy_eyeball.mbt:30-106），频率低于 stale 但同一判定机器。

**Independent Test**: P03 夹具 + 关闭端口（无监听）确定性注入
「拒绝」；恢复半边的覆盖口径见 Clarifications R2（进程内无法确定
性「先拒后收」，以共享 recover 机器 + 判定器单元级用例覆盖）。

**Acceptance Scenarios**:

1. **Given** 无监听端口（确定性拒绝），**When** execute，
   **Then** 在 max_attempts 内完成 2 次尝试、仍失败后透传最后一次
   原始错误（无包装变体，池状态零变化）；拒绝形态的错误类型按
   FR-015 同款双 target 观测记录钉定后加入断言（观测清单由本包
   元测试交付，先行断言收窄为「原始错误透传 + 恰 2 次尝试」）。
2. **Given** 判定器单元级用例，**Then** 连接建立失败
   （`@os_error.OSError`/`ResolveHostnameError`/TLS 握手族）均映射
   为「可重试」，且建连失败路径不触发毒化（无租约持有，池状态零
   变化——004 pool-api 契约「建连失败池状态零变化」）。

---

### User Story 3 - 不可重试分类（Priority: P1）

作为使用者，语义上不可安全重放的失败原样抛出，不产生重复副作用。

**Why this priority**: 正确性红线——「已收到响应字节/体已写出」后
重试会造成重复副作用；分流判定（BadRequest 不可重试但毒化、
ReaderClosed 可重试）是本包最密的分支区，宪法 IV 红绿循环优先区。

**Independent Test**: P03 B-11 PartialResponse（drain 内置，截断点
参数化）+ Stream 体失败注入 + 取消/预算耗尽场景；不依赖 P08。

**Acceptance Scenarios**:

1. **Given** P03「回半截响应头后断」脚本（B-11，截断点
   MidHeaderLine），**When** execute，**Then** 客户端错误为
   `BadRequest`（钉死可观测集合 {BadRequest, ReaderClosed}，specs/003
   澄清 D3/证据 E4），**不可重试**、连接毒化（对齐 OkHttp
   RetryAndFollowUpInterceptor.kt:171-173 协议错误不可重试）；错误
   原样透传（无包装）。
2. **Given** 同 B-11 夹具 `ReaderClosed` 形态（F17 实测：截断点
   Nothing 0B/MidStatusLine 15B/AfterStatusLine 17B 三形态均落
   ReaderClosed），**Then** 均可重试、判定陈旧连接（对齐
   RetryAndFollowUpInterceptor.kt:197 兜底与 Http1ExchangeCodec.kt:
   247-252 的 EOF 重包路径；ReaderClosed 不以「零字节」为限，半截
   状态行字节形态同判）。注意钉死集合是可观测集合、不等同可
   重试集合（F17）。
3. **Given** `Stream` body 已发生至少一次成功的 L1 写调用后发送
   失败（如对端提前关闭），**Then** 不重试（一次性体不可回退，副
   作用可能已发生；对齐 OkHttp isOneShot 路径
   RetryAndFollowUpInterceptor.kt:145/:157-163），错误原样透传。
4. **Given** 调用方已 cancel（含重试轮间 cancel），**Then** 以裸
   `CallCancelled` 终止、不走重试分支（取消优先于重试）。
5. **Given** 重试预算耗尽（第 max_attempts 次仍失败），**Then**
   透传最后一次原始错误（无包装、无新错误变体）。

---

### User Story 4 - 计数与观测（Priority: P2）

作为运维/基准下游（P10、未来 06），我从池读取 `stale_evictions`
等计数，量化陈旧连接发生率。

**Why this priority**: 观测面（P10 基准与闭环判据的量化口径）；
不阻塞主链路价值，但计数精度直接决定闭环判据可判定性。

**Independent Test**: K 次陈旧注入 + 非 stale 失败路径对照，断言
计数恰为 K。

**Acceptance Scenarios**:

1. **Given** 注入 K 次陈旧连接失败（K≥2，K 次独立 execute 各命中
   stale 一次；或跨代次形态：stale 恢复后跟随 301 再命中 stale），
   **Then** `stale_evictions` 恰为 K。
2. **Given** `BadRequest` 不可重试路径与 `Stream` 写失败路径各若干
   次，**Then** 计数不因此误增（毒化与重试解耦：毒化照常、计数只
   认 stale 命中——RealConnection.kt:398-400 trackFailure→
   noNewExchanges 的等价物）。

### Edge Cases

- 可重放 body 为 `Bytes` 且重放两次（第一次 stale、第二次成功）
  ——线上字节逐字节一致（捕获对端 L3 联合断言；同代次重放零重折
  叠，fold_count 不变）。
- `Bytes` body 部分写出后写阶段/读头阶段失败 → 仍可重试（OkHttp
  repeatable body 语义对拍精化，见 Clarifications C2——静态体内存
  可整体重发、新连接无重复副作用；种子的 bytes_written==0 条款收
  敛到 `Stream` 一侧）。
- 读头阶段 `HttpVersionNotSupported`（parser.mbt:405-408，协议段非
  HTTP/1.x）→ 与 `BadRequest` 同族：不可重试、毒化。
- `IncorrectBodyLength`（send.mbt:249-254，本地声明 Content-Length
  与实发不符）→ 本地框架缺陷非连接失败：不可重试、毒化、原样透传。
- 空体 GET 命中陈旧连接（canonical 形态）：发头成功、零体写调用、
  读头 EOF → 可重试。
- 重试轮间 cancel → 轮首取消 guard 生效，以裸 `CallCancelled` 终止。
- 重试与重定向叠加：先 stale 恢复再跟随 301 → 重试不占用 20 跳
  follow-up 预算（独立计数，对齐 OkHttp recover 与 follow-up 分离
  ——C3 裁决）；重试预算按请求代次计（每代次 ≤2 次尝试）。
- 同租约第 N 轮请求（keep-alive 复用中）命中 EOF 族 → 同样按 stale
  重试路径处置（计数 +1；「取出后首读」是 canonical 形态而非判据
  限制）。
- RST 注入形态（@os_error.OSError）：并入可重试面（对齐 OkHttp
  :197 兜底），端到端不可确定性注入（F16），以判定器单元级用例覆
  盖（Clarifications R1）。

## Requirements *(mandatory)*

### 范围

**前置依赖**：P04（ConnectionPool 租约/毒化/`stale_evictions` 计
数器）、P05（Call/exchange 接缝/`CallCancelled`/错误透传语义）、
P06（follow-up 循环——recover 段插入同一循环）；测试依赖 P03 夹具
（B-09/B-10/B-11、观测清单 FR-015）。下游：P08（callTimeout 伞覆
盖重试轮 + builder 承接开关配置面）、P10（闭环场景入基准）。

**包含**：

- recover 段：插入 P06 `exchange_loop` 轮内（建连段与单轮 exchange
  段各自的错误捕获点），六条件可重试判定、换新 Lease 重放。
- 阶段化发送的错误分类：L1 自有的 request/写体/end_request 调用点
  即阶段边界（02 §4「写路径阶段化由 L1 自身控制」，非侵入）；按
  错误类型分流可重试性。
- 毒化与计数：任何失败路径毒化归属不变（轮级 errdefer 单点）；
  stale 命中额外递增 `stale_evictions`。
- `retryOnConnectionFailure` 开关（`HttpClient::new` 可选参数，默
  认 true）。

**非目标（显式排除，含归属，clarify 不复议）**：

- 408/503 响应级重试（D7，不做；OkHttp 实况为 408 在默认
  retryOnConnectionFailure 下会重试、503 按 Retry-After——差异记
  映射表，M2/08 Authenticator 一并归位）；
- 代理路由失败语义（M2 代理引入后扩展）；退避策略（max_attempts=2
  场景无退避；`@async.retry` 及其退避参数为未来扩展点，006 种子
  已预留口径）；
- 收到部分响应字节后的重试的**旧口径修正**：种子「收到部分响应字
  节一律不可重试」按 F17 实测收窄——读头阶段半截状态行字节
  （ReaderClosed 形态，0B/15B/17B）可重试（FR-002）；真正排除的是
  **响应交付开始后**（`end_request` 成功返回响应头之后）的重试——
  体阶段失败归 P05 收尾语义处置，不走 recover。
- js 自实现重试（fetch 连接由浏览器管理，无陈旧连接概念，本包在
  js 不激活）；wasm-gc——上游 runtime 缺口，仅跟踪。

### Functional Requirements

- **FR-001**（种子）可重试判定 MUST 为六条件合取，逐条可测：
  `retryOnConnectionFailure 开启 ∧ 失败类型 ∈ 可重试失败集 ∧ 请求体
  可重放 ∧ 失败发生于响应交付开始之前（失败阶段 ∈ 建连/发头/写体
  /读头，读头阶段按 FR-002 分流；end_request 成功返回后不适用本判
  定） ∧ 未被取消 ∧ 本请求代次尝试次数 < 2`。可重试失败集：
  连接建立失败（建连段 `@os_error.OSError`/`ResolveHostnameError`/
  TLS 握手族）、读头阶段 EOF 族（`@io.ReaderClosed`/
  `@os_error.OSError`/TLS 层 `ConnectionClosed`/`TlsError`）。六条
  件与 OkHttp recover 门（:142/:145/:148/:151）的逐条映射见本文件
  映射表。
- **FR-002**（种子）读头阶段错误 MUST 按类型分流（钉死集合是可观测
  集合、不等同可重试集合；specs/003 澄清 D3/证据 E4；欠账 F17）：
  `BadRequest` 与同族 `HttpVersionNotSupported`（parser.mbt:404/
  :405-408/:410-413，畸形片段已作为状态行解析＝已收到字节）MUST NOT
  重试、毒化照常（对齐 OkHttp :171-173）；`ReaderClosed` 可重试、
  判定陈旧连接——按 F17 实测其覆盖零字节（Nothing 0B）与半截流
  （MidStatusLine 15B/AfterStatusLine 17B）两类形态（Windows 侧部
  分 EOF 亦折叠为 ReaderClosed，io_windows.mbt:136-143），**不以
  「零字节」为判据**（对齐 OkHttp：requestSendStarted 按异常类型
  判定而非字节计数，:139）。全链 MUST NOT 以
  「状态行是否已解析」为任何判定条件（@http 不暴露该内部状态）。
- **FR-003**（种子，C2 精化）`Stream` body 在本请求代次**已进入体
  发送**（L1 体发送入口已被调用，且至少一次底层写调用已成功发起）
  后 MUST NOT 重试；未进入体发送（发头失败或体发送入口未被调用）
  可重试。判据方向为**保守封锁**——宁可漏重试不可误重试（一次性
  体不可回退）；观测机制（L1 侧计数包装等，非侵入）归 plan 裁定，
  但判据 MUST 可在 L1 侧取得。`Bytes` body 恒可重放（整请求在新连
  接上重发；OkHttp repeatable body 对拍，理由见 Clarifications C2）。
  上游 `write`/`write_once` 不暴露已上行字节数（client.mbt:283-291
  返回 Unit、writer.mbt:28-42 丢弃进度），字节级「已写出」不可观测。
- **FR-004**（种子）stale 命中（读头阶段 EOF 族走重试路径）MUST
  毒化旧连接（close 不回池）并递增 `stale_evictions` 恰 1（与 004
  超期剔除同一计数器、同一锁内更新——004 FR-007 语义扩展行）；计
  数在**进入重试分支时**发生、与重试最终结果无关（重试后再失败不
  重复计数，预算耗尽透传时该计数已发生）；递增
  入口 MUST NOT 新增公开面（同包私有入口）。毒化与重试解耦：不可
  重试路径毒化但 MUST NOT 计数。
- **FR-005**（种子）重试 MUST 换新 Lease（失败连接丢弃不复用；上
  游 Client 实例失败后状态不可复用，TLS 层甚至缓存错误态——
  tls/transport.mbt:65-86）；预算默认 2 次尝试/请求代次、第一次立
  即重试不退避（对齐 OkHttp 无退避靠路由切换；M1 直连单路由退化为
  「整体重来一次」，02 §3.3）。
- **FR-006**（种子）重试判定 MUST 在取消检查之后（循环顶取消 guard
  优先于重试）；已取消或轮间取消 MUST 以裸 `CallCancelled` 终止，
  不进入重试分支。
- **FR-007**（接缝，qod-1 复核后改写）recover 的形态 MUST 为**轮内
  尝试子循环**：每代次请求的发送至多尝试 2 次（1 次原始 + 至多 1
  次重试），重试在当前轮内完成、MUST NOT 重入外层 follow-up 循环
  （不触碰 follow_ups 计数、不产生决策表推进、不产生 prior 条目）。
  阶段化捕获点（建连/发头/写体/读头）由 L1 自有调用点边界提供
  （02 §4，非侵入）。毒化归属钉底线约束：**进入重试分支前，旧租
  毒化（poison + close 不回池 + lease 置空）MUST 已完成**；不可重
  试逸出路径的毒化归属保持 P06 轮级 errdefer 单点不变。若 plan 采
  纳重试路径在捕获分支内显式毒化的机制，MUST 同批修订 006
  data-model D-2「轮级 errdefer 是唯一毒化归属点」的措辞（加注
  P07 修正：唯一性限于「错误逸出路径」）。
- **FR-008**（透明性）重试机器 MUST NOT 改变调用方可观测的错误面：
  透传错误一律为原始错误值（`err is` 判别集合与 P05/P06 既有面一
  致），不新增包装变体；`CallCancelled` 保持裸变体。预算耗尽 MUST
  透传最后一次原始错误。
- **FR-009**（L3 正确性）重试重放 MUST 与首次尝试同请求代次：MUST
  NOT 递增 `gen`、MUST 复用同代次折叠头缓存（fold_count 不变）、
  MUST NOT 修改请求（方法/头/URL/体）；线上字节与首次尝试逐字节一
  致（捕获对端断言）。
- **FR-010**（配置面）`HttpClient::new` MUST 增加可选参数
  `retry_on_connection_failure~ : Bool`（缺省 true，＝OkHttp 默认
  行为面）；false 时任何失败 MUST NOT 重试、按 P05/P06 既有语义处
  置（毒化照常）。builder 化配置归 P08（C4）。
- **FR-011**（.mbti 冻结面，可验收）本包公开面新增 MUST 恰为
  `HttpClient::new` 的上述可选参数一项：无新错误变体、无新公开方
  法、`stale_evictions` 计数入口保持私有。对账基线＝005 FR-014/
  006 FR-012 冻结面叠加本条（签名变更类增量仅此一项）。实现完成
  后 `.mbti` 审视（宪法 VI）以其为对账面，计划外公开项为零。

### Key Entities

- **recover 段**：`exchange_loop` 轮内尝试子循环与分流层（OkHttp
  `RetryAndFollowUpInterceptor.recover` 等价物）：捕获 → 六条件判
  定 → 可重试则毒化旧租/计数/换新租在同一轮内重试（子循环，至多 2
  次尝试），不可重试则原样 re-raise（逸出路径毒化归属＝P06 轮级
  errdefer 单点）。
- **可重试判定器**：纯函数（错误值 + 阶段 + 体形态 + 体发送进入
  与否 + 代次尝试数 + 开关 + 取消态）→ 重试/透传决策；分支全覆盖
  的单元级测试对象（含不可端到端注入分支：RST/TLS 族）。
- **尝试预算**：按请求代次计数的尝试上限（每代次 ≤2）；与
  follow-up 20 跳预算独立（C3）；不占跳数预算但占总线上请求数
  （对 006「总请求数 21」口径的修正见 Assumptions）。
- **stale 命中**：读头阶段 EOF 族重试路径的观测事件——毒化 +
  `stale_evictions` +1 的唯一计数触发点。
- **retryOnConnectionFailure 开关**：`HttpClient` 构造期不可变配置
  （缺省 true）；builder 化归 P08。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: US-1–US-4 全部验收场景测试全绿，native 与 wasm 双
  target（wasm 断言强度按 specs/003 FR-015 观测清单调整并记录）；
  可重试判定器每个分支至少一个正例或反例（宪法 IV）。
- **SC-002**: stale-retry 闭环端到端可证——预热→服务端静默关闭→
  自动换新连接重放→终态响应正确→`stale_evictions` 恰 1→池计数
  守恒（M1 交付判据之二的包级闭环，US-1）。
- **SC-003**: 计数精度可证——K 次独立 stale 注入（K≥2，各命中一
  次）计数恰为 K；`BadRequest`/`Stream` 写失败/预算耗尽路径零误计
  （US-4）。
- **SC-004**: 重放保真可证——`Bytes` 体 stale 重放的线上字节与首
  次尝试逐字节一致（捕获对端），折叠计数 fold_count 在重试前后不
  变（同代次，FR-009）。
- **SC-005**: 不可重试确定性可证——B-11 `BadRequest` 形态错误原样
  透传（`err is` 判别）、连接毒化（同址后续请求建新连接，夹具侧
  连接计数可证）、零重试（对端仅见一次发送尝试）。
- **SC-006**: 预算与取消语义可证——第 2 次尝试仍失败透传原始错误；
  尝试次数恰为 2 后终止；重试轮间 cancel 以裸 `CallCancelled` 终
  止；重试+301 叠加场景下重试不占跳数预算（观测面：retry 不产生
  prior 条目、follow_ups 语义不变——跳数判定与 P06 一致；总线上
  请求数上界按 Assumptions 修正口径 ≤42）。
- **SC-007**: 外部网络依赖为 0——全部测试仅访问 P03 本地夹具
  （loopback），断网环境全套测试仍全绿。
- **SC-008**: 公开面零泄漏——实现完成后 `.mbti` 审视显示公开面增
  量与 FR-011 冻结面一致（仅 `HttpClient::new` 可选参数），计划外
  公开项为 0。

## Assumptions

- **C1 裁决（2026-10-30，链路内自主裁决）**：TLS 握手失败在 M1 的
  可重试语义＝判定框架级——握手族错误（`@tls.TlsError`/
  `ConnectionClosed`）映射为可重试（对齐 OkHttp :197 兜底），M1 测
  试以明文 http 为主，TLS 分支以判定器单元级用例覆盖（构造错误值
  直接喂判定器；M1 无 TLS 夹具、不建端到端注入）。若上游错误分类
  无法区分握手/传输阶段，则整个 TLS 错误面按读头阶段同族处理（可
  重试），差异随 M2 TLS 场景扩展时复核。
- **C2 裁决（2026-10-30，对拍精化；qod-1 后修订）**：种子的 `bytes_written==0`
  条款按上游实测精化——`@http` 公开面不暴露任何已上行字节数
  （`request`/`write` 返回 Unit、`write_once` 返回值仅为 1024B 发
  送缓冲的拷贝计数，writer.mbt:28-42 丢弃进度；写失败可推迟到
  flush/end_request 才显现）。故：`Stream`（one-shot 等价物）按
  「体发送已进入」保守封锁（宁可漏重试不可误重试；观测机制归
  plan）；`Bytes`（repeatable 等价物）恒可重放——静态体
  在新连接整体重发无重复副作用，对齐 OkHttp recover 对非 one-shot
  体的行为（requestSendStarted 仅封锁 one-shot 路径，:145/:157-163；
  「请求已上行后对端已处理再重放」的副作用窗口为 OkHttp 基准固有
  语义，非本包新增差异）。
  种子边界用例「bytes_written>0 → 不可重试」收敛到 `Stream` 侧记
  录为本条。
- **C3 裁决（2026-10-30）**：重试与 follow-up 预算独立——重试不在
  20 跳预算内计数（OkHttp 内部 recover 与 followUpCount 为独立机
  制；每次 follow-up 是新请求、预算自然重置，:113-116 区仅对
  follow-up 递增）；尝试预算按请求代次（每代次 ≤2 次尝试），代次
  换代（跟随重定向）不继承已耗预算。**跨文档口径修正**：重试不占
  跳数预算但占总线上请求数——006 FR-005「总请求数 21」在本包修正
  为「每代次至多 2 次尝试 × ≤21 个代次请求 ⇒ 总线上请求数 ≤42」，
  P08/P10 对拍以本条为准（006 spec 文本不回改，差异随本条登记生
  效）。max_attempts=2 为项目显式化（OkHttp 无暴
  露计数、靠 RouteSelector 路由耗尽兜底），记有意差异（映射表）。
- **C4 裁决（2026-10-30）**：开关配置面＝`HttpClient::new` 可选参
  数（缺省 true），P08 builder 落地时承接为 builder 字段（签名迁
  移属 P08 spec 范围）。M1 不建 builder。
- **R1 裁决（2026-10-30，F16 承接）**：RST 的客户端表现
  （`@os_error.OSError`；Windows 侧部分形态折算为
  `ReaderClosed`——io_windows.mbt:136-143 与 FR-015 证据 E5）并入
  读头阶段可重试集合；端到端确定性注入不可得（上游无 shutdown/
  SO_LINGER，specs/003 裁决 D2），以判定器单元级用例覆盖该分支，
  集成断言落在 FR-015 观测清单可达的 ReaderClosed 形态上。
- **R2 裁决（2026-10-30，种子 US-2 修正）**：「端口先拒绝 N-1 次
  后可用」的进程内确定性注入不可得——两次立即重试之间无信号通道
  可让监听者上线（无时钟/事件锚点，竞态注入违反可控服务端原则）。
  集成测试覆盖确定性半边（关闭端口→2 次尝试→原始错误透传）；恢
  复半边由 stale 路径共用同一 recover 机器端到端覆盖（US-1）+ 判
  定器单元级用例覆盖建连失败分支（US-2-2）。P03 种子「夹具端口先
  拒绝 N-1 次后可用」按本条修正。
- **夹具扩展（2026-10-30 登记）**：现有夹具无「应答后静默关闭空闲
  连接 + 二次 accept」组合脚本（B-06 close_after_response 必带
  `Connection: close` 头，不构成静默关闭；exp-3 盘点确认）。US-1
  所需脚本由本包在 fixtures 包内新增（最小 PeerProgram/服务端组合
  变体），行为判据不变；属于测试基建的增量而非语义扩张。
- 重试路径的池侧不变量无需补丁：毒化→closed、新租→新建分支自动
  满足 004 INV-5 守恒恒等式（exp-3 取证：client.mbt:244-252 同锁
  段计数）。
- **006 data-model D-2 措辞修订登记（2026-10-30，qod-1 复核）**：
  若 plan 采纳「重试路径在捕获分支内显式毒化」机制，implement 阶段
  MUST 同批在 006 data-model.md D-2 行加注 P07 修正（「轮级 errdefer
  是轮内失败的唯一毒化归属点」→ 唯一性限于**错误逸出路径**；重试
  路径的毒化由捕获分支显式完成，底线约束见 FR-007）。
- **js 编译面形态（2026-10-30，qod-1 复核）**：判定器需判别的错误
  类型包 @os_error/@tls 上游 moon.pkg 锁 [native, wasm]、无 js 支
  （现行 src/client 未引入，属本包新引入面）。js 侧形态由 plan 裁
  定（候选：错误分类薄封装隔离/#cfg 分支/编译检查豁免并如实记录）；
  无论何种形态，js 语义均为「重试路径不激活」（浏览器管理连接），
  不入门禁、欠账随 M5 收口（F9 先例）。宪法 V 未验证面口径不变。

## 宪法合规口径（OkHttp 映射表 / Target 矩阵 / 性能影响 / 测试方案）

**OkHttp 映射表（宪法 III；证据基准 = tag `parent-5.5.0`
`RetryAndFollowUpInterceptor.kt`/`Http1ExchangeCodec.kt`/
`RealConnection.kt`，行号锚点转引自 P07 种子与 specs/003 澄清
D3/证据 E4——02 README 无源码锚点，2026-10-30 归属核查）**：

| OkHttp 5.5.0 行为 | moonhttp 本包对应 | 差异注记 |
| --- | --- | --- |
| `recover`：`retryOnConnectionFailure` 关 → 不可重试（:139 语境） | FR-001 首条件 / FR-010 开关（缺省 true＝默认行为面） | 对齐；开关面显式化（C4） |
| `isRecoverable` 首行：`ProtocolException → false`（:171-173） | `BadRequest`/`HttpVersionNotSupported`/`IncorrectBodyLength` → 不可重试、毒化照常（FR-002） | 对齐：moonhttp 协议错误族即 ProtocolException 等价物 |
| EOF 族：`EOFException` 重包为普通 IOException「unexpected end of stream」（Http1ExchangeCodec.kt:247-252）→ 落 :197 兜底 `return true` | `ReaderClosed`（+`OSError`/TLS 族）→ 可重试、判定 stale（FR-002/FR-001） | 对齐；OSError 并入按 R1（Windows EOF 折算实测）；ReaderClosed 不以零字节为限（F17 实测 0B/15B/17B 三形态） |
| one-shot body：`requestSendStarted ∧ isOneShot → false`（:145/:157-163） | `Stream` 已进入体发送后 → 不可重试（FR-003） | 对齐：Stream＝one-shot 等价物；两处口径差异已注记——OkHttp 的 requestSendStarted 按异常类型判定（`e !is ConnectionShutdownException`，:139），moonhttp 按「体发送已进入」保守封锁（宁可漏重试不可误重试，C2） |
| 非 one-shot body 部分发送后仍可 recover（新连接整体重发） | `Bytes` 恒可重放（FR-003；C2 对拍精化） | 对齐（种子的 bytes_written==0 条款为保守过时口径，已按上游实测修正） |
| SSLException 且 cause 为 CertificateException → 不可重试（:183-189）；SSLPeerUnverifiedException → 不可重试（:190-193） | M1 判定框架把整个 TLS 错误面（`TlsError`/`ConnectionClosed`）按可重试处理（C1/FR-001） | **有意差异（M2/M3 TLS 场景扩展时复核收窄）**：M1 无 TLS 夹具与证书场景，证书族不可重试分支暂不实现，登记备查 |
| 超时：`InterruptedIOException` 仅 connect 超时且未发送时可重试（:177-178） | M1 无超时层（P08 交付）；超时分类归 P08 对拍接线 | 范围差异：P08 需消化本行 |
| 重试预算：无显式计数，RouteSelector 路由耗尽兜底（:151 语境） | 每代次 ≤2 次尝试、立即重试不退避（FR-005；C3） | **有意差异**：M1 直连单路由，显式预算替代路由耗尽；`@async.retry` 为未来扩展点 |
| recover 与 follow-up 独立计数 | 重试不占 20 跳预算、按代次独立（C3） | 对齐 OkHttp 分离机制 |
| 408 默认重试 / 503 按 Retry-After / 421 连接合并重试 | 一律终态返回（P06 FR-003 行 5；D7） | **有意差异（D7）**：响应级重试 M1 不做，M2/08 归位 |
| 任何失败 trackFailure→noNewExchanges（RealConnection.kt:398-400，毒化与重试解耦） | 任何失败路径毒化（轮级 errdefer 单点）；stale 命中额外计数（FR-004） | 对齐：毒化与重试/计数解耦 |
| stale 检测＝被动（取出后失败兜底，03 §3.3） | 不做主动探测，池侧惰性剔除 + 本包 recover 兜底（004 FR-007 语义扩展行） | 对齐 |
| js：fetch 连接由浏览器管理 | 本包在 js 不激活（同形编译、循环不触发重试路径） | target 差异：宪法 V 未验证面，欠账随 M5 收口 |

**Target 矩阵（宪法 V）**：

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 质量门双绿 target；同一路径；wasm 断言强度按 specs/003 FR-015 观测清单（D2/证据 E5：close 形态依 OS 与在途数据而变） |
| js | ⭕ | **未验证**（差异 D14 先例）：fetch 连接由浏览器管理、无陈旧连接概念；重试路径不激活。编译面注意：判定器引用的 @os_error/@tls 上游无 js 支（moon.pkg 锁 native/wasm），js 编译形态由 plan 裁定（隔离封装/#cfg/豁免记录，见 Assumptions）；仅 `moon check --target js`，不入门禁，欠账随 M5 收口 |
| wasm-gc | ❌ | 上游 runtime 缺口（差异 D9），仅显式排除说明 |

**性能影响（宪法 II）**：stale-retry 把「陈旧连接导致的用户可见失
败」变成 ~1 次额外 RTT 的延迟（池化的必要配套，02 §6）；快乐路径
零额外成本——判定器仅在错误路径执行，无热路径新增分支/分配；重试
复用 L3 折叠缓存（同代次零重折叠）。量化归 P10 闭环场景基准；本包
测试不断言延迟数字（避免基准抖动侵蚀测试稳定性）。

**测试方案（宪法 IV）**：US-1 基于「应答后静默关闭 + 二次 accept」
夹具组合（本包新增，见 Assumptions）+ B-09 供证；US-3 基于 B-11
PartialResponse 双形态 + Stream 失败注入 + 取消/预算场景；判定器
全分支单元级用例（含 RST/TLS 族不可注入分支，红-绿循环优先区）；
重放字节一致性用捕获对端断言；计数精度用 K 次注入 + 非 stale 对照；
native + wasm 双绿；js 仅编译检查。

## 包级 DoD（验收判据）

1. US-1–US-4 验收场景测试全绿（native/wasm 双 target）；判定器每
   分支至少一个用例。
2. M1 判据「stale-retry 闭环」在本包 DoD 内闭环：预热→空闲关闭→
   自动恢复→计数正确（SC-002 端到端用例）。
3. `moon info && moon fmt` 干净；`.mbti` 新增面恰为
   `HttpClient::new` 可选参数（FR-011 冻结面对账）并经审视。
4. 与 OkHttp 的语义差异（max_attempts 显式化、408/503/421 D7 行、
   TLS 证书族行、C2/C3 精化）保留于本 spec 映射表，implement 阶段
   不回改语义。
5. 种子回写：`docs/roadmap/M1/P07-stale-retry.md` 两处按本 spec 裁
   决订正（US-2 的「P03 先拒后收脚本」按 R2 修正；C4 的「与 P08
   builder 合并交付」按 FR-010 修正），与 006 先例（种子按裁决回
   写）一致。
6. 006 data-model D-2 措辞修订（若触发，见 Assumptions 登记）随本
   包实现同批完成。

## 待澄清项（移交 /speckit.clarify）

种子澄清问题 C1–C4 已于 2026-10-30 链路内按「种子默认 + 上游实测
+ OkHttp 5.5.0 对拍」自主裁决并回记（无 [NEEDS CLARIFICATION] 标
记，无待 owner 裁决的未决项）：C1 TLS 判定框架级、C2 bytes_written
不可观测→L1 写调用口径、C3 预算独立按代次、C4 开关构造参数化。
另有 R1（RST 并入可重试面、单元级覆盖）、R2（US-2 拒绝恢复半边
不可确定性注入）两条证据裁决。裁决全文见 Assumptions 与
Clarifications；owner 如推翻任一裁决，须回改本 spec 后再向下传导
（宪法「先审后跑」）。

## Clarifications

### Session 2026-10-30（specify/clarify 合并裁决，承 006 先例自主推进）

1. **C1 TLS 握手失败语义** → 判定框架级：握手族错误映射可重试，
   单元级用例覆盖；不建 TLS 端到端注入（M1 无 TLS 夹具）。
2. **C2 bytes_written 位置** → 上游不暴露已上行字节数（实测：request/
   write 返回 Unit、write_once 为缓冲拷贝计数、写失败可推迟到
   flush/end_request）；「写出」观测口径＝L1 写调用成功返回（Stream
   计数封禁重试；Bytes 恒可重放，OkHttp repeatable 对拍精化）。
3. **C3 重试与 20 跳预算** → 独立计数（对齐 OkHttp recover 与
   followUpCount 分离）；尝试预算按请求代次 ≤2，换代不继承。
4. **C4 开关配置面** → `HttpClient::new` 可选参数（缺省 true）；P08
   builder 承接。
5. **R1 RST/OSError 归属** → 并入读头阶段可重试集合（OkHttp :197
   兜底对齐；Windows EOF 折算实测佐证）；端到端不可注入（F16/D2），
   判定器单元级覆盖。
6. **R2 US-2 拒绝恢复半边** → 进程内不可确定性「先拒后收」（无信
   号通道，竞态注入违反可控服务端原则）；集成测覆盖确定性半边（预
   算耗尽透传），恢复半边由共享 recover 机器（US-1 e2e）+ 单元级
   用例覆盖。
7. **夹具缺口登记** → 「应答后静默关闭 + 二次 accept」脚本由本包
   新增（fixtures 包最小变体，行为判据不变）。

### Session 2026-10-30（qodercn 独立复核 qod-1，六阻断项全部采纳修正）

外部复核（ACP qodercn）对初版 spec 提出六项阻断发现，全部采纳并
回改本文；要点存档：

1. **「未收到任何响应字节」条款与 F17 实测矛盾**（ReaderClosed 实
   覆 0B/15B/17B 三形态）→ FR-001 第四条件改写为「失败发生于响应
   交付开始之前（阶段 ∈ 建连/发头/写体/读头）」；FR-002/US-3-2/非
   目标同步按 F17 修正；删除全部「零字节真 EOF」定性。
2. **FR-007 机制矛盾**（轮内 catch 与轮级 errdefer 单点不能同时成
   立）→ 改写为轮内**尝试子循环** + 底线约束「进入重试分支前旧租
   毒化必已完成」；机制归属（捕获分支显式毒化 vs 内层 errdefer）
   划归 plan；连带登记 006 data-model D-2 措辞修订义务。
3. **FR-003 Stream 写计数无观测点**（filler 直持连接、失败可推迟）
   → 改为「已进入体发送」保守封锁口径，观测机制归 plan。
4. **US-4-1「连续两次 stale 后成功」不可达**（每代次 ≤2 次尝试）→
   改为 K 次独立 execute / 跨代次形态。
5. **TLS 证书族不可重试差异未登记**（OkHttp :183-193 显式不可重试）
   → 映射表补 SSLException 行，记有意差异（M2/M3 复核）。
6. **js 编译面风险**（@os_error/@tls 无 js 支）→ Target 矩阵与
   Assumptions 补形态声明，plan 裁定。

非阻断建议亦已采纳：FR-004 计数与结果无关明示、006「总请求数 21」
跨文档修正（≤42）、US-2-1 判别式观测清单化、SC-006 锚定 prior 链
与 follow_ups 观测面、FR-011 冻结面基线注记、种子 L81/L184 回写入
DoD。

**owner 待裁决项：无。** C1–C4/R1/R2 均按宪法 III（5.5.0 基准）
与上游实测证据自主裁决并记录理由；如 owner 推翻，回改本 spec 后再
向下传导。

## 参考

- `docs/roadmap/M1/P07-stale-retry.md`（本包唯一规格种子）
- `proj-init-docs/okhttp-on-async-http/02-redirects-retries/README.md`
  §3.3（判定式与阶段化）、§4（非侵入结论）、§6（池化配套）、§8（测
  试方案；RST 手法按 specs/003 D2 修正为 close 注入）
- `proj-init-docs/okhttp-on-async-http/03-connection-pool/README.md`
  §3.3（被动检测）、§3.4（毒化表 stale 行：close 不回池 + 计数 +1）
- OkHttp 5.5.0 取证锚点（转引自 P07 种子/specs/003 D3/证据 E4；
  2026-10-30 归属核查确认 02 README 无源码锚点）：
  `RetryAndFollowUpInterceptor.kt`（:139 requestSendStarted、:145
  isOneShot、:157-163 one-shot 封锁、:171-173 ProtocolException、
  :177-178 超时条件、:197 兜底 return true）、`Http1ExchangeCodec.kt`
  （:247-252 EOF 重包）、`RealConnection.kt`（:398-400
  trackFailure→noNewExchanges）
- 上游可观测性取证（.mooncakes/moonbitlang/async，2026-10-30）：
  `src/http/parser.mbt:401-413`（ReaderClosed/BadRequest/
  HttpVersionNotSupported 抛出点）、`src/io/reader.mbt:217-224`
  （read_until 残片语义）、`src/io/writer.mbt:28-42`（write 进度丢
  弃）、`src/http/send.mbt:93-100/:249-254`（flush 推迟失败/
  IncorrectBodyLength）、`src/os_error/error.mbt:73-75`（OSError）、
  `src/internal/event_loop/io_windows.mbt:136-143`（EOF 折算）、
  `src/tls/transport.mbt:51-94`（TLS 错误缓存）、
  `src/socket/happy_eyeball.mbt:30-106`（竞速语义）、
  `src/async.mbt:218-266`（@async.retry 存在性与语义）
- `specs/003-m1-p03-test-fixtures/spec.md`（FR-015 观测清单、澄清
  D2/D3、B-09/B-10/B-11 夹具契约、证据 E4/E5）
- `specs/004-m1-p04-connection-pool/spec.md`（FR-007 stale_evictions
  语义扩展行、毒化契约、pool-api 建连失败零状态变化、INV-5 守恒）
- `specs/005-m1-p05-call-engine/spec.md`（exchange 接缝、
  CallCancelled 裸变体、ResponseBody 收尾契约、Stream 重放策略归
  P06/P07）
- `specs/006-m1-p06-redirects/spec.md` + `plan.md` + `data-model.md`
  （recover 插入同一循环的接缝约定、轮级 errdefer 毒化单点归属、
  gen 代次机制与 C4 裁决「P07 重放同代次」、research R6「P07 将在
  该错误上做 recover」）
- `.specify/memory/constitution.md`（原则 I/II/III/IV/V/VI/VII）
- 下游引用方：P08（callTimeout 伞覆盖重试轮、超时错误分类对拍、
  builder 承接开关）、P10（闭环场景入基准）
