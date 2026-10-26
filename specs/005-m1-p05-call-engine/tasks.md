# Tasks: Call 执行骨架与取消（M1-P05）

**Input**: Design documents from `/specs/005-m1-p05-call-engine/`

**Prerequisites**: plan.md（必读，四决策节与 FR/US↔元测试映射表）、spec.md
（Clarifications C2/C3 已裁决 + FR-001～015 + SC-001～007）、research.md
（R1–R8：取消底座/@http 锚点/dispose 裁决/夹具/js/测试组织）、data-model.md
（五实体/七不变量/两状态机）、contracts/call-api.md（client 冻结面 §1 + core
裁决面 §2）、quickstart.md（六门命令与 `-p` 假验证警示）

**Tests**: 本包**行为任务（T002–T013）**按宪法 IV「验收场景与测试先行」
执行——每任务的自证元测试与实现在**同一任务内成对出现（先红后绿）**；
「只写实现、测试另立任务补」为违规排布（003 tasks:7 口径）。Setup 与
收口任务（T001、T014–T017）为治理/对账任务，无红绿对（2026-10-25
analyze F10 校准）。双 target（native/wasm）为每对
任务的默认验收；js 仅编译检查不入门禁（D14/F9）。护栏/落笔即绿判据须在
任务产出中显式标注，不得静默（004 T016 先例）。

**Organization**: 按用户故事分组（US-1～US-5，spec 优先级）；core dispose
裁决面与 client 骨架为 Foundational 阻塞项。**阶段顺序说明**：US-1→US-3
→US-5 为 P1 依赖链（execute 单轮 → cancel 接线 → 体生命周期闭环，后两者
消费前者的管线与 I-3 时序）；US-2（P2）在 US-3 之后，其「已取消」前态需要
cancel 在场，且穷尽成功/失败/取消三种终态路径；US-4（P2）仅依赖 exchange
接缝（T006），可在 Phase 3 后任意时点插入，默认压轴保持阶段单调。Story
标签与 spec 编号一一对应，优先级标注不受阶段顺序影响。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无未完成依赖）
- **[Story]**: 所属用户故事（US1/US2/US3/US4/US5，对应 spec 用户故事 1～5）
- 描述含精确文件路径

## Path Conventions

- 门面包：`src/client/`（池已在此，P04 结构裁决延续——管线入同包，
  `http_client.mbt`/`exchange.mbt`/`body_bridge.mbt` 三新文件 +
  `call_test.mbt`/`call_wbtest.mbt` 两新测试文件；`moon.pkg` 零改动预期，
  async/async/http/fixtures 依赖已具备）
- core 增面：`src/core/response_body.mbt`（且仅 FR-015 裁决面，contracts §2）
- 夹具：`src/internal/fixtures/`（期望零 diff；F-8 若触发扩展，逐处归因
  FR-010，plan 风险 R3 兜底）
- 零改动：`src/core` 其余文件（P01/P02 既有面零 diff）

---

## Phase 1: Setup（共享基线）

**Purpose**: 动工前固化基线，供后续 diff 归因与回归对照；核实 F-8 夹具
1xx 能力（plan 风险 R3 首片）

- [X] T001 记录动工前基线（只读测量，无代码改动）：静态测试计数
  `grep -rhP '^\s*(async\s+)?test\s' src --include='*_test.mbt'
  --include='*_wbtest.mbt' | wc -l` 当前实测 **== 193**（含
  `src/client/pool_longrun_wbtest.mbt:19/:123` 两条 `#skip` 长跑 ⇒
  双 target 运行时基线 `Total tests:` **== 191**，T015 判据以此为准）；
  再依次运行六门
  （`moon check --target native/wasm --deny-warn`、`moon test --target
  native/wasm --deny-warn`——运行时判据 `Total tests:` 非 0、
  `moon fmt --check`、`moon info`），将六门结果与
  `src/client/pkg.generated.mbti`、`src/core/pkg.generated.mbti`、
  `src/internal/fixtures/pkg.generated.mbti` 快照存入本特性目录
  `specs/005-m1-p05-call-engine/baseline.md`（对照物：Phase 8 的
  T014～T015；动工时如遇数目漂移，以实测为准并记录新值与原因）
- [X] T002 [P] F-8 核实：1xx-then-200 组合响应夹具能力（implement 首片，
  plan 风险 R3/R6）：审读 `src/internal/fixtures/`（scripted_server*.mbt）
  判定 `ResponseScript` 能否表达 1xx 组合响应。**两点判据前置（analyze
  C5）**：①`mount_sequence`/`RouteScript::Sequence`（P04 产物）是
  **跨请求**命中序（scripted_server.mbt:46-48/:193-194），不满足单
  请求内 1xx→200，勿据其误判已支持；②status=100 合法性已有
  `reason_of` 兜底（无校验门）证据可引用，免重复核实。
  `PeerProgram::Capture` 不受影响；结论追记
  `specs/005-m1-p05-call-engine/research.md` R6 待核项——支持 ⇒ 夹具
  零改动；不支持 ⇒ 先红后绿最小扩展：`scripted_server_test.mbt` 写
  P05-FIX①（红）→ `scripted_server.mbt` 裸写状态线扩展（绿），`.mbti`
  增面逐处归因 FR-010。本任务只核实与（必要时）夹具扩展，不写 client
  侧行为测试

---

## Phase 2: Foundational（阻塞项：core dispose 裁决面 + client 骨架）

**Purpose**: FR-015 裁决面是 BodyBridge on_dispose 注入的前提（contracts
§2 是 T003/T005/T014 的对账面）；HttpClient/Call 骨架与错误变体被全部
故事消费

**⚠️ CRITICAL**: 本阶段未完成前不得开始任何 US 行为任务

- [X] T003 [P] core FR-015 裁决面 `dispose`（先红后绿）：
  `src/core/response_body_lifecycle_test.mbt` 写 dispose 语义元测试六条
  （红）——①`consumed()==true` ⇒ dispose 为 no-op（处置已由 Consumed
  通道完成）；②未消费 dispose ⇒ 置 dropped 并触发 `Dropped` 事件（与
  `drop()` 同一互斥时序、先到者赢）后 `await on_dispose()`；③
  `on_dispose` raise ⇒ 错误透传（毒化由注入方在 raise 前完成）；④
  `on_dispose` 缺省 ⇒ 等价当前 `drop()`（纯状态标记，core 独立可用性
  不被 P05 绑架）；⑤`drop()` 语义零变化；⑥幂等与收尾唯一性（第二轮
  clarify 增补）：收尾动作整体至多一次有效、已收尾再 dispose ⇒ no-op、
  先 `drop()` 再 `dispose()` 补执行收尾（drop 不阻断）→ 实现
  `src/core/response_body.mbt`：`ResponseBody::stream` 增可选参
  `on_dispose? : async () -> Unit raise`（既有参数位置不变）+ 新增
  `pub async fn ResponseBody::dispose(Self) -> Unit raise`（contracts
  §2 六条契约逐条落地）；`moon info` 核对 core `.mbti` 增面**恰好等于
  §2 且仅此**（P01/P02 既有面零 diff）
- [X] T004 [P] client 骨架 + 错误变体（先红后绿）：
  `src/client/call_wbtest.mbt` 新建写 P05-WB①②③（红）——①
  `HttpClient::new(pool)` 持池零网络动作、`new_call(request)` 装箱
  Pending 态 Call（state 白盒直读，I-1 初版；不校验 URL 可达性）；②
  `is_cancelled` 初始 false、`cancel()` 置 true 且重入幂等无错（I-5
  标记通道初版）；③`CallCancelled`/`CallStateError` derive(@debug.Debug)
  且 `err is` 可判别、网络错误不在此二层 → 实现
  `src/client/http_client.mbt` 新建：`HttpClient`（priv 持
  ConnectionPool，**不建** P08/P09 配置位字段，YAGNI）+
  `HttpClient::new(pool)`/`HttpClient::new_call(request)` + `Call` 私有
  字段 request/client/state/cancelled/task/lease/folded/fold_count
  （data-model §1 实体 2 全字段一次落位，fold_count 为 US-4 白盒断言面）
  + `Call::is_cancelled` 直读 + `Call::cancel` 标记通道（Task::cancel 与
  毒化接线归 T008）+ 两 suberror 变体（data-model 实体 5，plan 定名随本
  仓惯例）；`placeholder()` 原样保留（P6 延续）

**Checkpoint**: core dispose 面就绪（`.mbti` 恰为 contracts §2）、client
骨架与判别性错误变体可用——US 行为任务可以开始

---

## Phase 3: User Story 1 — execute 单次请求与连接复用（Priority: P1）🎯 MVP

**Goal**: execute 直连管线单轮可用：POST（Bytes/Stream 体）得到完整
`Response`（code/headers/body）、连续 execute 复用池化连接、
`Connection: close` 与 1xx 语义正确（US-1 场景 1～4 + 边界 1xx；
FR-004/006/007/008/009/010 机制在场）

**Independent Test**: `moon test -p hahh9527/moonhttp/client --target
native|wasm -f "P05-US1*"`（黑盒）+ `-f "P05-WB*"`（白盒接缝）——全部基于
P03 夹具（echo/连接计数/捕获对端），不依赖 P06/P07/P08/P09

### Implementation for User Story 1（每任务 = 元测试先红 → 实现转绿）

- [X] T005 [US1] BodyBridge 读适配器与租约处置状态机（先红后绿）：
  `src/client/call_wbtest.mbt` 写 P05-WB④～⑦（红）——④EOF 读到底 ⇒
  Consumed ⇒ `release` 回池 + lease 置 None（I-3：处置后立刻置 None）；
  ⑤读中网络错误 ⇒ poison+release + lease 置 None + 错误判别：未取消
  ⇒ 原样透传（不包装）、`cancelled==true` ⇒ 映射裸 `CallCancelled`
  （FR-002a，2026-10-25 第三轮定形态）；⑥读边界发现 cancelled ⇒
  raise `CallCancelled`（cancel 已完成
  poison+release，FR-002a）；⑦on_dispose 注入三分支：skip 成功→
  release / skip 失败→poison+release 后透传错误 / `call.cancelled` 或
  lease 已 None→no-op（data-model 实体 4、I-4 0 错路由）→ 实现
  `src/client/body_bridge.mbt` 新建：包装 `@io.Reader`（内持 @http
  Client）+ 三行读路径职责 + on_dispose 注入点（skip 收尾的端到端验收
  在 T010，本任务白盒直驱）
- [X] T006 [US1] exchange_once 接缝（先红后绿）：`src/client/
  call_wbtest.mbt` 写 P05-WB⑧（红）——桩直调 exchange_once：Address
  推导正确（`Request.url`→scheme/host/port；Protocol→串匹配为包内私有
  helper，不用弃用 Show）、单轮终止无 follow-up/重试循环（FR-006 结构
  审）、首次折叠后 `fold_count==1` 且再次直调不再折叠（I-2 初版）→
  实现 `src/client/exchange.mbt` 新建：折叠缓存（folded 由 None→Some
  恰一次，经 `HeadersV::to_http_map()`，P02 转换层产物）+ 单轮管线
  pool.acquire→`Client::request(extra_headers=folded)`→Bytes 走
  `write_once`/Stream 走 `write_reader`→`end_request()`（不传 1xx 回调，
  C3 裁决落地）→`Response::from_http`+`ResponseBody::stream(bridge,
  on_event, on_dispose)`；execute 只调一轮（FR-006）
- [X] T007 [US1] execute 包装 + US-1 黑盒场景（先红后绿）：
  `src/client/call_test.mbt` 新建写 P05-US1①～⑥（红）——①echo 夹具
  POST（Bytes 体）：code/headers/body 正确、回显一致（FR-009）；②同一
  HttpClient 连续 3 次 execute 同一 Address：夹具侧新建连接数==1 且池侧
  计数一致（SC-002 双证据）；③`Connection: close`（close_after_response）
  响应读完后再次 execute：新建连接计数 +1（FR-007，旧连接未回池）；④
  未知长度 Stream 体：`CapturedRequest.chunked==true` 且内容逐字节一致
  （帧形态由 P02 判定，本包不改写）；⑤1xx-then-200 组合响应（消费 T002
  结论）：execute 返回最终响应、缺省回调不暴露（FR-010）；⑥GET 冒烟：
  捕获请求行方法为 GET 且无 body 发送（US-1 描述 GET/POST 覆盖，
  analyze C2 补）→ 实现
  `src/client/http_client.mbt` 增 `pub async fn Call::execute`：Pending
  首检（非 Pending→`CallStateError`，Executing 同步置位无重入窗口，I-1；
  cancelled→`CallCancelled` 零网络，FR-002a）→`@async.with_task_group`→
  `spawn(exchange_once)` 存 `Task` 句柄→`task.wait()`→
  `handle_cancellation` 返回 None 映射 `CallCancelled`（FR-003；I-6：
  映射后收尾仅同步操作——poison/release/close，R1 证据）；弃用面零引用
  （`is_cancellation_error`/`with_cancellation_handler`/`Timer` 等
  `--deny-warn` 门，R1）

**Checkpoint**: MVP——execute 单轮 + 复用/close/chunked/1xx/GET 全链路
native+wasm 双绿，可独立验证后暂停

---

## Phase 4: User Story 3 — cancel 三阶段（Priority: P1）

**Goal**: cancel 三通道全接线：预取消零网络、写中/读中取消以
`CallCancelled` 终止且连接毒化不回池、幂等与迟到 cancel 竞争安全
（US-3 场景 1～4 + FR-002/003/012 + 边界 cancel/release 竞争；I-5/I-6）

**Independent Test**: `moon test -p hahh9527/moonhttp/client --target
native|wasm -f "P05-US3*"`（黑盒）+ `-f "P05-WB*"`（竞争/收尾白盒）——
P03 慢速/滴流夹具 + 池计数断言；禁 sleep 串联，以夹具节奏与读边界推进

- [X] T008 [US3] cancel 三通道接线（先红后绿）：`src/client/
  call_test.mbt` 写 P05-US3①～④（红；池计数断言等价式：毒化 ⇒
  `per_host_total(addr)` 不变 + 下次 execute 夹具 `accepted_total` +1，
  「再现次数 0」级断言走 P05-WB 白盒直读——analyze B2）——①预取消后 execute：立即
  `err is CallCancelled` 且 accepted_total==0（零网络动作，US-3-1）；
  ②SlowReceive 慢收 + 大 body 写入中 cancel：写路径以裸
  `CallCancelled` 失败、该连接毒化不回池（池计数断言，US-3-2）；③Drip 滴流
  读中 cancel：读路径以裸 `CallCancelled` 失败、连接毒化（池
  计数断言，US-3-3；in-flight 读失败同样映射，spec 第二轮 clarify 裁决）；④cancel 后
  `is_cancelled==true`、重复 cancel 幂等无错（FR-012 前半，I-5）→
  实现 `src/client/http_client.mbt` `Call::cancel` 完整接线：置标记→
  `Task::cancel`（在途读写协程立即失败，R1/R4）→lease 非 None 时
  poison+release（同步关连、清引用置 None——**I-3 时序是 FR-012 竞争
  安全的支点：处置完成即置 None，迟到 cancel 只见 None**）；
  `src/client/body_bridge.mbt` 读边界接标记通道（T005⑥ 的 cancelled
  判定改读真实标记）
- [X] T009 [US3] 迟到 cancel 竞争与同步收尾白盒（先红后绿/护栏）：
  `src/client/call_wbtest.mbt` 写 P05-WB⑨⑩——⑨I-3/FR-012 竞争：读到底
  →release 回池→迟到 cancel→无错、不 double-close、已归池连接不受影响
  （下个 execute 复用且新建连接不增）；⑩I-6 收尾仅同步：
  `handle_cancellation`→None 映射后的清理路径仅 poison/release/close、
  零 await（**护栏/结构审判据**——混入 async 操作即违规：None 后未保护
  async 操作立即取消，R1 证据；落笔即绿形态，显式标注。可执行判据
  （analyze B4）：收尾路径白名单仅 `Lease::poison`/`Lease::release`/
  `Client::close`，`protect_from_cancel` 零使用列入 code review 检查单）
  → 缺处补齐
  （预计零或极小改动）

**Checkpoint**: 取消三阶段 + 毒化闭环——被取消连接在其后全部租借中再现
次数为 0（SC-003 池计数可断言）

---

## Phase 5: User Story 5 — 响应体生命周期闭环（Priority: P1）

**Goal**: 归池/毒化执行侧闭环：读到底→回池；未读完即弃→dispose→skip
后回池或失败毒化；异常→毒化（US-5 场景 1～3 + FR-005/011/015 + 边界
空 body/非取消错误；I-4）

**Independent Test**: `moon test -p hahh9527/moonhttp/client --target
native|wasm -f "P05-US5*"`（黑盒）——P03 夹具（echo/残数据/断连注入）+
池计数断言；回池路径以「复用 + 夹具下个请求读到干净流」双证据断言
（SC-005）

- [X] T010 [US5] 归还闭环三路径（先红后绿）：`src/client/call_test.mbt`
  写 P05-US5①～⑤（红）——①流式 body 读到最后一块：连接回池（下次
  execute 复用、新建连接计数不增，US-5-1）；②读一半即弃→`dispose()`：
  skip 清理回池 + 夹具侧下个请求读到干净流无残帧（US-5-2 双证据，端到端
  消费 T003 的 core dispose 面）；③skip 失败注入（PartialResponse+
  close_after_response）：毒化关闭、池计数守恒（US-5-3）；④非取消错误
  毒化（FR-011）：RST/断连→错误透传调用方 + 连接不回池（重试判定归
  P07，本包只保证不回池）；⑤空 body（Content-Length: 0）：消费即刻
  完成、连接回池（边界）；白盒侧 `src/client/call_wbtest.mbt` 写
  P05-WB⑫（红）——读错误毒化路径上 Abandoned 已触发（`consumed()/
  dropped()` 查询，P02 owner 义务闭环，spec FR-005 第二轮 clarify）→
  实现 `src/client/body_bridge.mbt`/
  `src/client/exchange.mbt` 收口：on_dispose 注入 `skip_response_body()`
  异步收尾（成功→release/失败→poison+release 后透传，R3 裁决——组不可
  在 execute 返回后续存，skip 落在消费者协程）+ Abandoned 按
  `consumed()/dropped()` 查询在毒化收尾触发（data-model §4）+ 归池前提
  「发送完成∧体完整消费或 skip 成功」（I-4）

**Checkpoint**: 体生命周期 0 错路由——回池/skip 回池/毒化三路径双证据
全绿（SC-005）；P05 执行侧与 P04 契约侧配对完成

---

## Phase 6: User Story 2 — Call 一次性语义（Priority: P2）

**Goal**: 同一 Call 二次 execute 得到可判别状态错误（非 panic、非静默
重跑）：完成/失败/取消三种前态穷尽 + 状态机直驱（US-2 场景 1 + FR-001；
I-1）

**Independent Test**: `moon test -p hahh9527/moonhttp/client --target
native|wasm -f "P05-US2*"`（黑盒）+ `-f "P05-WB*"`（状态机白盒）——纯
Call 状态断言为主，失败前态需一次网络动作

- [X] T011 [US2] 一次性语义穷尽 + 状态机直驱（先红后绿）：
  `src/client/call_test.mbt` 写 P05-US2①～③（红）——①已完成（成功交付
  Response 后）、②已失败（网络错误透传后）、③已取消（CallCancelled 后）
  三种前态下二次 execute 均 `err is CallStateError`（FR-001）；`src/
  client/call_wbtest.mbt` 写 P05-WB⑪ 状态机直驱（I-1 全迁移：Executing/
  Done 态 execute→CallStateError；成功/失败/取消三路终态置 Done，data-
  model §3 图 1）→ T007 首检核对，缺处补齐（预计零或极小改动——首检已
  随 T007 落位，本任务补穷尽前态与终态置位）

**Checkpoint**: 恶性未定义行为防线闭合；全部 US-1～US-5 行为路径在场

---

## Phase 7: User Story 4 — 重放零折叠（L3，Priority: P2）

**Goal**: 折叠头每 Call 恰好折叠一次、重放复用同一实例、N 次线上字节
逐字节相同（US-4 场景 1 + FR-004/SC-004；I-2；差异 D4 收敛口径——@http
内部逐段 blit 不在消除范围）

**Independent Test**: `moon test -p hahh9527/moonhttp/client --target
native|wasm -f "P05-US4*"`（白盒，按测试名跨文件收集）——桩接缝在同一
Call 内强制重放 N 次 + P03 捕获对端字节比对，不经 P06/P07

- [X] T012 [US4] 重放零折叠白盒（先红后绿）：`src/client/
  call_wbtest.mbt` 写 P05-US4①（红；**盒型注记**：fold_count/folded 为
  包内私有，黑盒不可读（E4091，004 R9 先例），故 US-4 落白盒——
  quickstart §2「US-4（白盒）」口径一致）——带多条头与 Bytes 体（可
  重复体；Stream 不在重放断言范围，spec FR-004 第二轮 clarify 裁决）的
  Request 同一
  Call 内桩接缝强制重放 N 次：`fold_count==1`（SC-004）、folded 复用
  同一 Map 实例、`PeerProgram::Capture` N 次捕获线上字节两两
  `assert_eq` → 若不满足修 `src/client/exchange.mbt` 折叠缓存（T006 已
  落机制，预计小改或不改）；**依赖仅 T006，可在 Phase 3 后任意时点插入**

**Checkpoint**: L3 机制级保证可证（量化收益归 P10 基准，本包不断言延迟
数字）；全部用户故事独立可用

---

## Phase 8: Polish & Cross-Cutting（收口）

**Purpose**: 并发语义文档化、冻结审视、门禁收口、对账与归档

- [X] T013 [P] FR-013 并发语义文档 + 冒烟（先红后绿）：`src/client/
  call_test.mbt` 写 P05-US1⑦（红）——同一 HttpClient 并发 N≥8 个 Call
  （对齐 004 K=8 先例）：各自租借不同连接、互不串响应
  （`peak_concurrent==N` 断言，池并发租借
  前提）→ `src/client/http_client.mbt` API 文档注释显式声明：P09 之前
  无 Dispatcher 闸门、并发 Call 各自独立租借（C4 文档义务）；文档部分
  为护栏判据（非红绿），显式标注
- [X] T014 `.mbti` 冻结面对账（FR-014/SC-007/I-7）：`moon info` 后逐条
  对照 `contracts/call-api.md`——`src/client/pkg.generated.mbti` 恰为
  §1（placeholder 保留 + HttpClient::new/new_call + Call::execute/
  cancel/is_cancelled + CallCancelled/CallStateError；**无** enqueue/
  拦截器 API/builder/`request` 访问器/`exchange_once`/BodyBridge/1xx
  回调参数）；`src/core/pkg.generated.mbti` 恰为 §2 且仅此；
  `src/internal/fixtures` 零 diff（F-8 例外逐处归因 FR-010）；命名全
  snake_case
- [X] T015 收口六门（最终轮先 `moon clean` 再全量）：quickstart §1 逐条
  ——`moon check --target native/wasm --deny-warn`、`moon test --target
  native/wasm --deny-warn`（`-p` 只认全包名 `hahh9527/moonhttp/client`，
  执行后核对 `Total tests:` = 运行时基线 191 + 新增数且非 0，换算见
  T001）、`moon fmt --check`、
  `moon info` 审视；SC-006 核查：grep 测试文件目标地址仅
  `127.0.0.1`/`localhost` + 夹具 `port()`（无外网端点，analyze C3）；
  随后按映射表（下）对账 FR-001～015、SC-001～007
  覆盖无缺项
- [X] T016 js 非门禁（D14/F9）：`moon check --target js` 编译验证（零
  `#cfg(js)` 分支，R7）；可行时 node 冒烟（execute+cancel 直通路径），
  失败不阻塞合入、登记欠账（归池/毒化语义不适用 js，随 M5 收口）
- [X] T017 收尾归档（plan 收尾事项 1～4）：`.mbti` 三面对账结论归档本
  特性目录、F-8 核实结论归档（T002 产出）、`placeholder` 保留确认（P6
  延续，删除评估留后续收口片）、宪法自查（I/III/IV/V/VI/VII）随 PR
  记录（含持续盯防两处：取消收尾无 async 操作、body 阶段 cancel 的
  lease 置 None 时序——plan 风险 R1/R2）

---

## FR/US ↔ 任务 ↔ 元测试映射表（包级 DoD 对账面，承 plan 同名表加任务列）

| spec 条目 | 任务 | 元测试（文件·盒型） |
| --- | --- | --- |
| FR-001/US-2 一次性 | T007、T011 | call_test P05-US2①～③ 黑盒 + call_wbtest P05-WB⑪ 白盒 |
| FR-002a(标记)/US-3-1 预取消 | T004、T008 | call_test P05-US3① 黑盒（execute 首检，accepted_total==0） |
| FR-002a(body 阶段映射)/US-3-3 | T005、T008 | call_wbtest P05-WB⑥ 白盒 + call_test P05-US3③ 黑盒（`cancelled==true` ⇒ 裸 CallCancelled，analyze E3 拆行） |
| FR-002b/US-3-2 写中取消 | T008 | call_test P05-US3② 黑盒（SlowReceive+大 body；CallCancelled+池计数） |
| US-3-3 读中取消 | T008 | call_test P05-US3③ 黑盒（Drip 滴流；边界失败+毒化） |
| FR-003 判别性 | T004、T007、T008 | 变体 `err is` 判别（P05-WB③）+ 场景落点 |
| FR-004/US-4 零折叠 | T006、T012 | call_wbtest P05-WB⑧ + P05-US4① 白盒（fold_count==1 + raw 两两 assert_eq） |
| FR-005/US-5 体生命周期 | T005、T010 | call_wbtest P05-WB④～⑦ 白盒 + call_test P05-US5①～⑤ 黑盒（三路径+池计数双证据） |
| FR-006 接缝/单轮 | T006、T007 | call_wbtest P05-WB⑧（桩直调）+ execute 无循环结构审 |
| FR-007 Connection:close | T007 | call_test P05-US1③ 黑盒（读完 close 不回池，新建+1） |
| FR-008 直连构造 | T004、T014 | 骨架（P05-WB①）+ contracts §1 对账 |
| FR-009 完整 Response | T007、T010 | call_test P05-US1① + P05-US5① 黑盒 |
| FR-010 1xx 透传 | T002、T007 | F-8 结论 + call_test P05-US1⑤ 黑盒（缺省回调不暴露） |
| FR-011 非取消错误毒化 | T005、T010 | call_wbtest P05-WB⑤ 白盒 + call_test P05-US5④ 黑盒（RST/断连→透传+不回池） |
| FR-012 竞争/幂等 | T008、T009 | call_test P05-US3④ 黑盒 + call_wbtest P05-WB⑨ 白盒（迟到 cancel→复用不新建） |
| FR-013 并发语义 | T013 | API 文档 + call_test P05-US1⑦ 黑盒冒烟（N≥8） |
| FR-015/C2 dispose | T003、T010 | core lifecycle test 六条（含幂等/收尾唯一性，contracts §2 第 6 条）+ call_test P05-US5② 黑盒（dispose 承载） |
| FR-014/SC-007 冻结面 | T014 | `moon info` 对账 contracts §1/§2 |
| SC-001/SC-006 双 target/零外网 | T015 + 全部测试任务 | quickstart §1 六门；全部测试仅访问 P03 本地夹具 |
| SC-002 复用可证 | T007 | call_test P05-US1②③ 黑盒（新建==1 / close 后 +1，双计数） |
| SC-003 取消三阶段 | T008、T009 | call_test P05-US3①～④ 黑盒 + call_wbtest P05-WB⑨⑩ 白盒 |
| SC-004 重放零折叠 | T012 | call_wbtest P05-US4① 白盒（fold_count==1 + raw 两两 assert_eq） |
| SC-005 0 错路由 | T010 | call_test P05-US5①～⑤ 黑盒 + P05-WB⑫ 白盒（池计数+干净流双证据） |

> 不变量对照：I-1→T011、I-2→T006/T012、I-3→T005/T008/T009、I-4→T010、
> I-5→T004/T008、I-6→T007/T009、I-7→T014。

## Dependencies & Execution Order

### Phase 依赖

- **Phase 1（Setup）**：T001 无依赖立即开始；T002 可并行（只触及
  fixtures/research.md）
- **Phase 2（Foundational）**：依赖 T001；T003（core 包）与 T004（client
  包）异包可并行；**阻塞全部 US 任务**（T005 消费 T003 的 on_dispose
  参数与 T004 的 Call 字段）
- **Phase 3（US-1）**：依赖 Phase 2；T005→T006→T007 串行（bridge 是
  exchange 的构件、execute 是 exchange 的唯一公开入口；且白盒同文件
  演进）——MVP
- **Phase 4（US-3）→ Phase 5（US-5）**：依赖 Phase 3（cancel 接线消费
  execute 的 Task 句柄；体闭环消费 I-3 时序与标记通道）
- **Phase 6（US-2）**：依赖 T007+T008（「已取消」前态需要 cancel 在场）
- **Phase 7（US-4）**：**依赖仅 T006**——可在 Phase 3 后任意时点插入，
  默认压轴保持阶段单调
- **Phase 8（Polish）**：依赖全部 US 完成；T013 可与 T011/T012 并行准备
  （异任务异断言面，同包文件须协调先后）

### 并行机会

- T002 ∥ T003 ∥ T004（fixtures+research.md ∥ core ∥ client，三处互异）
- Phase 3 内 T005→T006→T007 串行（依赖链 + call_wbtest.mbt 同文件演进），
  无 [P] 标注
- T012（call_wbtest.mbt P05-US4①）与 Phase 4/5 的 call_test.mbt 工作
  异文件，可并行推进（同包编译，合入前须 reconcile）
- T013 与 T014～T017 无依赖冲突

## Implementation Strategy

- **MVP**：Phase 1+2+3（US-1）交付后即得「可发请求、可复用连接的最小
  门面」，独立验证（`-f "P05-US1*"` 双 target）后可停
- **增量**：每 Phase 收尾跑一次分包双 target（quickstart §2/§3 过滤器），
  红不进下一 Phase；每任务或逻辑组完成后 commit（Conventional Commits
  中文描述）
- **收口**：Phase 8 六门 + `.mbti` 三面对账 + FR/SC 覆盖核对无缺项 +
  归档

## Notes

- **`-p` 只认包名**：`moon test -p hahh9527/moonhttp/client`；写目录路径
  （如 `-p src/client`）**跑 0 个测试却返回 exit 0**（假绿）——每条
  `-p` 命令后核对 `Total tests:` 非 0（quickstart §0）
- **测试命名**：`P05-US*`（黑盒为主；US-4① 落白盒，按测试名跨文件
  收集）/`P05-WB*`（白盒）/夹具侧 `P05-FIX*`（仅 F-8 触发时）——与
  quickstart `-f` glob 一致，不得自创前缀
- **先红后绿**：每任务元测试先失败再转绿；护栏/落笔即绿判据（T009⑩、
  T011、T012、T013 文档部分）须显式标注，不得静默（004 T016/T010 先例）；
  「预计零或极小改动」类任务（T011/T012）完成判据＝对应元测试在场且
  全绿，如需修复实现须在任务产出登记改动与原因（analyze B9/D3）
- **禁 sleep 串联**：取消/滴流场景以夹具节奏（SlowReceive/Drip）与读
  边界推进；断言优先 `assert_eq`/`assert_true(pattern is …)`，错误判别
  一律 `err is CallCancelled`/`err is CallStateError`
- **弃用面零引用**：`is_cancellation_error`/`with_cancellation_handler`/
  `Timer`/`TaskCancelled` 别名均弃用（R1），`--deny-warn` 门零引用；
  取消收尾仅同步操作（I-6）
- **白盒边界**：Call 私有字段（state/task/lease/folded/fold_count）仅
  经同包 `call_wbtest.mbt` 直读（I-7，004 R7 先例）；黑盒读 priv 即
  E4091，不得改公开面迁就测试
- **`moon.pkg` 零改动预期**：三新源文件与两新测试文件均为
  `hahh9527/moonhttp/client` 同包，async/async/http/fixtures 依赖已
  具备；若 implement 期需动 moon.pkg，逐处归因并汇报
- **[P] 语义**：不同文件、无未完成依赖；[Story] 标签对应 spec 用户故事
- 每个 Checkpoint 处停机验证（TDD 纪律，宪法 IV）；js 与 wasm-gc 不入门
  禁（宪法 V，T016 口径）

---

## Phase 9: Convergence

> 2026-10-25 converge 追加（append-only，不改既有任务）。意图清单＝
> FR-001～015、SC-001～007、US-1～5 全部验收场景与 5 条边界、plan 决策
> （R1–R9、contracts §1/§2、不变量 I-1～I-7）、宪法 I～VII；全部 17 条
> 既有任务按当前代码行为复核（勾选态不作为证据）。实测证据：`moon clean`
> 后 native/wasm `moon test --deny-warn` 双绿 **231/231**、
> `moon fmt --check` 绿、`moon info` 工作树零 diff、js 检查失败与欠账
> 登记一致（archive §4）。核对项中已在案登记、不另立任务者：在途读跨协程
> 关连悬挂（R9 偏差 3＋archive §8-1 上游欠账）、js 编译失败（P03 既有，
> archive §8-2）、Stream 回调 async 化（R9 偏差 1＋archive §1）、夹具三处
> 扩展（R9 逐处归因）、US3②/WB⑩ 写停摆取消形态（R9 偏差 3）。剩余两项
> actionable 缺口如下。

- [X] T018 Abandoned 触发闭环（先红后绿）：毒化收尾路径（读失败
  errdefer / dispose skip 失败 / 取消关连）按「未 Consumed 且未
  Dropped」判据经既有 on_event 通道触发 `ResponseBodyEvent::Abandoned`，
  Call 增 priv 触发标记供白盒断言；将 P05-WB⑫ 从「查询面双 false」
  恢复为 T010 原判据「读错误毒化路径上 Abandoned 已触发」（先红）——
  现状：src 内无任何 Abandoned 触发代码（core 冻结面无触发 API、client
  无触发调用），body_bridge.mbt「Abandoned 由毒化收尾按查询触发」与
  call_wbtest.mbt 注释声称已触发但与代码不符；若评估忠实落地必须 core
  增面，先按治理流程回改 spec/contracts 归因后再实现，不得手改 tasks
  绕开；同步修正上述两处注释与 archive.md §5「FR-001～015 无缺项」的
  失实表述 per FR-005（2026-10-24 第二轮 clarify MUST）与 T010、
  data-model §4（partial）
  **产出（2026-10-25）**：`fire_abandoned_if_orphaned`（已交付 ∧ 未
  Consumed ∧ 未 Dropped ⇒ 经 on_event 触发，幂等）挂接
  `poison_release`；core/client 公开面零变化（`.mbti` 零 diff，未走
  core 增面分支）；WB⑫ 更名「毒化路径 Abandoned 已触发」并恢复原判据
  （先红实测：12 tests 11 过 1 败 → 接线后 12/12）；WB⑨/WB⑦ 补互斥
  护栏（Consumed/Dropped 先到者赢不触发，落笔即绿已标注）；
  archive.md §5 补记修正；修正后 native/wasm 全量 231/231 双绿、
  `moon fmt --check` 绿
- [X] T019 FR-013 API 文档落位（护栏/落笔即绿，显式标注）：将
  `http_client.mbt` 文件末尾悬空的 FR-013 并发语义注释块（165～169 行，
  「本方法」无指代对象）挂接到 `Call::execute` 的文档注释位，使 C4
  「并发语义 MUST 在 API 文档显式声明」真实锚定公开 API——冒烟断言
  P05-US1⑦ 已在场，无红绿对 per FR-013/T013（partial）
  **产出（2026-10-25）**：注释块并入 `Call::execute` 文档注释（EOF 悬空
  块删除），护栏判据显式标注

---

## Phase 10: Convergence

> 2026-10-25 第二轮 converge 追加（append-only；不改既有任务与勾选态）。意图
> 清单＝FR-001～015、SC-001～007、US-1～5 全部验收场景（13）与边界（5）、plan
> 决策（R1–R9、contracts §1/§2、不变量 I-1～I-7）、宪法 I～VII；19 条既有任务
> 按当前代码行为复核（勾选态不作为证据）。实测（本轮）：`moon clean` 后
> native/wasm `moon test --deny-warn` 双绿 **231/231**、`moon check` 双 target
> 绿、`moon fmt --check` 绿、`moon info` 工作树零 diff。承上轮 triage 已在案、
> 不另立任务者：在途读跨协程关连悬挂（R9 偏差 3／archive §8-1；SC-003
> 「0 挂死」在 in-flight 读形态下未成立，属上游能力降级——建议 owner 后续在
> spec 措辞层收敛）、US3②/WB⑩ 写停摆形态（R9 偏差 3）、`BodySource::Stream`
> async 化（R9 偏差 1；可选参次序已核实未变）、js 编译失败（P03 既有）、
> fixtures 三处扩展（R9 逐处归因）。剩余 7 项 actionable 缺口如下。

- [X] T020 读错误路径取消映射（先红后绿）per FR-002a/US-3-3（partial）：
  `src/client/body_bridge.mbt:116-134` 的 `read_checked` 仅在读**边界**两次
  检查 `cancelled`；`self.inner.read_some` 抛错时 `errdefer` 只做
  `poison_release` 后原样外泄网络错误，注释 `:6-7` 声称的「cancelled ⇒ 映射
  裸 CallCancelled」在错误路径不成立——2026-10-24 第二轮 clarify 裁决
  「`cancelled==true` 时读路径任何失败一律映射 `CallCancelled`」未落地。
  改法：以 try/catch 取代 errdefer（毒化仍先于映射；未取消 ⇒ 原样透传不
  包装），把映射抽成可白盒直驱的单一判定（或等价形态）并补确定性用例：
  置 `call.cancelled` 后直驱错误映射 ⇒ `err is CallCancelled`；未取消对照
  ⇒ 原错误，不误映射；跑双 target 与 `-f "P05-WB*"`
  **产出（2026-10-26）**：`Call::map_read_error` 单点判定 + `read_checked`
  errdefer 改 try/catch（毒化先于映射，读前边界检查在 try 外、读后成功
  路径取消检查随其后语义零变化）；WB⑬⑭ 直驱实测（先红＝编译红
  map_read_error 不存在 → 绿＝双 target 全过），commit 84f6c44
- [X] T021 失败路径终态置位与死分支清理（先红后绿）per I-1/data-model §3
  图 1（partial）：`src/client/http_client.mbt:136-172` 的
  `@async.with_task_group` 在子任务失败时于组退出重抛（上游
  `task_group.mbt:258-274` `Fail(err) => raise err`），故 `:155-171` 的
  `state = Done`/`task = None`/`match outcome` 在**失败路径不可达**（源码
  推定，须以 T021 白盒用例实测确认）——预期语义为 `state` 停留 `Executing`、
  `task` 残留 `Some`、`ExchangeOutcome::Failed`（`:177-181`）为死分支；
  `P05-US2②` 之所以绿是靠 `Executing` 也抛
  `CallStateError`（FR-001 偶然满足，图 1「失败──▶ Done」未落实）。将终态
  置位移到组外兜底（catch 失败 ⇒ `Done`+清 task 后再透传），补白盒断言
  「失败后 `state is Done` 且 `task is None`」，并删除或启用 `Failed` 分支；
  保持取消/成功两路行为与既有用例零回归
  **产出（2026-10-26）**：WB⑮ 实测确认组退出重抛推定（先红 1 败：state
  停留 Executing）；终态置位兜底移组外 errdefer 形态（初版 try/catch 触发
  上游 [0092] fragile_catch_all 门，按其建议改 errdefer——清理不涉 err、
  语义等价且取消安全：失败 ⇒ state=Done + 清 task 后原样透传）；
  `ExchangeOutcome::Failed` 死分支与变体删除；US2①③/US3 全系/WB⑨⑩ 零
  回归，commit 5a123f4
- [X] T022 `Connection: close` 判定 token 化（先红后绿）per FR-007/SC-002
  （partial）：`src/client/exchange.mbt:114-117` 用 `v == "close"` 精确
  小写比较；@http 头值不归一（`parser.mbt:266-282`），重复头以 `","` 拼接，
  故 `Connection: Close`、`keep-alive, close` 均漏判 ⇒ 本应关闭的连接按
  poison 未置位回池（死连接）。改按 token 解析（`split(',')` +
  `trim().to_lower() == "close"`）；补大小写与多值头用例（夹具
  `extra_headers` 可直发原值，逐处归因 FR-007），断言「读完不回池、下次
  新建 +1」双证据
  **产出（2026-10-26）**：token 解析落位 exchange.mbt（任一命中即
  poison）；US1⑧⑨ 大小写/多值双证据（先红＝US1 套件 2 败——两形态均
  漏判死连接回池 → 绿＝US1 9/9 双 target），夹具零扩展，commit 3be0ec7
- [X] T023 execute 段非取消错误验收补齐（先红后绿）per FR-011/宪法 IV
  （partial）：现有注入全部落在体阶段（`call_test.mbt:616-719` 的
  `mount_truncated`、`call_wbtest.mbt:268-347`），请求发送/`end_request`
  阶段的非取消错误无判据（`exchange.mbt:78-86` 的 `errdefer
  poison_release` 有实现、无测试）。以既有 `PeerProgram::AcceptClose`
  （或 `PartialResponse(CutPoint::Nothing, true)`）在收头前关连，断言：
  错误原样透传（`!(err is CallCancelled)` 且非 `CallStateError`）、
  `call.lease is None`、后续 execute 新建计数 +1（毒化不回池）；夹具零扩展
  优先，若确需扩展逐处归因 FR-011
  **产出（2026-10-26）**：US5⑥ 黑盒（AcceptClose 错误透传 +
  per_host_total +1，夹具侧证据以 ScriptedPeer 第二次 run 重新 accept 的
  complete==false 凭证替代 accepted_total——该夹具无此计数器）+ WB⑯
  白盒 `lease is None`；【补判据：落笔即绿，显式标注】errdefer 毒化收尾
  实现在场、缺口为判据非行为，首跑即绿（非红绿对），commit 0f297e4
- [X] T024 FR-013 并发语义改文档注释（护栏/落笔即绿，显式标注）per
  FR-013/C4（partial）：`src/client/http_client.mbt:112-121` 的
  「P09 之前无 Dispatcher 闸门」为 `//` 行注释（全文件 `///` 文档注释计数
  为 0），`moon doc` 不可见——T019「并入 `Call::execute` 文档注释」的
  声称不成立。改为 `///` 文档注释并挂到 `pub async fn Call::execute`
  （含并发语义与调用方自控并发度），冒烟断言 `P05-US1⑦` 已在场、无红绿对
  **产出（2026-10-26）**：execute 注释块（含 FR-013 段）改 `///` 文档注释
  （全文件 `///` 计数 0→28，moon doc 可见、内容不缩水）；护栏/落笔即绿
  显式标注，US1⑦ 冒烟确认在场，commit 8138359
- [X] T025 `body_bridge.mbt` 头注与实现对齐 per 宪法 VI（contradicts）：
  `:12-19` 声称「不委托上游弃用面 `_get_internal_buffer`/`_direct_read`」
  「内部缓冲给空桩」，实际 `:110-112` 经 trait 面**委托内层缓冲**、
  `:146-160` 的 `_direct_read` 是完整实现（且内部缓冲直通绕过读边界取消/
  错误检查，仅因消费路径只走 `read_some` 而未暴露）。改正头注为零失真描述，
  或使缓冲访问与 `read_checked` 同源（至少显式注明绕过语义与适用范围）；
  不改公开面（I-7）
  **产出（2026-10-26）**：头注与 `_get_internal_buffer` impl 注释零失真
  对齐（三入口委托拓扑如实陈述：read_some/_direct_read ⇒ read_checked；
  缓冲直通绕过读边界取消/错误检查的适用范围显式注明）；零代码改动、公开
  面零变化（同 commit 8138359）
- [X] T026 `src/client/moon.pkg` 注释与配置对齐 + import 归因 per 宪法 VI
  （contradicts）：`:25-29` 声称「增补 `-reserved_keyword`」，`options`
  （`:31-33`）仅 `"-unused_package"`——删除该段或真正加入并与 core
  `moon.pkg`（`:5-7`）口径对齐；同轮补登 P05 对 `moon.pkg` 的 import 增补
  （`@io`/`@core`/`@debug`）归因（tasks 原「零改动预期」的逐处汇报义务），
  落点为本特性 research/archive 或文件内注释；`--deny-warn` 双 target 复核
  **产出（2026-10-26）**：删除失实 `-reserved_keyword` 增补段（复核本包
  无 `method` 字面量构造、--deny-warn 双 target 现绿未触发 [0035]，core
  口径不适用）；同位补登 P05 import 归因三项 @io/@core/@debug（git 核实
  基线 309e890~1 仅 4 import），commit 1a50bd8
