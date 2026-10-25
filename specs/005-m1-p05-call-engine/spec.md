# Feature Specification: Call 执行骨架与取消（M1-P05）

**Feature Branch**: `005-m1-p05-call-engine-cancel`（2026-10-25 实测分支名；
特性目录为 `005-m1-p05-call-engine`）

**Created**: 2026-10-24

**Status**: Draft

**Input**: User description: "仓库文件 docs/roadmap/M1/P05-call-engine-cancel.md
的全文（speckit 输入种子，唯一功能描述输入）"。

## User Scenarios & Testing *(mandatory)*

<!--
  用户故事按重要性排序；每条故事独立可测——只实现其中一条也应产出可用价值。
  优先级继承种子文件：US-1/US-3/US-5 为 P1，US-2/US-4 为 P2。
-->

### User Story 1 - execute 单次请求与连接复用（Priority: P1）

作为使用者，我用 `HttpClient` 发起 GET/POST（Bytes/Stream 体），得到完整
`Response`（code/headers/body）；连续请求复用池化连接，不重复建连。

**Why this priority**: 门面的核心价值路径——execute 直连管线是 P06/P07/
P08/P09 全部下游能力的承载底座；没有它，池（P04）无法被终端用户触达。

**Independent Test**: P03 脚本化服务端（echo/连接计数夹具）；不依赖
P06/P07/P08/P09，单包可完整验收。

**Acceptance Scenarios**:

1. **Given** echo 夹具，**When** execute 带 body 的 POST，**Then**
   code/headers/body 正确、body 内容回显一致。
2. **Given** 同一 HttpClient 连续 3 次 execute 同一 Address，**Then** 仅
   第 1 次新建连接（夹具侧连接计数与池计数双断言一致）。
3. **Given** `Connection: close` 响应，**When** 响应体读完后再次 execute，
   **Then** 新建连接（旧连接未回池）。
4. **Given** 未知长度 Stream 体，**When** execute，**Then** 以 chunked
   发送成功（夹具接收侧校验帧形态与内容）。

---

### User Story 2 - Call 一次性语义（Priority: P2）

作为使用者，同一 Call 二次 execute 得到明确错误（可判别的状态错误类），
而非未定义行为（对齐 OkHttp「Call 不可重复执行」）。

**Why this priority**: 契约小但属恶性未定义行为防线；不阻塞主干管线，
故列 P2。

**Independent Test**: 纯 Call 状态断言（完成/取消/失败后重复 execute），
不需要网络动作。

**Acceptance Scenarios**:

1. **Given** 已完成（或已失败/已取消）的 Call，**When** 再次 execute，
   **Then** raise 可判别的状态错误（类型明确，非 panic、非静默重跑）。

---

### User Story 3 - cancel 三阶段（Priority: P1）

作为使用者，我在任意时点 `cancel()`：发出前、发送中（写 body）、读响应
体中；调用以 `CallCancelled` 终止，被取消连接不回池。

**Why this priority**: 取消是用户可控的资源释放保证，是 P08 超时与 P09
可取消 enqueue 的共同底座；「毒化不回池」同时是池正确性（P04 契约）在
管线侧的闭环条件。

**Independent Test**: P03 慢速/滴流夹具 + 池计数断言；不依赖
P06/P07/P08/P09。

**Acceptance Scenarios**:

1. **Given** 尚未 execute 的 Call 已 cancel，**When** execute，**Then**
   立即 raise `CallCancelled`、无任何网络动作。
2. **Given** P03 慢速接收对端 + 大 body 写入中，**When** cancel，**Then**
   写入路径以 `CallCancelled` 失败、池内该连接被毒化关闭
   （不回池，池计数可断言）。
3. **Given** 慢速滴流 body 读取中，**When** cancel，**Then** 读路径以
   `CallCancelled` 失败、连接毒化（in-flight 读失败同样
   映射，见 Clarifications 第二轮第 1 条）。
4. **When** cancel 后查询 `is_cancelled`，**Then** 为 true；重复 cancel
   幂等无错。

---

### User Story 4 - 重放零折叠（L3，Priority: P2）

作为重定向/重试路径的下游（P06/P07），Call 上的折叠头在多次重放间复用，
不重复执行 HeadersV→Map 折叠（差异 D4 收敛口径：@http 内部逐段 blit
不可避免，零折叠指上层折叠恰好一次）。

**Why this priority**: L3 性能杠杆的机制级保证，收益在 P10 的重定向/
重试基准中量化；机制断言可先于真实重定向逻辑（桩接缝）独立验收，故列
P2。

**Independent Test**: 桩接缝在同一 Call 内强制重放 N 次 + P03 捕获对端
字节比对，不经 P06/P07。

**Acceptance Scenarios**:

1. **Given** 带多条头与 Bytes 体（可重复体）的 Request，**When** 同一
   Call 内部强制重放 N 次（桩接缝模拟），**Then** 折叠函数仅执行 1 次
   （计数断言）、N 次线上字节逐字节相同（P03 捕获对端比对；Stream 体
   不在重放断言范围）。

---

### User Story 5 - 响应体生命周期闭环（Priority: P1）

作为使用者，Response 的消费方式决定连接去向：读到底→回池；未读完丢弃→
尝试 skip 后回池，失败则毒化；异常→毒化。

**Why this priority**: 归池/毒化执行侧闭环是池无泄漏、无串响应的管线侧
一半（与 P04 的契约侧配对）；路由错误将直接造成挂死或连接泄漏。

**Independent Test**: P03 夹具（echo/残数据/断连注入）+ 池计数断言；
不依赖 P06/P07/P08/P09。

**Acceptance Scenarios**:

1. **Given** 流式 body 读到最后一块，**Then** 连接回池（下次 execute
   复用，新建连接计数不增）。
2. **Given** body 读一半即弃，**Then** 连接被 skip 清理回池（夹具侧下个
   请求读到干净流、无残帧）。
3. **Given** skip 失败（P03 注入残数据后断连），**Then** 连接毒化关闭、
   池计数守恒。

---

### Edge Cases

- execute 中抛非取消错误（连接被 RST）→ 错误透传给调用方、连接毒化
  （重试判定归 P07，本包只保证不回池）。
- 1xx 信息响应后再 200：@http 自动跳过并回调既有行为透传（取证锚点
  `client.mbt:232-253`），execute 最终返回最终响应。
- 空 body 响应（Content-Length: 0）→ Response 正常返回，body 消费即刻
  完成、连接回池。
- 同一 HttpClient 并发多个 Call → 各自租借不同连接、互不干扰（池并发
  租借前提，P09 之前无闸门）。
- cancel 与 release 竞争（cancel 恰在 body 读完后到达）→ 不 double-
  close、不报错；已归池连接不受迟到 cancel 影响。

## Clarifications

### Session 2026-10-24

- Q: 「未读完即弃」响应体的处置，是否维持 FR-015 的两段式收敛（默认按
  P02 回调契约处置，若 plan 证实析构时机不可靠再改为强制显式丢弃 API）？
  → A: 维持两段式；公开面维持最小，plan 裁决结果回记本 spec。
- Q: 1xx 信息响应（如 100 Continue）的处理进度，是否需要在 M1 就作为
  公开 API 暴露给使用者（例如可注册的回调）？ → A: M1 不暴露——维持
  宪法 VI 最小面，FR-010 仅透传既有跳过语义；暴露与否留 M5 与 101 一并
  裁决。
- Q: 读响应体期间 cancel()（此时 execute 已返回，取消仅经「标记 + 同步
  关连」生效）导致的 in-flight 读取失败，错误如何判别？ → A:
  `cancelled==true` 时读路径任何失败一律映射 `CallCancelled`（形态
  后由 2026-10-25 第三轮定为裸变体），网络错误仅在未取消时透传（
  2026-10-24 第二轮裁决；US-3-3/
  FR-002a 据此统一，SC-003「以 CallCancelled 终止」口径获得确认；
  dispose/skip 收尾路径的同类竞争仍按 data-model 实体 4 的
  no-op 收敛）。
- Q: `ResponseBody::dispose()` 对「同一 body 二次调用」与「先 `drop()`
  再 `dispose()`」两个入口的行为应如何裁定？ → A: dispose 幂等——收尾
  动作整体至多一次有效、已完成即 no-op（内部「已收尾」标记）；`drop()`
  仅置状态、不阻断首次 dispose 收尾（Dropped 事件先到者赢不重发，
  `on_dispose()` 补执行一次）。不重开 FR-015 裁决本体（API 形状不变），
  条款见 contracts §2 第 6 条（2026-10-24 第二轮裁决）。
- Q: FR-004/SC-004 的「N 次线上字节逐字节相同」重放断言，是否限定为
  可重复体（Bytes）？ → A: 限定 Bytes——Stream 体一次性，其重放策略
  （缓冲/拒绝）归 P06/P07；对齐 OkHttp「不可重复体限制重定向/重试」
  语义与 FR-006 单轮接缝定位（2026-10-24 第二轮裁决；FR-004/US-4
  场景 1/SC-004 措辞已同步）。
- Q: Abandoned 收尾触发（毒化收尾按 `consumed()/dropped()` 查询，P02
  契约授予 owner）是否需要验收判据？ → A: 需要——补一条白盒断言
  （读错误毒化路径上 Abandoned 已触发），不保留「有实现、无判据」的
  契约义务（2026-10-24 第二轮裁决；FR-005 已固化，tasks T010 白盒侧
  承载）。

### Session 2026-10-25

- Q: 取消错误是否允许以包装形态暴露（spec 多处「CallCancelled（或其
  包装）」）？ → A: 不允许——管线保证以裸 `CallCancelled` raise（不
  包装于其他错误内），`err is CallCancelled` 为全场景唯一判别式；spec
  全文删除「或其包装」对冲语（FR-003/FR-002a/US-3/SC-003 已同步）。
  依据：测试判别式（research R8）与 T007 的 `handle_cancellation`→
  直接 raise 映射设计一致，包装形态无消费方。

## Requirements *(mandatory)*

### 范围

**前置依赖**：P01（HttpUrl/HeadersV 值对象）、P02（Request/Response/
体模型与折叠头转换、回调契约）、P04（ConnectionPool/Lease/毒化）；
测试依赖 P03 夹具。下游：P06/P07/P08/P09 与 M2 拦截器链均在本包预留的
exchange 接缝上插入。

**包含**：

- `HttpClient` 门面：持有 `ConnectionPool`（P08/P09 配置位仅预留
  扩展点，本包不建字段——YAGNI，P08 落位）；直连形态构造 API。
- `Call`：`request`/`client`/`cancelled` 标记；一次性语义；`is_cancelled`。
- `Call::execute`：单次 exchange 管线（内部函数 `exchange` 为接缝）。
- 取消三通道：标记终止 / 子任务组关闭（读写中的协程立即失败）/ 连接
  毒化不回池；`CallCancelled` 显式错误变体。
- L3 落地：折叠头 Map（P02 转换层产物）缓存在 Call 上，重放复用同一
  实例。
- 归池/毒化执行侧闭环：完整消费→回池；未读完即弃→skip 后回池或失败
  毒化；`Connection: close`→读完即 close；取消/异常→毒化。
- 1xx 信息响应语义记录（透传 @http 既有行为）。

**非目标（显式排除，含归属，clarify 不复议）**：

- 拦截器链与 Bridge/Cache 层——归 M2（差异 D1；exchange 接缝预留）；
- `enqueue` 与 Dispatcher——归 P09（差异 D2）；
- follow-up 循环/重定向/重试——归 P06/P07（在接缝上包裹；本包 execute
  只跑单轮）；
- 超时接线——归 P08（在同一管线时序上包裹）；
- WebSocket 门面——归 M5；
- 101 协议切换透传——归 M5（本包仅透传 1xx 自动跳过的既有语义）。

### Functional Requirements

- **FR-001**（种子）Call MUST 一次性：同一 Call 在完成、失败或取消后，
  再次 execute MUST raise 可判别的显式状态错误；MUST NOT 出现未定义
  行为或静默重跑。
- **FR-002**（种子）cancel MUST 三通道生效：
  (a) 标记——已 cancel 的 Call，execute 及后续管线步骤直接终止；
  body 消费阶段（execute 已返回后）读路径任何失败若 `cancelled==true`
  MUST 以裸 `CallCancelled` 暴露，网络错误仅在未取消时透传
  （2026-10-24 第二轮 clarify 裁决）；
  (b) 在途协程取消——执行体包在可独立取消的子任务组中（Call 持句柄），
  cancel 后读写中的协程立即失败；
  (c) 连接毒化——被取消 exchange 所用连接 MUST NOT 回池。
- **FR-003**（种子）取消 MUST 以显式 `CallCancelled` 错误变体暴露，
  可与网络错误判别（宪法 III：OkHttp 映射表见本 spec「宪法合规口径」，
  差异已显式记录）。管线保证以裸 `CallCancelled` raise（不包装于其他
  错误内），`err is CallCancelled` 为全场景唯一判别式（2026-10-25
  第三轮 clarify）。
- **FR-004**（种子）折叠头 MUST 每 Call 恰好折叠一次（HeadersV→Map，
  P02 转换层产物）并缓存在 Call 上；同 Call 内强制重放 N 次复用同一
  Map 实例，且 N 次线上字节逐字节相同（差异 D4 收敛口径；@http 内部
  逐段 blit 不在消除范围，属侵入项 I8 边界外）。重放断言限定可重复体
  （Bytes）；Stream 体一次性，其重放策略（缓冲/拒绝）归 P06/P07
  （2026-10-24 第二轮 clarify 裁决）。
- **FR-005**（种子）响应体析构 MUST 遵守 P02 回调契约，三类事件映射：
  完整消费→release 回池；显式丢弃且未读完→先 `skip_response_body`
  尝试、成功回池、失败毒化；取消或异常→毒化。归池前提：请求发送已完成
  且 body 完整消费（03 §3.2；连接 clean state 约束，取证锚点
  `client.mbt:351-355`）。Abandoned 收尾触发（毒化收尾按
  `consumed()/dropped()` 查询，P02 契约授予 owner 的义务）MUST 有
  白盒验收断言，不得「有实现、无判据」（2026-10-24 第二轮 clarify）。
- **FR-006**（种子）exchange 接缝 MUST 显式（单次 exchange 的内部函数
  边界：池租借→发送→收响应头→构建 Response→归还），供 M2 拦截器链
  与 P06/P07 循环在同一接缝插入；本包 execute MUST 只跑单轮、MUST NOT
  内置 follow-up/重试循环。
- **FR-007**（种子）`Connection: close` 响应头 MUST 在 body 读完（或
  skip 完成）后关闭连接、MUST NOT 回池；判定在管线侧实现、消费 P04
  预留的判定接口约定（与 004 号 spec FR-010 的归属口径一致）。
- **FR-008** `HttpClient` MUST 持有 `ConnectionPool` 并提供直连形态
  构造；builder 全量 API 与配置透传归 P08，本包公开面 MUST NOT 含
  builder。
- **FR-009** execute MUST 同步等待单次 exchange 完成并返回完整
  `Response`（code/headers/body；ResponseBody 挂在租约上）；exchange
  在可取消子任务组内执行、调用方经 `task.wait()` 阻塞至返回（结构化
  并发，不跨事件循环投递——2026-10-25 analyze 措辞校准）；定长/
  chunked 帧形态由 P02 转换层既有判定决定，本包不改写。
- **FR-010** 1xx 信息响应 MUST 透传 @http 既有行为（自动跳过并回调，
  取证锚点 `client.mbt:232-253`）；回调不进本包公开面（宪法 VI 最小
  面，C3 默认口径见 Assumptions，2026-10-24 owner 确认），101 透传归
  M5。
- **FR-011**（边界）execute 中非取消错误（如连接 RST）MUST 透传调用方
  且连接 MUST 毒化（不回池）；重试判定归 P07——本包只保证「不回池」
  这一半。
- **FR-012**（边界）cancel MUST 幂等：重复 cancel 无错；`is_cancelled`
  MUST 即时反映取消状态；cancel 与 release 竞争（body 读完后才到达）
  MUST NOT double-close、MUST NOT 报错、MUST NOT 把已归池连接再毒化。
- **FR-013**（边界；C4 默认口径）同一 HttpClient 的并发 Call MUST 各自
  独立租借连接、互不干扰；P09 之前无 Dispatcher 闸门——该并发语义
  MUST 在 API 文档显式声明。
- **FR-014**（.mbti 冻结面，可验收）HttpClient/Call 公开面 MUST 与本
  spec「Key Entities」一致并冻结：execute/cancel/is_cancelled、门面
  构造与 Call 创建；MUST NOT 含 enqueue（差异 D2）、拦截器 API
  （差异 D1）、builder（P08）。实现完成后 `.mbti` 审视（宪法 VI）以
  其为对账面，计划外公开项为零。
- **FR-015**（C2 默认口径，2026-10-24 owner 确认维持；同日 plan 裁决
  落地）「未读完即弃」的处置以 P02 回调契约为唯一依据。plan 核实：
  MoonBit 无语言层析构机制（强于「不可靠」——P02 先例即显式 `drop()` +
  状态查询），且 `drop()`/`on_event` 为同步、skip 为异步、结构化任务组
  不可在 execute 返回后续存（research R1/R3）⇒ 按本条预留的收敛方向改为
  强制显式丢弃 API：`ResponseBody` 增 `dispose()`（显式异步收尾——已消费
  no-op；否则触发 `Dropped` 后执行注入的 skip→回池/失败毒步；形状见 plan
  contracts §2：`stream` 增 `on_dispose?` 参 + `dispose` 方法），client
  冻结面（FR-014）零变化。`drop()` 语义零变化（纯状态标记；仅 drop 不
  dispose ⇒ 租约滞留，文档化为调用方责任）。dispose 自身幂等：收尾动作
  （Dropped 触发 + `await on_dispose()`）整体至多一次有效，已完成 ⇒
  no-op；先 `drop()` 再 `dispose()` 仍补执行收尾（drop 不阻断）；
  disposed 后再 `drop()` 亦 no-op——2026-10-24 第二轮 clarify 补充契约，
  条款见 contracts §2 第 6 条。

### Key Entities

- **HttpClient**：门面。持有 ConnectionPool；P08/P09 配置位仅预留
  扩展点（本包不建字段，YAGNI）；公开面 = 直连构造 + Call 创建/execute
  入口（FR-014 冻结）。
- **Call**：一次待执行请求的句柄。request/client 引用、cancelled 标记、
  一次性执行状态、`is_cancelled` 查询；持有子任务组取消句柄；缓存
  折叠头 Map（L3，每 Call 一次）。
- **exchange 接缝**：单次 exchange 的内部函数边界（租借→折叠→发送→
  收头→构建→归还），M2 拦截器链与 P06/P07 循环的统一插入点。
- **Response（管线产物）**：code/headers/body；ResponseBody 挂在租约
  上，其消费事件（完整消费/显式丢弃/异常）驱动连接去向（FR-005）。
- **CallCancelled**：取消的显式错误变体，与网络错误判别（FR-003）。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: US-1–US-5 全部验收场景测试全绿，native 与 wasm 双 target
  （宪法 IV/V）。
- **SC-002**: 复用可证——同一 HttpClient 连续 execute 同一 Address，
  夹具侧累计新建连接数恰为 1（US-1 场景 2）；`Connection: close` 后
  再 execute 新建连接计数 +1（US-1 场景 3）。
- **SC-003**: 取消三阶段全部以裸 `CallCancelled` 终止（不包装，
  `err is` 判别）、0 挂
  死；被取消连接在其后全部租借中再次出现次数为 0（毒化不回池，池计数
  可断言）。
- **SC-004**: 重放零折叠可证——同 Call 强制重放 N 次：折叠函数执行计数
  恰为 1，N 次捕获的线上字节两两逐字节相同（限定可重复体 Bytes；
  Stream 重放策略归 P06/P07，2026-10-24 第二轮 clarify）。
- **SC-005**: body 生命周期 0 错路由——回池/skip 回池/毒化三路径均以
  池计数 + 夹具「下个请求读到干净流」双证据断言，路由错误为 0。
- **SC-006**: 外部网络依赖为 0——全部测试仅访问 P03 本地夹具
  （loopback），断网环境全套测试仍全绿。
- **SC-007**: 公开面零泄漏——实现完成后 `.mbti` 审视（宪法 VI）显示
  HttpClient/Call 公开面与本 spec「Key Entities」一致、计划外公开项
  为 0、enqueue 为 0（对账面 FR-014）。

## Assumptions

- **C1 默认**：取消底座为 runtime 水平触发取消（协程持久标记，后续
  async 操作立即失败），执行体包入可取消子任务组、Call 持句柄；子任务
  组的确切公开 API 形状（0.22.x 公开面）归 plan 阶段核实。本 spec 只
  约定行为：「cancel 后在途读写立即失败、以 CallCancelled 可判别」，
  不绑定具体原语名。2026-10-24 plan 核实（research R1）：底座为
  `@async.with_task_group` + `TaskGroup::spawn` 的 `Task` 句柄
  （`Task::cancel` 同步幂等）；判别用非弃用 `handle_cancellation`
  （None=正常取消）。行为约定不变。
- **C2 默认**：「未读完即弃」按 P02 回调契约处置；析构时机可靠性由
  plan 核实，不可靠则强制显式 API（FR-015 收敛方向已预留）。
  2026-10-24 clarify：owner 确认维持两段式。
- **C3 默认**：1xx 回调不在 M1 暴露（宪法 VI 最小面），透传既有跳过
  行为并在本 spec 记录语义；暴露面变化留 M5 与 101 一并裁决。
  2026-10-24 clarify：owner 确认不在 M1 暴露。
- **C4 默认**：并发语义（无闸门）显式写入 API 文档（FR-013），不设
  运行时限制。
- 发送路径 body 分块尺寸（种子 16–64KB）与管线内对象计数（连接已建时
  ≈2 个对象：头块引用 + body 引用，01 §6）为 plan/实现级细节，本包
  测试只断言发送成功与夹具接收内容正确。
- js target：仅 `moon check --target js` + 可行时 node 冒烟（execute+
  cancel 直通路径）；不入合入门禁（宪法 V、差异 D14）。js 路径
  execute 直通（无池语义）、cancel 经 AbortController，归池/毒化语义
  不适用——挂欠账跟踪（F9 形态），随 M5 收口。

## 宪法合规口径（OkHttp 映射表 / Target 矩阵 / 性能影响 / 测试方案）

**OkHttp 映射表（宪法 III）**：

| OkHttp 5.5.0 行为 | moonhttp 本包对应 | 差异注记 |
| --- | --- | --- |
| Call 不可重复执行：重复 `execute()` raise `IllegalStateException` | 同义：二次 execute raise 可判别状态错误（FR-001） | 对齐；错误类型命名随本仓惯例（plan 定名） |
| 取消：`cancel()` 后以 `IOException("canceled")` 暴露（按消息判别） | `CallCancelled` 显式错误变体（FR-003） | **有意差异**：变体判别替代消息判别，判别性更强；语义等价（取消可区分于网络错误），宪法 III 要求的显式记录即此行 |
| `enqueue`/Dispatcher 并发闸门 | 不在本包（差异 D2，归 P09） | P05 前 execute 直通、无闸门（FR-013 文档化） |
| 拦截器链（应用/网络双层） | 不在本包（差异 D1，归 M2）；exchange 接缝预留 | 接缝保证 M2 无重写成本 |
| 超时（connect/read/write/call） | 不在本包（归 P08）；包裹点已在管线时序上预留 | P08 在同一时序叠加，不改本包结构 |
| WebSocket / 101 透传 | 不在本包（归 M5） | 1xx 自动跳过语义透传（FR-010） |
| 弃读处置：`body.close()` 同步排空后连接复用 | `ResponseBody::dispose()` 异步排空（skip 成功回池、失败毒化，FR-005/FR-015） | **有意差异**：同步↔异步由单线程结构化并发约束决定（plan R3：drop/on_event 同步、skip 异步、组不可在 execute 后续存）；仅 `drop()` 不收尾 ⇒ 租约滞留——OkHttp 有 GC 弱引用泄漏检测、本仓无，文档化 + F9 欠账 |

**Target 矩阵（宪法 V）**：

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 质量门双绿 target；同一路径 |
| js | ⭕ | **未验证**（差异 D14，挂欠账 F9 随 M5 收口）：execute 直通（无池语义），cancel 经 AbortController（@http js 后端已接）；归池/毒化语义不适用 |
| wasm-gc | ❌ | 上游 runtime 缺口（差异 D9） |

**性能影响（宪法 II）**：L3 杠杆——重放路径零重复折叠（本包机制级
断言，US-4；量化收益在 P10 的重定向/重试场景基准体现）。管线自身不加
分配放大：折叠缓存后，热路径新增对象 ≈ Lease + Response 壳（01 §6
口径）；本包测试不断言延迟数字（量化归 P10，避免基准抖动侵蚀测试
稳定性）。

**测试方案**：US-1/US-3/US-5 全部基于 P03 夹具（echo/慢速/残数据/
连接计数），native+wasm 双绿；US-4 用桩接缝 + 捕获对端做计数与字节级
断言；js 仅编译检查 + 可行时冒烟（不入门禁）。

## 包级 DoD（验收判据）

1. US-1–US-5 验收场景测试全绿（native/wasm 双 target）。
2. 取消三阶段 + 毒化（连接不回池）有池计数侧断言。
3. `moon info && moon fmt` 干净；`.mbti` 冻结 HttpClient/Call 公开面
   （execute/cancel/is_cancelled；无 enqueue；FR-014/SC-007）。
4. OkHttp 映射表（Call 一次性、取消错误分类）保留于本 spec（宪法
   III），implement 阶段不回改语义。

## 待澄清项（移交 /speckit.clarify）

种子澄清问题 C1–C4 均已按「合理默认」写入 Assumptions（无
[NEEDS CLARIFICATION] 标记）；clarify 议程状态（2026-10-24）：C2/C3
owner 已裁决（见 Clarifications）、C1 已由 plan 核实回记、C4 为 FR-013
固化的实现期文档义务（非未决问题），如 owner 推翻默认值，回改本 spec
后再向下传导：

- **C1**（plan 已核实 2026-10-24）子任务组取消句柄形状：底座为
  `with_task_group`/`Task` 句柄，判别用 `handle_cancellation`（research
  R1）；行为约定不变，Assumptions C1 已回记。
- **C2**（已裁决 2026-10-24）「未读完即弃」最终策略：owner 确认维持
  两段式——默认 P02 回调契约处置，plan 证实析构时机不可靠才改为强制
  显式丢弃 API（见 Clarifications）。plan 已于同日核实并落地：
  `ResponseBody::dispose()` 显式收尾 API（FR-015 回记，contracts §2）。
- **C3**（已裁决 2026-10-24）1xx 回调不在 M1 暴露给用户：owner 确认
  最小面口径（见 Clarifications）；暴露与否留 M5 与 101 一并裁决。
- **C4** execute 并发语义文档（默认显式声明无闸门）。

## 参考

- `docs/roadmap/M1/P05-call-engine-cancel.md`（本包唯一规格种子）
- `docs/roadmap/M1/README.md` 第 2/3 节（依赖拓扑；差异 D1/D2/D4/D9/
  D14 登记）
- `proj-init-docs/okhttp-on-async-http/01-calls/README.md` §3.5（Call/
  取消三通道）、§6（头块缓存与分配目标）、§8；§2 表（runtime 取消
  底座）
- `proj-init-docs/okhttp-on-async-http/03-connection-pool/README.md`
  §3.2（归池前提）、§3.4（毒化表）
- 下游引用方：P06（循环包裹接缝）、P07（recover 插入）、P08（超时
  包裹）、P09（enqueue+闸门）、M2 04（拦截器链接缝）
- `specs/004-m1-p04-connection-pool/spec.md`（P04 判定接口约定
  FR-010、毒化契约侧；本包为执行侧闭环）
- `specs/003-m1-p03-test-fixtures/spec.md`（echo/慢速/残数据/连接计数
  夹具冻结面）
- `.specify/memory/constitution.md`（原则 I/II/III/IV/V/VI/VII）
