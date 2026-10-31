# Feature Specification: 四类超时与 per-call 配置（M1-P08）

**Feature Branch**: `008-m1-p08-timeouts`

**Created**: 2026-10-30

**Status**: Draft（qod-1 复核后修订 v2）

**Input**: User description: "仓库文件 docs/roadmap/M1/P08-timeouts-builder.md
的全文（speckit 输入种子，唯一功能描述输入）"。

## User Scenarios & Testing *(mandatory)*

<!--
  用户故事按重要性排序；每条故事独立可测。
  优先级继承种子文件：US-1/US-2/US-3 为 P1，US-4/US-5 为 P2；
  US-6（跟随开关）为 P08 specify 阶段补登（deferred-items F21 钦定
  本包交付，种子范围节有载但未给用户故事）。
  超时归属与错误分类已对拍 OkHttp 5.5.0（取证锚点见「宪法合规口径」
  映射表：recover isRecoverable 的 InterruptedIOException 分支与
  buildRedirectRequest 两开关均为 parent-5.5.0 实测，2026-10-30）。
  P07 承接三件套已消化进 FR-008/FR-009/FR-012：超时错误分类对拍
  （重试判定器扩展）、builder 承接 retry_on_connection_failure 开关、
  call 伞取消形态与重试子循环的共存纪律。
  上游取消语义已实测消化（qod-1 取证，2026-10-30）：catch 不可捕获
  取消（async.mbt:44-47 废弃注记）、取消处理中抛其他错误按失败计且
  组 worker catch 无条件覆盖 Fail 态（task_group.mbt:78-91/:116-119）
  ——据此 call 伞逸出形态钉定为「组内看门者 + 伞内标记位 + 取消收尾
  分支选变体」（FR-002 两处有界例外之一），判定器零误判 stale 为结
  构保证（R4）。
  进程内注入边界（连接伞触发不可注入，R3）与其清理义务（伞×建连成
  功竞态，R5）分列；慢速写载体钉定 Stream 体（R6——Bytes 定长契约
  下大体量停滞对端以 IncorrectBodyLength 收尾，非写窗场景）。
-->

### User Story 1 - 四类超时各自触发（Priority: P1）

作为使用者，慢连接、慢写、慢读、慢全程各自在对应阈值触发，错误类型
可判别（四变体逐一可 `err is` 判别）。

**Why this priority**: 超时的存在性本体——没有可判别的超时错误，使用
者无法区分「对端慢」与「对端坏」；四类归属（连接伞/写窗/读窗/call
伞）是 10 §3.2 四级接线的验收载体，宪法 IV 红绿循环优先区。

**Independent Test**: P03 夹具（B-01 头延迟 / B-12 慢速接收 + 新增
静默读对端）+ 跟随链延迟编排；连接伞例外（触发不可进程内注入，R3
——以白盒接线伴随 + 判定器单元级用例覆盖）。不依赖本包其他故事即
可验收。

**Acceptance Scenarios**:

1. **Given** connect_ms 已配置与连接伞接线，**When** 判定器单元级用
   例喂 `HttpTimeout::Connect`（建连段、无租约、零字节发送），**Then**
   映射为建连失败族（可重试，预算内换新连接；FR-008）；白盒接线伴
   随断言伞包裹建连调用与参数传递链（触发不可注入的诚实边界见 R3，
   竞态清理义务见 R5/US-3-3）。
2. **Given** read_ms=500 与「延迟 2s 回响应头」夹具（B-01 变体），
   **When** execute，**Then** 约 500ms 收头窗内 raise
   `HttpTimeout::Read`（计时带按 C1），错误可 `err is` 判别，连接被
   毒化（US-3）。
3. **Given** write_ms=500 与静默读对端（新增变体：读得极慢且**不关
   闭**连接）+ Stream 大体量 body（约 1MB、分块写出，充满对端接收
   窗与发送缓冲），**When** execute 发体，**Then** 写停滞超过
   write_ms 后 raise `HttpTimeout::Write`（计时带按 C1），连接被毒
   化。（载体钉定 Stream：Bytes 体受 P02 定长契约约束——停滞对端下
   大体量 Bytes 以 `IncorrectBodyLength` 收尾而非写停滞，见 R6 与
   Edge Cases。）
4. **Given** call_ms=1000 与「3 跳 301 跟随链 × 每跳慢」夹具
   （P06 301 编排 + B-01 头延迟组合，每跳延迟和超 call_ms、各单窗
   未超），**When** execute，**Then** `HttpTimeout::Call`（call 伞
   覆盖 follow-up 全程，FR-004）；各窗阈值互不重叠时变体判别正确
   （call_ms 小于其他窗时终态为 `Call` 而非 `Read`——阈值配置关系
   下的归属判别，嵌套同时刻归属不作承诺，见 Key Entities）。

---

### User Story 2 - read 按操作重置（Priority: P1）

作为使用者，慢速但持续滴数据的 body 不触发 read 超时；静默中断则在
一个读窗后触发。

**Why this priority**: FR-003「按操作计时、非整段限时」的唯一行为级
证明载体；慢速大文件下载是超时语义的第一线上线风险区。

**Independent Test**: P03 滴流夹具两态变体（持续滴 vs 滴 K 块后静
默——后者为本包夹具增量，见 Assumptions 登记）。滴流节奏与阈值按
C1 的耗时预算压缩至 1s 量级。

**Acceptance Scenarios**:

1. **Given** read_ms=500 与每 200ms 滴一块的 body（共 5 块、总约
   1s），**When** 读完整 body，**Then** 无超时、内容完整（每次体读
   各享独立读窗，非整段限时）。
2. **Given** read_ms=500 与滴 2 块后静默（连接保持不断开）的
   body，**When** 读至静默段，**Then** 一个读窗后 raise
   `HttpTimeout::Read`（计时带按 C1），且该连接被毒化不回池（FR-006
   体读超时分支）。

---

### User Story 3 - 超时后连接不回池（Priority: P1）

作为池的正确性守护，任何超时异常抛出点持有的连接都被毒化，绝不带超
时状态回池复用；建连段的超时竞态不泄漏池副作用。

**Why this priority**: 池正确性红线——超时后连接状态不可知（可能仍
有在途字节），复用即串响应；与 Call.cancel 同一毒化通道（10 §3.2
「取消后清理」行），是取消语义与超时语义正交性的守护面。

**Independent Test**: 读超时触发后断言池状态（idle 不含该连接、池计
数守恒 004 INV-5）；同址后续请求建新连接（夹具侧连接计数可证）。

**Acceptance Scenarios**:

1. **Given** US-1-2 读超时触发，**Then** 池内 idle 不含该连接、
   borrowed→closed 迁移、池计数守恒（借出+空闲+已关＝累计新建）；
   同址再发起请求时夹具观测到新建连接（非复用旧连接）。
2. **Given** US-2-2 体阶段读超时触发，**Then** 同样毒化不回池（体读
   发生在响应交付后的消费期，毒化义务不因交付完成而豁免；机制＝复
   用 BodyBridge read_checked 既有毒化点，零新增接线，S5）。
3. **Given** 连接伞到期与建连完成的竞态交叠（R5：伞取消到达时建连
   已完成或即将完成），**Then** 池计数守恒恒成立——建连副作用必达
   （租约交付）或被显式关闭并撤销记账，无 borrowed 悬挂、无打开连
   接泄漏（白盒驱动交叠点 + 收敛断言；触发时序本身不可注入，R3）。

---

### User Story 4 - per-call 配置派生（Priority: P2）

作为使用者，我用 `new_builder` 派生客户端（共享连接池）改超时/开关，
只影响派生方的新调用；Request 级 builder 保留 headers/tag。

**Why this priority**: OkHttp newBuilder 派生惯用法的等价物（10
§3.4）；per-call 定制是超时面可用的前提（无人想为单请求重建池），
但不阻塞 P1 三故事的价值。

**Independent Test**: 派生客户端 B 与原客户端 A 同池断言（连接计数
共享）+ 超时隔离断言（B 超时 A 不受影响）；Request 派生保留性断言。

**Acceptance Scenarios**:

1. **Given** client A（默认超时）派生 B（call_ms=300），**When** 经
   B 的调用遇慢夹具（B-01 头延迟 1s），**Then** B 触发
   `HttpTimeout::Call` 而 A 对同夹具的调用正常完成；A、B 的请求复用
   同一池（连接计数共享可证，FR-009 引用语义）。
2. **Given** `Request::new_builder()` 派生，**Then** headers 逐项保
   留、tag 保留，可换 method/url/body（五要素中仅此三者可换）；
   Request 级无超时覆盖位（C2 裁决）。
3. **Given** 派生时覆盖 `retry_on_connection_failure=false`（P07 开
   关承接），**Then** 仅派生方关闭重试、原 client 开关不变（P07 C4
   承接验收）。

---

### User Story 5 - 与取消/重试的交互（Priority: P2）

作为使用者，超时与取消/重试语义正交：callTimeout 覆盖重试轮、取消
优先级不降、超时不被重试层误吞、取消不被超时伞吞掉。

**Why this priority**: P05 取消语义与 P07 重试机器是既有正确性资产；
超时接入不得侵蚀二者（种子 C3 与 P07 前瞻「超时错误分类对拍」的验
收载体；qod-1 B2 的反向隔离方向在此补齐）。

**Independent Test**: P07 stale 组合夹具（先 stale 后成功）× 每轮延
迟编排；取消与超时的竞争场景以不变量断言（二择一终态 + 收敛，不赌
竞速赢家——可控服务端原则）。

**Acceptance Scenarios**:

1. **Given** call_ms=1000 + 「先 stale 后成功但每轮 600ms」场景
   （P07 ServeSequence × B-01 组合），**When** execute，**Then** 两
   轮总计 1.2s → call 伞触发 `HttpTimeout::Call`（覆盖重试轮，FR-004）；
   `stale_evictions` 恰为 1（第一轮合法 stale 命中）——call 伞取消
   形态零误增（FR-008，结构保证见 R4）。
2. **Given** call_ms 已配置且用户 cancel（无论 cancel 先于/后于/竞
   于伞到期），**Then** 终态为 `CallCancelled` 或 `HttpTimeout::Call`
   之一（有序终结、`err is` 可判别），无悬挂协程（TaskGroup 收敛断
   言）、池计数守恒；**反向隔离硬断言**：cancel 明确先于伞到期时终
   态恰为裸 `CallCancelled`（伞不得吞掉用户取消——B2 修法（a）的
   隔离面）。

---

### User Story 6 - 跟随开关（Priority: P2）

作为使用者，我关闭 followRedirects / followSslRedirects 后，3xx 按
OkHttp 语义终态透传，不再自动跟随。

**Why this priority**: deferred-items F21 钦定本包交付（P06 spec 非
目标/映射表钦定，2026-10-28 review 修复批补登）；M1 现行为面＝恒跟
随（＝两开关默认 true），开关只增加「关闭」方向的行为，缺省路径零
变化。

**Independent Test**: P06 301/302 夹具 × 两开关两态矩阵；跨 scheme
（http↔https）场景在 M1 直连明文测试面以判定级/决策表单元级覆盖
（跟随决策表扩展 WB），同 scheme 场景端到端覆盖。

**Acceptance Scenarios**:

1. **Given** follow_redirects=false 与 301 夹具，**When** execute，
   **Then** 301 响应原样终态返回（Location 头保留）、prior 链不累
   积（判据载体＝`Response::prior() is None` 且终态 3xx，S7）、跳数
   预算零消耗（006 follow_ups 语义不变）。
2. **Given** follow_ssl_redirects=false 与跨 scheme 3xx 场景，
   **Then** 该响应终态透传（对齐 5.5.0 buildRedirectRequest 的
   sameScheme 门）；同 scheme 3xx 仍正常跟随（开关只封锁跨 scheme）。
3. **Given** 两开关缺省（true），**Then** 行为面与 P06 交付完全一致
   （恒跟随、恒允许 scheme 变更——缺省路径回归保护）。

### Edge Cases

- call_ms=0（缺省）不限时；四字段值 0 均＝不限且 **MUST NOT 建立
  该级计时窗**（S2：0 不是「立即到期」而是「无窗」）；四字段全 0
  ⇒ 正常完成、零窗构造（用例载体）；负值在构建期快速失败（不静默
  钳制，失败形态沿 004 `validate_pool_config` abort 先例，S3）。
- 阈值极小（1ms）的退化行为：快速失败不 panic；回环夹具即时完成时
  允许「成功」与对应超时变体二择一（断言终态有序、资源无泄漏，不赌
  计时赢家）。
- header 写与首块间的超时归属：header 写归写窗（10 §3.2 ②「含
  header 写出」）——**接线位承诺**：上游 Sender 仅 1024B 缓冲，回
  环上 <1KB 的 header 无法观测写停滞，本条无行为级断言载体，降为
  WB 接线伴随（B7）；头字节滞留缓冲、真正落线在 end_request 尾刷
  ——对端不读导致的写停滞可从收头段逸出而归**读窗**（有意差异，
  映射表 B7 行）。
- 1xx 阶段的 read 计时归属：@http `end_request` 内部跳读 1xx
  （005 research：跳过集 100|102..<200），收头段为单读窗覆盖整个
  end_request 调用（C4 裁决——与 OkHttp 每底层读重置的粒度差异记
  映射表）；行为级用例＝「1xx + 慢头共享同一收头窗」（S9，夹具
  F-8 interim 能力组合 B-01 延迟）。
- 超时错误经重试层不被误吞：`HttpTimeout::Write/Read/Call` 不可重
  试（FR-008），原样透传无包装变体；写段传输失败（对端 close ⇒
  OSError 落 Send 段）仍走 P07 既有 `(Send, Stale) → Retry` 重放，
  本包仅约束 HttpTimeout 变体不重放（映射表登记，B4）。
- call 伞到期取消形态不得被 P07 判定器误判为 stale：零重试轮、零
  `stale_evictions` 误增、终态恰为 `HttpTimeout::Call`（FR-008；结
  构保证——取消不可被 catch 捕获，R4）。
- 体阶段读超时的毒化义务不因响应已交付而豁免（US-3-2；复用既有毒
  化点，S5）。
- 建连伞超时（`HttpTimeout::Connect`）在重试预算内换新连接重试、耗
  尽后透传 `HttpTimeout::Connect` 原始变体（单元级，R3 边界）。
- Bytes 体遇停滞对端：P02 定长契约语义不变（声明长度 ≠ 实发 ⇒
  `IncorrectBodyLength` 收尾）——大体量 Bytes + 不读对端**不是**写
  超时场景（R6；写超时端到端载体＝Stream，US-1-3）。
- `_get_internal_buffer` 直通面绕过 read_checked（P05 既有形态）：
  该面不经读窗、不经毒化——本包判据面＝经 `read_some` 的消费路径，
  直通面不入承诺（S4 登记）。
- builder 派生零串扰：派生方的标量覆盖不影响原 client 任何后续调用
  （US-4-1/3）；两 client 并发使用同一池时连接记账守恒（004 INV-5）。
- 超时阈值经派生链（A 派生 B 派生 C）逐级覆盖，后一派生以前一方的
  当前值为缺省（OkHttp newBuilder 语义）。

## Requirements *(mandatory)*

### 范围

**前置依赖**：P03（B-01/B-02/B-12 慢速夹具与观测清单）、P04（池租
借/毒化/计数契约与 `validate_pool_config` 先例）、P05（Call/exchange
接缝/错误透传/BodyBridge 体读通道与 read_checked 收口）、P06
（follow-up 循环与决策表——跟随开关接入点）、P07（recover 判定器/
建连族/尝试预算——超时分类对拍承接面）。

**包含**：

- `Timeouts` 配置：connect_ms/write_ms/read_ms 缺省 10s、call_ms 缺
  省 0（不限）；四字段独立可配、0＝不限且不建窗、负值构建期快速失
  败。
- 四级接线（时序叠加在 P05 单轮 + P06/P07 循环上，包裹层非流程层）：
  ④ call 伞包 execute 全程；① 连接伞包建连调用；② 写窗包头写与
  每次写调用；③ 读窗包 `end_request` 与每次体读。
- 按操作重置的实现形态：每操作一个计时窗（runtime 原语接线）；单
  Timer + refresh 优化方案留待基准驱动（P10 量化后 M2 决策）。
- `HttpTimeout` 错误四变体（Connect/Write/Read/Call），超时抛出点
  伴随连接毒化（与 Call.cancel 同一毒化通道）。
- `HttpClient::new_builder()`（共享 pool 引用语义，仅覆盖标量）与
  `Request::new_builder()`（headers/tag 保留，可换 url/method/body）。
- `followRedirects`/`followSslRedirects` 关闭跟随开关（builder 配置
  位；P06 spec 非目标与映射表钦定归本包——F21 回补）。
- P07 承接：重试判定器对 `HttpTimeout` 的分类映射（FR-008）；builder
  承接 `retry_on_connection_failure` 开关（P07 C4，FR-009/FR-012）。
- js 降级清单（FR-011）：调用方侧变体语义、底层 fetch 不保证取消、
  降级清单记录。

**非目标（显式排除，clarify 不复议）**：

- Dispatcher 并发闸（P09；enqueue/readyAsyncCalls 同构结构随 P09 交
  付）；connect 阶段 DNS 的可取消性（侵入 socket 线程池，10 §4 明确
  不做——超时后 getaddrinfo 后台跑完仅占线程，不阻塞正确性）；
- 按 Timer::refresh 的单 Timer 优化（P10 基准驱动后决策，14 跟踪）；
- 响应体消费期纳入 call 伞（OkHttp callTimeout 含读体——M1 有意差
  异：体消费期已有每次体读的读窗兜底，伞覆盖到交付为止，FR-004，M2
  复核）；
- Bytes 体分块写出（种子「Bytes 分 16–64KB 块」不采纳——现行单次
  `write_once` 即单写调用点，分块属功能改动且破坏 P02 定长契约观测
  面；写窗粒度承诺已按「每次写调用」口径达成，R6）；
- 拦截器层超时（M1 无拦截器）；wasm-gc（上游 runtime 缺口，仅跟踪）。

### Functional Requirements

- **FR-001**（种子）四类超时 MUST 独立可配：`Timeouts` 含
  connect_ms/write_ms/read_ms/call_ms 四字段，缺省
  10_000/10_000/10_000/0；值 0 ＝不限时且 MUST NOT 建立该级计时窗
  （非「立即到期」）；负值 MUST 在构建期快速失败（不静默钳制；失
  败形态沿 004 `validate_pool_config` abort 先例）。配置为
  HttpClient 构建期不可变标量（随 builder 交付，FR-009）。
- **FR-002**（种子，qod-1 B2/B5 修订）四级接线 MUST 以包裹层形态叠
  加在既有管线上（包裹层＝不改循环/捕获/毒化/预算机器拓扑，仅在既
  有调用点外沿包计时窗）：外层 call 伞 → 循环内：连接伞包建连调用
  → 写窗包头写/每次写调用 → 读窗包收头/每次体读。**两处有界例外**
  （MUST 显式登记于 plan，其余拓扑零改动）：① execute 取消收尾分
  支的标记位变体选择（call 伞逸出通道所需，FR-004）；② acquire 内
  建连调用点的连接伞包裹（池副作用不丢弃所需，FR-006/R5）。
- **FR-003**（种子，qod-1 B4 修订）读/写超时 MUST 按操作计时（每操
  作一个独立计时窗），非整段限时；粒度＝L1 自有调用点与用户写调用
  点：写窗粒度＝header 写调用 / Bytes 整写调用（单次 `write_once`
  即单操作）/ Stream 经 `@io.Writer` 包装面的每次用户写调用（P02
  计数 Writer 包装先例，trait 包装非侵入）；读窗粒度＝end_request
  调用（含内部 1xx 跳读，C4 单窗）/ 每次体读调用。收头段单窗与
  OkHttp「每底层读重置」的粒度差异记映射表。
- **FR-004**（种子，qod-1 B2 裁决）call 伞 MUST 覆盖 execute 全程
  （含全部 follow-up 轮与重试轮，至交付/失败/取消终态为止）：到期
  时序 MUST 准（计时带内触发，C1）、终态变体 MUST 恰为
  `HttpTimeout::Call`、用户取消 MUST NOT 被伞吞掉（反向隔离，US-5-2）。
  逸出形态钉定「组内看门者 + 伞内标记位 + 取消收尾分支选变体」（上
  游 `with_timeout` 包 execute 的形态确定性吞变体——qod-1 B2 取证，
  见映射表注记；具体构造归 plan）。响应体消费期 MUST NOT 纳入 call
  伞（有意差异记映射表；体消费期的每次体读仍有读窗兜底，FR-003）。
- **FR-005**（种子）超时 MUST 以 `HttpTimeout` 四变体之一暴露
  （Connect/Write/Read/Call，可 `err is` 判别），经计时原语的错误注
  入通道实现；超时错误透传 MUST 无包装变体（对齐 P05/P07 透明性先
  例）。
- **FR-006**（种子，qod-1 B3 修订）超时抛出点 MUST 毒化所持连接
  （不回池）：发头/写体/收头段超时经既有轮级 errdefer 逸出路径毒
  化；体阶段读超时 MUST 毒化租约（复用 BodyBridge read_checked 既
  有点，零新增接线，S5）。**连接伞的包裹形态 MUST NOT 丢弃池副作用
  结果**：机制形态归 plan——implement 订正为看门者同型 wait 交付（原
  「只包建连调用本身」的整包/内包设想被 WB⑥ 实测孤儿租约竞态否决，
  见 research R2 订正记录）；伞到期与
  建连完成的任何交叠下，建连副作用必达（租约交付）或被显式关闭并
  撤销记账——004 INV-5 守恒恒成立、无 borrowed 悬挂（US-3-3 验收）。
  全链与 Call.cancel 同一毒化通道语义。
- **FR-007**（种子）连接伞 MUST 覆盖 DNS+TCP+（M1 无 TLS/隧道）的
  整个建连段（含域名解析）；与 OkHttp 的差异（OkHttp connectTimeout
  不含 DNS）记映射表（更严：DNS 慢也限时，10 §3.2 注）。
- **FR-008**（P07 承接，C3 裁决；qod-1 B1 修订）`HttpTimeout` MUST
  接入 P07 重试判定器：建连段 `HttpTimeout::Connect` 映射为建连失
  败族（可重试，预算 ≤2 次尝试内换新连接，耗尽透传原始变体）；
  `Write/Read/Call` 三变体 MUST NOT 重试（族检测落点：Connect→
  ConnectFailure、Write/Read/Call→Other→透传，S6；对齐 5.5.0
  recover 的 InterruptedIOException 分支形状，见映射表）。call 伞
  到期的取消形态零误判 stale 为**结构保证**——取消不可被 catch 捕
  获（上游废弃语义，R4 取证），P07 捕获分支不可能目睹取消形态；零
  重试轮、零 `stale_evictions` 误增随之成立。
- **FR-009**（种子）HttpClient 派生面 MUST 双入口：`HttpClient::new_builder(pool)`
  （pool 根构造，全缺省）与 `HttpClient::builder()`（**自既有 client
  派生**——pool 引用共享、标量缺省取自被派生方当前值，OkHttp
  `client.newBuilder()` 同形；无此入口则调用方无法从既有 client 派生
  共享池的新 client——HttpClient 不暴露 pool）。两者共享 builder 类
  型与 `build()`（负值校验单点）；仅覆盖标量配置
  （timeouts/follow_redirects/follow_ssl_redirects/
  retry_on_connection_failure——P07 开关在此承接，语义不变）。
  pool 引用语义共享（两客户端连接记账同池守恒，US-4-1）。
  `Request::new_builder()` MUST 保留 headers 逐项与 tag，仅可换
  url/method/body；Request 级无超时覆盖位（C2 裁决）。
- **FR-010**（F21 回补）跟随开关两枚（follow_redirects /
  follow_ssl_redirects）MUST 为 builder 配置位、缺省 true（＝P06 既
  有行为面零变化）：follow_redirects=false 时任何 3xx MUST 终态透
  传（Location 保留、prior 链不累积——判据载体 `Response::prior()
  is None`（S7）、跳数预算零消耗）；follow_ssl_redirects=false 时跨
  scheme 3xx 终态透传、同 scheme 照常跟随（对齐 5.5.0
  buildRedirectRequest 的 sameScheme 门语义）。
- **FR-011**（target 面，qod-1 B6 修订）js 降级清单如实登记：js 上
  超时＝调用方按窗拿到对应变体（调用方侧计时原语仍然可用），**不
  保证**取消底层 fetch/连接——上游 `end_request` 内部自建自用
  AbortController、对 L1 无信号入参（`client.js.mbt:195-202` 取证，
  B6），callTimeout 语义在 js 为**弱化形态**（后台 fetch 跑完仅占
  资源、不阻塞调用方）。js 不入质量门（宪法 V 未验证面）：仅要求
  `moon check --target js` 错误数与基线（13 既有）持平零新增，欠账
  随 M5 收口；本条为登记级义务而非 L1 接线义务。
- **FR-012**（.mbti 冻结面，可验收；qod-1 S1 修订）本包公开面新增
  MUST 恰为（按包列举，`.mbti` 按包对账）：① src/client：
  `HttpTimeout` 错误类型（四变体，含判别支持）；② src/client：
  `Timeouts` 配置结构（四字段带缺省）；③ src/client：HttpClient
  builder 派生面——`new_builder` 构造 + build + 标量覆盖位 + 负值
  校验入口（构造/校验为同一公开构造面的组成部分，计 1 项；字段/setter
  具体形态归 plan，以「语义面」为对账单位）；④ src/core：
  `Request::new_builder()` 派生面（与既有 `RequestBuilder` 的关系——
  复用同一构建器或新增派生构造——归 plan，对账单位同为语义面）。
  `HttpClient::new` 签名 MUST 不变（P07 增量保持唯一签名变更先例）；
  无其他公开项。实现完成后 `.mbti` 审视（宪法 VI）以本条为对账面，
  计划外公开项为零。

### Key Entities

- **Timeouts**：四字段构建期不可变配置标量（connect/write/read/call）；
  HttpClient 持有、builder 覆盖、Call 经 client 同包直读（P07 开关
  同形态）。
- **HttpTimeout**：超时错误类型，四变体对应四级伞；判别面＝`err is`
  ；透传面＝无包装。
- **四级伞与嵌套归属**（qod-1 B5 修订）：call 伞（execute 全程）＞
  连接伞（建连段）＞ 写窗（每次写调用）／读窗（收头调用/每次体读）。
  归属规则＝**先逸出的错误变体即归属变体**，本包不承诺同一时刻的赢
  家（外层计时起点更早，阈值相等时外层先触发——机械事实）；构造责
  任在使用者：内层窗阈值应小于外层剩余窗。US 层只断言阈值互不重叠
  时的变体判别。
- **HttpClient 派生面**：new_builder 浅拷贝共享 pool、覆盖标量；
  Request 派生面：headers/tag 保留、五要素换三（url/method/body）。
- **跟随开关**：两枚缺省 true 的 builder 配置位；接入 P06 决策表
  判定路径（false ⇒ 终态短路），不触碰循环/预算/毒化机器。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: US-1–US-6 全部验收场景测试全绿，native 与 wasm 双
  target（wasm 计时带放宽口径按 C1 登记）；`HttpTimeout` 四变体每
  变体至少一个触发或映射用例（R3 边界内）。
- **SC-002**: 四变体判别可证——每类超时终态可 `err is` 判别到具体
  变体（**R3 边界内：Connect 为判定器单元级判别**，无端到端触发
  面，B8），无包装变体、无误吞（US-1/FR-005/FR-008）。
- **SC-003**: 计时带可证——native 上各类超时在
  [阈值−50ms, 阈值+300ms] 带内触发（C1 裁决；wasm 带放宽登记于
  tasks 证据行）；call 伞的时序准确性随 FR-004 在带内成立。
- **SC-004**: 按操作重置可证——持续滴流 body（总时长＞读窗）完整读
  取零超时；滴 K 块后静默 body 在一个读窗后触发 `HttpTimeout::Read`
  （US-2 两态）。
- **SC-005**: 毒化守恒可证——任一超时触发后池 idle 不含该连接、计
  数守恒（004 INV-5）、同址后续请求建新连接；体读超时同样毒化；连
  接伞×建连完成竞态交叠下守恒恒成立（US-3；R5）。
- **SC-006**: 派生隔离与共享可证——派生方超时触发而原方同夹具正常
  完成；两客户端连接计数同池共享；retry 开关覆盖仅影响派生方（US-4）。
- **SC-007**: 跟随开关两态可证——关闭后 3xx 终态透传（prior 链不累
  积、跳数零消耗）、跨 scheme 封锁/同 scheme 放行、缺省路径与 P06
  行为面逐位一致（US-6；F21 验收面）。
- **SC-008**: 交互正交可证——call 伞覆盖 stale 重试轮（1.2s＞1s 触
  发 `Call` 且 `stale_evictions` 恰 1）；超时×取消以二择一终态 +
  TaskGroup 收敛 + 池守恒通过，cancel 先于伞到期时终态恰为裸
  `CallCancelled`（US-5；反向隔离）。
- **SC-009**: 外部网络依赖为 0——全部测试仅访问 P03 本地夹具
  （loopback），断网环境全套测试仍全绿。
- **SC-010**: 公开面零泄漏——实现完成后 `.mbti` 审视显示增量与
  FR-012 冻结面一致（按包对账），计划外公开项为 0。

## Assumptions

- **C1 裁决（2026-10-30，链路内自主裁决；qod-1 S8 修订）**：计时带
  断言的 CI 稳定性——下界收紧防早触发（计时器正确性）：≥ 阈值−50ms；
  上界放宽容宿主调度抖动（共享 runner/CI）：≤ 阈值+300ms。沿用 P03
  B-01 不对称带（−50/+150）先例并放宽上界；wasm 侧带再放宽
  （+300→+1000ms），具体数值在 tasks 证据行登记。种子 ±50ms 口径
  按本条修正。睡眠类长测按 **target 分别计预算（每 target ≤10s）**
  （S8）；滴流/静默场景压至 1s 量级（US-2 已按此设定），逐场景耗时
  表在 tasks 登记。
- **C2 裁决（2026-10-30）**：`Timeouts` 不进 Request（OkHttp 的
  Request 无超时字段；per-call 定制＝client 派生惯用法，5.5.0
  RealCall 同形）；`Request::new_builder()` 不设超时覆盖位。10 §3.4
  草案的「Request 级 timeouts 覆盖」不采纳，记与草案的差异（非与
  OkHttp 的差异）。
- **C3 裁决（2026-10-30，种子澄清 C3 + P07 映射表钦定行消化）**：
  超时分类对拍——种子边界用例「重试层对 HttpTimeout 不重试（超时
  属不可重试分类）」按 OkHttp 5.5.0 实测精化：connect 段超时
  （`HttpTimeout::Connect`，无租约、零字节发送）并入 P07 建连失败
  族可重试（＝5.5.0 路由级重试的 M1 等价物：RoutePlanner 路由重试
  在单路由下退化为 P07 显式预算，P07 C3 既有注记）；Write/Read/Call
  不可重试（5.5.0 recover isRecoverable：InterruptedIOException →
  `SocketTimeoutException && !requestSendStarted`，而
  requestSendStarted = `e !is ConnectionShutdownException` 对超时形
  态恒真——本包 2026-10-30 parent-5.5.0 实测取证，见映射表）。种
  子「一律不可重试」的表述按本条收敛。
- **C4 裁决（2026-10-30；qod-1 S9 补强）**：1xx 阶段与响应头间隙的
  read 计时归属＝收头段单窗（`end_request` 整调用一窗，内部 1xx 跳
  读共享该窗）。依据：L1 非侵入边界内不可拆分上游内部读（005
  research：1xx 跳过在 `@http` client 内部 client.mbt:225-253）；与
  OkHttp 每底层读重置的粒度差异记映射表（更粗，收头段总时长受限而
  非每读受限）。行为级用例「1xx + 慢头共享收头窗」由 F-8 interim
  能力 × B-01 延迟组合交付（夹具已支持，零新增）。
- **C5 裁决（2026-10-30，qod-1 S3）**：负值失败形态沿 004
  `validate_pool_config` 的 abort 先例（构建期快速失败，不引入第三
  种错误呈现形态）。
- **R3 裁决（2026-10-30，US-1-1 注入边界）**：连接伞的端到端超时触
  发在进程内不可确定性注入——回环 TCP 建连即时完成（内核 accept 队
  列完成握手，夹具无法使建连段挂起；backlog 溢出表现为拒绝而非挂
  起）；「accept 后挂起不完成」对端影响的是收头/写段而非建连段。覆
  盖口径按 P07 R1/R2 先例：判定器单元级（`HttpTimeout::Connect` →
  建连族映射）+ 白盒接线伴随（伞包裹与参数传递链结构审判据）+ 记
  诚实边界；种子 US-1-1「accept 后挂起→~500ms Connect」按本条修正
  （种子回写义务见 DoD）。本条覆盖「触发面」；「清理面」（伞×建连
  成功竞态）独立成 R5。
- **R4 裁决（2026-10-30，call 伞取消形态；qod-1 B1 改写）**：上游
  取消语义实测（2026-10-30）：`catch` 不可捕获取消（`async.mbt:44-47`
  `is_cancellation_error` 废弃且恒 false，废弃说明原文「catch can
  no longer capture cancellation」）；被取消任务不算失败，但取消处
  理中抛其他错误按失败计、组 worker catch 对 Fail 态无条件覆盖
  （`task_group.mbt:78-91`/`:116-119`）。据此：P07 判定器对 call 伞
  取消形态**零误判 stale 是结构保证**（捕获分支不可能目睹取消），
  非需取证的风险；取消路径的 defer/errdefer 照常触发 ⇒ FR-006 的毒
  化义务在 call 伞路径自动成立。逸出通道形态选择（看门者 + 标记位）
  归 plan；「取消错误形状取证」候选废止（指向已废弃 API）。
- **R5 裁决（2026-10-30，qod-1 B3；2026-10-31 implement 订正）**：连
  接伞×建连完成竞态的清理义务——`pool.acquire` 在建连成功后先记账
  （borrowed + per_host_total ＋1，client.mbt:244-252）再返回租约；
  若伞包裹形态丢弃该结果，留下 borrowed 悬挂与打开连接，破坏 004
  INV-5。义务与验收见 FR-006/US-3-3。**WB⑥ 实测订正**：整包/内包形
  态的孤儿租约竞态实测成立（fast-path 同步记账尾可先于取消观察点完
  成），机制订正为看门者同型 wait 交付（research R2 订正记录）；上
  游构造器取消的半途资源清理已有 errdefer 行号证据（http/client.mbt:49/:57）。
- **R6 裁决（2026-10-30，qod-1 B4）**：写超时端到端载体钉定 Stream
  体：上游 Sender 仅 1024B 缓冲，大体量 Bytes + 停滞对端以
  `IncorrectBodyLength` 收尾（P02 定长契约，非写窗场景）；Stream 体
  经 `@io.Writer` 包装面驱动（trait 包装，P02 计数 Writer 先例），
  每次用户写调用各享写窗。种子的「Bytes 分 16–64KB 块」不采纳（非
  目标登记）；写段传输失败（对端 close ⇒ OSError）走 P07 既有
  `(Send, Stale) → Retry`，与 HttpTimeout::Write 不重放并行不悖（映
  射表登记）。
- **种子偏差 D 表（2026-10-30 登记；qod-1 B8）**：本包 spec 相对种
  子的全部修正项——①「④ callTimeout：Timer 包全程」→ FR-004 至
  交付为止、体消费期不入伞（有意差异）；②「② 写：Bytes 分 16–
  64KB 块」→ R6 不采纳、写窗按每次写调用口径；③ js 非目标
  「AbortController＋Dispatcher 闸」→ FR-011 弱化形态（Abort
Controller 不可触及）与 P09 归属；④「① 连接伞（DNS+TCP+TLS+隧
  道）」→ FR-007 M1 无 TLS/隧道口径；⑤「±50ms」→ C1 不对称带；
⑥「重试层对超时一律不重试」→ C3 Connect 并入建连族；⑦ US-1-1
  「accept 后挂起→Connect」→ R3 单元级口径；⑧「with_timeout 包
  acquire/包全程」的机制设想 → R4/R5 逸出形态与包裹位置。全部回写
  见 DoD 6。
- **夹具扩展（2026-10-30 登记）**：现有夹具缺两个变体——「滴 K 块
  后静默（连接保持）」（B-02 恒滴到结束、B-09/B-11 以 close 收
  尾）与「静默读对端（读得极慢且不关闭）」（B-12 收尾形态为
  close）；US-2-2 与 US-1-3 所需脚本由本包在 fixtures 包内新增最小
  变体（drip_count 参数化 + 静默保持；SilentReader）。US-1-4 的
  「3 跳×慢」与 US-5-1 的「stale+慢」组合均由既有夹具（P06 301 编
  排/B-01 头延迟/P07 ServeSequence）参数化组合而成。行为判据不变，
  属测试基建增量。

## 宪法合规口径（OkHttp 映射表 / Target 矩阵 / 性能影响 / 测试方案）

**OkHttp 映射表（宪法 III；证据基准 = tag `parent-5.5.0`
`RetryAndFollowUpInterceptor.kt`，两处为本包 2026-10-30 实测取证，
其余转引自种子与 10 README）**：

| OkHttp 5.5.0 行为 | moonhttp 本包对应 | 差异注记 |
| --- | --- | --- |
| 四类超时缺省 connect/write/read=10s、call=0=不限；0＝不限 | FR-001 同缺省、0 同语义且不建窗 | 对齐 |
| read 按操作计时（每读到一块重置） | FR-003 读窗按操作（体读每调用一窗） | 对齐；收头段单窗见下行 |
| 收头阶段每底层读重置（AsyncTimeout 逐读生效） | 收头段单窗覆盖 end_request 整调用（含 1xx 跳读，C4） | **粒度差异**：L1 非侵入边界不可拆上游内部读——收头段总时长受限而非每读受限 |
| write 按操作计时（每写出一块重置，逐 sink write 生效） | FR-003 写窗按写调用（header/Bytes/Stream 每次用户写调用一窗，Stream 经 @io.Writer 包装面） | 对齐粒度；Bytes 为单写调用（分块不采纳，R6）；写停滞经 end_request 尾刷逸出时归**读窗**（见下行） |
| 写停滞按 socket 方向判 write 超时 | 头字节滞留 1024B 缓冲、真正落线在 end_request 尾刷——停滞可从收头段逸出归读窗（B7） | **有意差异（更粗）**：归属按 L1 逸出点，非 socket 方向 |
| callTimeout 覆盖全程含读响应体 | FR-004 覆盖 execute 至交付；体消费期不在伞内 | **有意差异（M2 复核）**：体消费期每次体读仍有读窗兜底（FR-003），静默 body 仍可判 |
| callTimeout 到期抛 SocketTimeoutException（判别＝异常类型） | FR-004 终态恰为 `HttpTimeout::Call`；逸出形态＝看门者+标记位+取消收尾选变体（R4） | 对齐（变体可判别）；机制差异注记：上游 `with_timeout` 包 execute 的形态会以组 Fail 覆盖语义吞掉注入变体（qod-1 B2 取证），故钉定标记位形态；用户取消不被吞（反向隔离） |
| connectTimeout 不含 DNS（DNS 依赖 callTimeout 兜底） | FR-007 连接伞含 DNS | **有意差异（更严）**：DNS 慢也限时（10 §3.2 注） |
| connect 阶段超时由路由级重试承担（RoutePlanner/路由耗尽兜底） | `HttpTimeout::Connect` 并入 P07 建连失败族，≤2 次显式预算（C3） | 对齐形状：M1 单路由显式预算替代路由耗尽（P07 既有注记延续） |
| recover isRecoverable：`InterruptedIOException → SocketTimeoutException && !requestSendStarted`；`requestSendStarted = e !is ConnectionShutdownException`（超时形态恒真） | `Write/Read/Call` 三变体不可重试（FR-008；族落点 Connect→ConnectFailure、余→Other→透传） | 对齐（5.5.0 实测取证 2026-10-30）：发送已开始后的超时不换连接重放 |
| 写段传输失败（IOException）按 recover 常规判定 | 写段 OSError 落 Send 段走 P07 `(Send, Stale) → Retry`（既有面）；本包仅钉 HttpTimeout::Write 不重放（B4） | 对齐：按错误类型判别非按方向 |
| 超时/取消后连接不回池（毒化，03 §3.4） | FR-006 全段毒化接线（与 Call.cancel 同通道）；连接伞×建连竞态守恒（R5） | 对齐 |
| `client.newBuilder()`：共享池/dispatcher，仅覆盖标量 | FR-009 new_builder 浅拷贝共享 pool（dispatcher P09 后承接） | 对齐（M1 共享面=pool） |
| `Request.newBuilder()`：headers/tag 保留、可换 url/method/body | FR-009 Request::new_builder 同语义；无超时位（C2） | 对齐（10 §3.4 草案的 request 级覆盖不采纳，C2） |
| Request 无超时字段；per-call 定制=派生 client | FR-009/C2 Request 无超时位 | 对齐 |
| buildRedirectRequest：`!followRedirects → null`；`!sameScheme && !followSslRedirects → null`（3xx 终态透传） | FR-010 两开关接入 P06 决策表（缺省 true=P06 行为面） | 对齐（parent-5.5.0 实测取证 2026-10-30；F21 回补） |
| js：fetch 路径按操作超时由浏览器行为吸收，callTimeout 经 AbortController | FR-011 调用方侧变体、底层 fetch 不保证取消（AbortController 上游内建自用，L1 不可触及——B6 取证） | target 差异：宪法 V 未验证面，弱化形态如实登记，欠账随 M5 收口 |

**Target 矩阵（宪法 V）**：

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 质量门双绿 target；计时原语全 target 可用；wasm 计时带按 C1 放宽登记 |
| js | ⭕ | **未验证**（宪法 V）：调用方侧超时变体可用；底层 fetch/连接不保证取消（上游 AbortController 内建自用，B6 取证）；按操作伞与 call 伞在 js 均为调用方侧弱化形态（降级清单 FR-011）；仅 `moon check --target js` 与基线（13 既有）对账零新增，不入门禁，欠账随 M5 收口 |
| wasm-gc | ❌ | 上游 runtime 缺口，仅显式排除说明 |

**性能影响（宪法 II）**：每操作一窗的 Timer 创建/取消 ~百 ns 级，
块 ≥16KB 时占比 <0.1%（10 §6 预算）；call 伞每 execute 一 Timer，
O(1)。快乐路径（未超时）成本＝窗创建/销毁，进入热路径——P10「超时
开/关」对比场景量化，超出预算则 M2 转 refresh 方案。本包测试不断言
性能数字（计时带断言为功能正确性，非基准）。

**测试方案（宪法 IV）**：US-1-2/3/4 用 B-01 头延迟/静默读对端（新
变体）/301 链编排触发，断言变体判别与 C1 计时带；US-2 两态滴流（新
夹具变体）；US-3 池计数断言（004 INV-5 + idle 不含 + 夹具连接计数
+ R5 竞态收敛）；US-4 派生共享/隔离断言；US-5 stale×call 伞组合
（P07 ServeSequence）与取消竞争不变量断言（含反向隔离硬断言）；
US-6 两开关两态矩阵（301 夹具端到端 + 跨 scheme 决策级单元）；判定
器矩阵扩展 WB 按 S6 收敛＝四变体 × {Connect, Send, ReadHead} 可达
格 + 族落点断言（Connect→ConnectFailure、Write/Read/Call→Other）；
白盒接线伴随（四伞参数传递链与两处有界例外位点，P07 WB⑭ 先例）；
1xx+慢头共享收头窗场景（C4/S9）；红-绿循环优先区＝FR-008 分类矩阵
与 FR-010 开关短路。native+wasm 双绿（耗时预算每 target ≤10s，C1/
S8）；js 仅 check 对账。

## 包级 DoD（验收判据）

1. US-1–US-6 验收场景测试全绿（native/wasm 双 target）；计时带按
   C1；`HttpTimeout` 每变体至少一个用例（R3 边界口径）。
2. `moon info && moon fmt` 干净；`.mbti` 新增面恰为 FR-012 冻结面四
   项（按包对账）并经审视；`HttpClient::new` 签名不变。
3. js `moon check` 与基线（13 既有）对账零新增；js 降级清单写入本
   spec（映射表/Target 矩阵）与用户文档（README 超时配置段，落地形
   态 plan 定）。
4. **既有全量回归**（qod-1 S11）：004/005/006/007 全部既有用例在新
   缺省窗（connect/write/read=10s）下 native/wasm 双绿；如有需放宽
   的用例（长睡眠夹具逼近缺省窗）逐条登记。
5. 与 OkHttp 的语义差异（收头单窗粒度、写停滞尾刷归读窗、体消费期
   不在 call 伞、连接伞含 DNS、显式变体替代异常判别、C2 Request 无
   超时位、js 弱化形态）保留于本 spec 映射表，implement 阶段不回改
   语义。
6. P07 承接三件套消化证据落 tasks：超时分类矩阵（FR-008）、builder
   承接 retry 开关（FR-009）、call 伞取消形态零误增 + 反向隔离
   （FR-008/US-5）。
7. **种子回写（qod-1 B8 修订）**：`docs/roadmap/M1/P08-timeouts-builder.md`
   按 Assumptions 种子偏差 D 表八项逐项回写订正，与 006/007 先例
   （种子按裁决回写）一致。
8. F21 回补闭环：`docs/roadmap/deferred-items.md` 与
   `deferred-items/deferred-items-m1.md` 的 F21 状态列更新为已回补
   （指向本包交付）。
9. P06 spec 映射表行加注（「开关不在 M1 公开面」→「已由 008 交
   付」，见 Assumptions 登记）。

## 待澄清项（移交 /speckit.clarify）

种子澄清问题 C1–C4 已于 2026-10-30 链路内按「种子默认 + 上游实测 +
OkHttp 5.5.0 对拍」自主裁决并回记；qod-1 复核后增补 C5（负值失败形
态）与 R3–R6 四条证据裁决（注入边界、取消语义结构保证、竞态清理义
务、写载体钉定）及种子偏差 D 表。无 [NEEDS CLARIFICATION] 标记，无
待 owner 裁决的未决项；裁决全文见 Assumptions。owner 如推翻任一裁
决，须回改本 spec 后再向下传导（宪法「先审后跑」）。

## Clarifications

### Session 2026-10-30（specify/clarify 合并裁决，承 006/007 先例自主推进）

1. **C1 计时带 CI 稳定性** → 不对称带 [阈值−50, 阈值+300]ms（native），
   wasm 再放宽；长测按 target 分别计预算（≤10s/target）。
2. **C2 Timeouts 归属面** → 仅 HttpClient 级（builder 覆盖）；
   Request::new_builder 无超时位（OkHttp Request 形状对齐）。
3. **C3 HttpTimeout × P07 重试分类** → Connect 并入建连族可重试
   （路由级重试 M1 等价物）；Write/Read/Call 不可重试（5.5.0
   isRecoverable 实测形状）。
4. **C4 1xx read 计时归属** → 收头段单窗（end_request 整调用，内部
   1xx 跳读共享；L1 非侵入边界），粒度差异记映射表；行为级用例经
   F-8×B-01 组合交付。
5. **C5 负值失败形态** → 沿 004 `validate_pool_config` abort 先例。
6. **R3 连接伞端到端注入边界** → 回环建连即时完成、不可确定性注入；
   判定器单元级 + 白盒接线伴随覆盖；种子 US-1-1 按此修正。
7. **R4 call 伞取消形态（qod-1 B1 改写）** → 取消不可被 catch 捕获
   （上游废弃语义）：判定器零误判 stale 为结构保证；逸出通道＝看门
   者+标记位+取消收尾选变体（「取消错误形状取证」候选废止）；用户
   取消不被吞（反向隔离）。
8. **R5 连接伞×建连完成竞态（qod-1 B3）** → 伞只包建连调用（记账
   前）；任何交叠下池守恒恒成立（US-3-3 验收）。
9. **R6 写超时载体（qod-1 B4）** → Stream 体 + 静默读对端（新变
   体）；Bytes 大体量停滞对端=IncorrectBodyLength（非写窗场景）；
   「Bytes 分块」不采纳；写窗 per-op 经 @io.Writer 包装面达成。
10. **夹具缺口登记** → 「滴 K 块后静默」与「静默读对端」两变体由本
    包新增（fixtures 最小变体）；其余场景由既有夹具参数化组合。

**owner 待裁决项：无。** C1–C5/R3–R6 均按宪法 III（5.5.0 基准）与
上游实测证据自主裁决并记录理由；qod-1 八阻断（B1–B8）全部采纳落笔，
十二建议（S1–S12）全部采纳；如 owner 推翻，回改本 spec 后再向下传
导。

### Session 2026-10-31（implement 级机制订正登记，承 research R2）

1. **R2 连接伞形态订正（WB⑥ 实证）** → 原「`with_timeout` 整包 acquire」
   存在孤儿租约竞态（fast-path 同步记账尾先于取消观察点完成 ⇒ 记账
   完成而租约被组丢弃，native/wasm 双现）→ 订正为看门者同型
   wait 交付；FR-006/R5/INV-T3 的义务与不变量不变，机制形态以本条
   为准（详见 research R2 订正记录）。
2. **T013 看门者 no_wait 订正（WB⑦ 实证）** → waited 看门者使正常
   交付路径被组收尾拖满 call_ms（5s 悬挂实证）→ 改 no_wait 即发即
   忘（失败路径组 cascade 取消仍覆盖）；FR-004 语义不变。
3. **上游锐边适配** → 已取消协程不构造 with_timeout 组（上游
   PanicError）；`Task::cancel` 后 `task.wait` 以
   WaitedTaskAlreadyCancelled 呈现（P05 R1 同款）。

三条均为机制级订正，FR/SC 语义零变化；证据与形态详见 research R1/
R2 订正记录与 contracts §2。

## 参考

- `docs/roadmap/M1/P08-timeouts-builder.md`（本包唯一规格种子）
- `proj-init-docs/okhttp-on-async-http/10-timeouts-dispatcher/README.md`
  §1（OkHttp 行为规格）、§2（runtime 原语取证）、§3.1（配置面）、
  §3.2（四级接线与毒化）、§3.4（builder 派生）、§4（侵入性清单——
  DNS 不可取消行）、§5（js 降级）、§6（性能预算）、§8（测试方案）
- OkHttp 5.5.0 取证锚点（parent-5.5.0
  `RetryAndFollowUpInterceptor.kt`，两处 2026-10-30 实测取证，其余
  转引）：recover `requestSendStarted = e !is
  ConnectionShutdownException`（P07 锚点 :139 语境的 5.5.0 形态）、
  isRecoverable `InterruptedIOException → SocketTimeoutException &&
  !requestSendStarted`（P07 锚点 :177-178 同源）、buildRedirectRequest
  两开关门（`!followRedirects` / `!sameScheme && !followSslRedirects`）
- 上游 runtime 取证（2026-10-30 实测）：`async/src/pkg.generated.mbti`
  （`with_timeout`/`Timer{cancel,refresh,wait}` 签名）；
  `async/src/async.mbt:44-47`（is_cancellation_error 废弃——catch 不
  可捕获取消）、`:96-118`（with_timeout 实现＝task_group + timer 子
  任务先 raise 再取消全组）；`async/src/task_group.mbt:78-91`
  （worker catch 对 Fail 态无条件覆盖）、`:116-119`（取消不算失败/
  取消处理中抛其他错误按失败计）——R4/B2 证据链
- 上游 http 取证：`src/http/client.js.mbt:195-202`（AbortController
  内建自用，L1 无信号入参——B6）；Sender 1024B 缓冲与
  IncorrectBodyLength（send.mbt:249-254，P07 既有锚点）
- `specs/003-m1-p03-test-fixtures/spec.md`（B-01/B-02/B-12 夹具契
  约、FR-015 观测清单、B-01 不对称计时带先例）
- `specs/004-m1-p04-connection-pool/spec.md`（租借/毒化契约、
  INV-5 守恒、建连失败池状态零变化、validate_pool_config abort 先
  例）
- `specs/005-m1-p05-call-engine/spec.md` + research（exchange 接
  缝、错误透传、BodyBridge read_checked 收口、1xx 跳过锚点
  client.mbt:225-253、C3 回调不暴露）
- `specs/006-m1-p06-redirects/spec.md`（follow-up 决策表、跳数预
  算、轮级 errdefer 毒化单点、301 夹具编排、映射表「开关归 P08」行）
- `specs/007-m1-p07-stale-retry/spec.md`（recover 判定器六条件、建
  连失败族、尝试预算、ServeSequence 夹具、映射表「P08 需消化」行、
  C4 builder 承接裁决）
- `src/core/request_body.mbt`（Stream 回调收 `&@io.Writer` trait、
  P02 计数 Writer 包装先例——R6 写窗包装面依据）
- `docs/roadmap/deferred-items.md` F21（跟随开关欠账登记）
- `.specify/memory/constitution.md`（原则 I/II/III/IV/V/VI）
- 下游引用方：P09（Dispatcher 复用 builder 面）、P10（超时开/关对
  比量化场景、refresh 方案决策输入）
