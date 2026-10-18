# P07 连接失败重试（stale-retry 闭环）

> 里程碑：M1 性能核心 ｜ 前置依赖：P04、P05、P06 ｜ 人力估计：~1.5 人日
> 来源：`proj-init-docs/okhttp-on-async-http/02-redirects-retries/README.md` §3.3/§6/§8
> 侵入性：非侵入 ｜ 建议特性 slug：`m1-p07-stale-retry`

## 功能描述（speckit 输入种子）

在 P06 的 follow-up 循环中加入**连接失败恢复**（OkHttp
`RetryAndFollowUpInterceptor.recover` 等价物，`retryOnConnectionFailure`
默认开）：对「可重试的失败」（陈旧连接首读即断、连接建立失败、TLS 握手失败）
换一条**新连接**重放请求（旧连接毒化）。发送路径拆成两个可观测阶段
（写 body / 读响应头），以「是否已写出字节」与「读头阶段错误类型
（`ReaderClosed`＝EOF 族、`BadRequest`＝协议错误族，分流见范围节）」界定
可重试性——@http 不暴露「状态行已解析」信号，该内部状态不得作为
判定依据（specs/003-m1-p03-test-fixtures 澄清 D3/证据 E4；欠账 F17，
2026-10-18）。
这是 M1 交付判据之二「stale-retry 闭环」的载体，也是连接池正确性的必要配套
（池化不配 stale-retry 会让长闲连接场景错误率上升，03 §6）。

## 范围

包含：

- 可重试判定（对齐 02 §3.3）：
  `retryOnConnectionFailure 开启 ∧ 失败类型 ∈ {连接建立失败, 陈旧连接（取出后首读即 EOF/Reset）, TLS 握手失败} ∧ 请求体可重放 ∧ 未收到任何响应字节（可观测口径＝读头阶段以 @io.ReaderClosed 失败，分流见下条） ∧ 未被取消 ∧ 尝试次数 < max_attempts（默认 2）`。
- 阶段化发送的可观测性（**按错误类型分流；钉死集合是可观测集合，不等同
  可重试集合**）：写阶段失败且 `bytes_written == 0` → 可重试；读头阶段分流：
  - `@io.ReaderClosed`（parser.mbt:401-403——read_until 返回 None，零字节真
    EOF）→ 对齐 OkHttp EOF 路径（Http1ExchangeCodec.kt:247-252 把
    EOFException 重包为普通 IOException「unexpected end of stream」，落入
    RetryAndFollowUpInterceptor.kt:197 兜底 `return true`）→ **可重试**、
    判定陈旧连接；
  - `BadRequest`（parser.mbt:404/:410-413——畸形片段已作为状态行解析；:407
    HttpVersionNotSupported 同族）→ 对齐 OkHttp 协议错误路径
    （RetryAndFollowUpInterceptor.kt:171-173 isRecoverable 首行
    `if (e is ProtocolException) return false`）→ **不可重试**但**毒化**
    （毒化与重试解耦：任何失败都 trackFailure→noNewExchanges，
    RealConnection.kt:398-400）。
  全链没有任何以「状态行是否已解析」为条件的判定（OkHttp 替代信号＝
  requestSendStarted:139、isOneShot:145/:157-163、超时类型:177-178）；@http
  同样不暴露解析进度，「状态行是否已解析」不可作为判定依据（specs/003
  澄清 D3/证据 E4；欠账 F17）。连接被 reset 的客户端表现
  （@os_error.OSError）是否并入可重试面，由 P07 spec 依 P03 的 FR-015
  观测清单裁决（F16：RST 不可确定性注入）。
- 重放执行：新连接（新 Lease）重发；第一次立即重试（对齐 OkHttp——不退避，
  靠路由切换）；`max_attempts` 默认 2（若未来暴露更大值则接 `@async.retry` 退避）。
- 毒化与观测：陈旧连接 close 不回池；`pool.stale_evictions` 计数递增。
- 路由维度说明：`connect_to_host` 内部已是 Happy Eyeballs 多地址竞速
  （`happy_eyeball.mbt:30-106`），单次 connect 已含「换路由」；L1 的整体重来
  一次覆盖竞速全败后的瞬时故障（spec 记录，无代码项）。

非目标（显式排除）：

- 408/503 响应级重试（D7，不做）；Authenticator 相关恢复（M2/08）；
- 代理路由失败语义（M2 代理引入后扩展）；退避策略（max_attempts=2 场景无退避）；
- 收到部分响应字节后的重试（语义禁止，一律不可重试）。

## 用户故事种子

### US-1 陈旧连接自动恢复（P1，M1 判据核心）

作为使用者，从池中取出的连接已被服务端静默关闭；我的请求自动换新连接重放成功，
全程无错误暴露。

**独立测试**：P03「accept 后立即 close」与「复用连接上不发响应直接断」脚本。

**验收场景**：

1. Given 预热连接入池空闲超期（夹具已关闭它），When execute，
   Then 首次尝试失败后自动换新连接重放、终态响应正确、用户无感知错误。
2. Given 上述场景，Then `pool.stale_evictions` 递增、旧连接未回池、池计数守恒。

### US-2 连接建立失败重试（P2）

作为使用者，connect 阶段的瞬时失败（如竞速全败后的短暂拒绝）在重试预算内
自动恢复。

**验收场景**：

1. Given 夹具端口先拒绝 N-1 次后可用（P03 脚本），When execute，
   Then 在 max_attempts 内成功（M1 直连单地址，此场景为「整体重来一次」语义）。

### US-3 不可重试分类（P1）

作为使用者，语义上不可安全重放的失败原样抛出，不产生重复副作用。

**验收场景**：

1. Given P03「回半截响应头后断」脚本（截断点由夹具声明，specs/003 B-11），
   When execute，Then 客户端错误落在钉死可观测集合 {BadRequest, ReaderClosed}
   （specs/003 澄清 D3/证据 E4；欠账 F17），并按错误类型分流：
   `BadRequest`（畸形片段已作为状态行解析＝已收到字节）→ 不可重试、连接毒化
   （对齐 OkHttp RetryAndFollowUpInterceptor.kt:171-173 协议错误不可重试）；
   `ReaderClosed`（EOF 路径）→ 可重试、判定陈旧连接（对齐 RetryAndFollowUp
   Interceptor.kt:197 兜底与 Http1ExchangeCodec.kt:247-252 的 EOF 重包）。
   注意钉死集合是可观测集合、不等同可重试集合；两类形态的最终措辞在
   P07 spec 记录与 OkHttp 的映射。
2. Given `Stream` body 已写出部分字节后写失败，Then 不重试（副作用可能已发生）。
3. Given 调用方已 cancel，Then 以 `CallCancelled` 终止、不走重试分支。
4. Given 重试预算耗尽（第 max_attempts 次仍失败），Then 透传最后一次原始错误。

### US-4 计数与观测（P2）

作为运维/基准下游（P10、未来 06），我从池读取 `stale_evictions` 等计数，
量化陈旧连接发生率。

**验收场景**：

1. Given 注入 K 次陈旧连接失败，Then 计数恰为 K（不因不可重试路径误计）。

## 边界用例

- 可重放 body 为 `Bytes` 且重放两次（第一次 stale、第二次成功）——线上字节
  逐字节一致（L3/重放性联合断言）；
- 写阶段失败但 `bytes_written > 0`（部分写出）→ 不可重试；
- `end_request` 读头阶段错误按类型分流（与「阶段化发送的可观测性」一致）：
  `BadRequest`（协议错误族，对齐 RetryAndFollowUpInterceptor.kt:171-173
  `ProtocolException → 不可重试`）→ 走毒化不重试（毒化与重试解耦，
  RealConnection.kt:398-400）；`ReaderClosed`（EOF 族，
  Http1ExchangeCodec.kt:247-252 → RetryAndFollowUpInterceptor.kt:197 兜底）→
  可重试；
- 重试轮间 cancel（guard 生效）；重试与重定向叠加（先 stale 恢复再跟随 301，
  总 follow-up 计数语义在 spec 定义——重试是否占用 20 跳预算，澄清 C3）。

## 需求种子

- **FR-001** 系统 MUST 按 02 §3.3 判定式界定可重试性（六条件合取）。
- **FR-002** 读头阶段以 `BadRequest`（畸形状态行片段，parser.mbt:404/:410-413
  协议错误族）失败 MUST NOT 重试（毒化照常，对齐 OkHttp
  RetryAndFollowUpInterceptor.kt:171-173）；`ReaderClosed`（EOF 族，
  parser.mbt:401-403）可重试。
- **FR-003** `Stream` body 已写出任意字节后 MUST NOT 重试。
- **FR-004** 陈旧连接 MUST 毒化（close 不回池）并递增 `stale_evictions`。
- **FR-005** 重试 MUST 换新 Lease（不复用失败连接），预算默认 2 次、不退避。
- **FR-006** 重试判定 MUST 在取消检查之后（取消优先于重试）。

## 关键设计要点

- 阶段化由 L1 自身控制（L1 负责调 `request`/`write`/`end_request`，故在 L1 侧
  捕获错误时已知阶段——02 §4「写路径阶段化由 L1 自身控制」，无需侵入 @http）。
- 可重试分流以捕获到的**错误类型**判定（`ReaderClosed`＝EOF 族、
  `BadRequest`＝协议错误族，parser.mbt:401-413），L1 在 `end_request` 错误
  捕获点即可取得，无需侵入 @http（02 §4 侵入项「低必要性」，不做侵入；
  「状态行是否已解析」不可观测、不作判据——F17）。
- recover 分支插在 P06 循环内：`chain.proceed` 抛错 → recover 判定 → 可重试则
  新 Lease 重入循环；不可重试则 re-raise。

## 侵入性与宪法合规

- 非侵入（02 §4 表：stale-retry 非侵入）。
- 宪法 IV：每条判定分支有先写测试（红-绿循环优先区——本包分支多、边界密）。
- 宪法 III：与 OkHttp 差异（max_attempts 显式化为 2、TLS 握手失败重试面在
  M1 直连下的实际覆盖）在 spec 记录。

## target 矩阵

| target | 支持 | 说明 |
| --- | --- | :-: |
| native | ✅ | 故障注入＝close/FIN + 依实测钉死的 FIN/RST 观测清单（specs/003 FR-015）；RST/半关（shutdown/SO_LINGER）为上游能力缺口（F16），不作为可得判据 |
| wasm | ✅ | 宿主上 close 的线上形态（FIN/RST）依 OS 与在途数据而变，观测清单见 specs/003 FR-015（P03 澄清 D2，原 C3）；允许断言降级但行为不降级 |
| js | ⭕ | fetch 连接由浏览器管理，无陈旧连接概念；本包在 js 不激活 |
| wasm-gc | ❌ | 上游 runtime 缺口 |

## 性能影响

stale-retry 把「陈旧连接导致的用户可见失败」变成 ~1 次额外 RTT 的延迟——
池化（L1）的必要配套。重试路径复用 L3 折叠缓存与可重放 body，零额外重排成本。

## 测试方案

- US-1/2/3 全部基于 P03 故障注入脚本；每条判定条件一个正例+一个反例。
- 重放字节一致性用捕获对端断言。
- native + wasm 双绿（wasm 断言强度按 P03 澄清 D2/FR-015 观测清单调整并记录）。

## 澄清问题种子

- **C1** 「TLS 握手失败可重试」在 M1 直连无路由选择下的实际语义（仅当错误
  分类可区分握手阶段时才纳入；M1 测试以明文 http 为主，TLS 分支允许仅实现
  判定框架 + 单元级用例）。
- **C2** `bytes_written` 计数的实现位置（写路径包装计数 vs 异常上下文携带）。
- **C3** 重试与 20 跳 follow-up 预算的关系（OkHttp 内部 recover 与 follow-up
  为独立计数——遵 OkHttp 分离，spec 记录）。
- **C4** `retryOnConnectionFailure` 开关的配置面（HttpClient builder 字段，
  与 P08 的 builder 设计合并交付）。

## 验收判据（包级 DoD）

1. US-1–US-4 验收场景测试全绿（native 必须全绿；wasm 按 C3 结论执行并记录降级）。
2. M1 判据「stale-retry 闭环」在本包 DoD 内闭环：预热→空闲关闭→自动恢复→
   计数正确（端到端用例）。
3. `moon info && moon fmt` 干净；`.mbti` 新增面（retryOnConnectionFailure 配置）
   经审视。

## 参考

- `02-redirects-retries/README.md` §3.3（判定式与阶段化）、§4（侵入性）、§6、§8。
- `03-connection-pool/README.md` §3.3（被动检测设计）、§3.4（毒化表 stale 行）。
- 下游引用方：P08（超时与重试交互——callTimeout 伞覆盖重试轮）、P10（闭环场景
  入基准）。
