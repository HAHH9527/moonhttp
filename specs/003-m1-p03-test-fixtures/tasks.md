# Tasks: 可控服务端测试基建（M1-P03）

**Input**: Design documents from `/specs/003-m1-p03-test-fixtures/`

**Prerequisites**: plan.md（必读，四决策与验收口径）、spec.md（含 Clarifications D1–D5）、research.md（C1 探针证据 P-a～P-h 与 R1–R8 裁决）、data-model.md（实体/状态机/常量）、contracts/fixtures-api.md 与 contracts/wire-observations.md（契约面）、quickstart.md（验证命令）

**Tests**: 本包全部任务按宪法 IV「验收场景与测试先行」执行——每个行为的自证元测试与实现在**同一任务内成对出现（先红后绿）**；「只写实现、测试另立任务补」为违规排布。双 target（native/wasm）为每对任务的默认验收。

**Organization**: 按用户故事分组（US-1～US-5，spec 优先级）；迁移为 Foundational 阻塞项，先于一切行为任务。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无未完成依赖）
- **[Story]**: 所属用户故事（US1/US2/US3/US4/US5，对应 spec 用户故事 1～5）
- 描述含精确文件路径

## Path Conventions

- 单项目：`src/internal/fixtures/`（C1 裁决后的夹具包）、`src/core/`（唯一外部消费方）
- 迁移映射：`src/fixtures → src/internal/fixtures`；`@fixtures` 别名不变（包名未变，仅路径加 internal 段）

---

## Phase 1: Setup（共享基线）

**Purpose**: 迁移与改写前固化基线，供后续 diff 归因与回归对照

- [x] T001 记录迁移前基线：依次运行 `moon check --target native --deny-warn`、`moon check --target wasm --deny-warn`、`moon test --target native --deny-warn`、`moon test --target wasm --deny-warn`、`moon fmt --check`、`moon info`，将六门结果与 `src/fixtures/pkg.generated.mbti`、`src/core/pkg.generated.mbti` 快照存入本特性目录 `baseline.md`（对照物：T003/T025）

---

## Phase 2: Foundational（阻塞项：迁移 + 驱动辅助）

**Purpose**: 结构迁移必须先于一切行为任务；驱动辅助被全部故事消费

**⚠️ CRITICAL**: 本阶段未完成前不得开始任何 US 行为任务

- [x] T002 包迁移（一次性结构动作）：`git mv src/fixtures src/internal/fixtures`；`src/core/moon.pkg:21` 导入改路 `"hahh9527/moonhttp/fixtures"` → `"hahh9527/moonhttp/internal/fixtures"`（`for "test"` 保持）；同步 `src/core/wire_form_test.mbt` 与包内各文件头注释中的**自身路径**引用（`src/fixtures` → `src/internal/fixtures`）；**specs/002 已交付文档中的历史锚点一律不回改**（映射关系以 plan.md「收尾事项」第 3 条为准）；moon.pkg 依赖（moonbitlang/async + async/socket）不变。**bench/ 归档探针处置（analyze F2）**：`bench/diag_ovf/moon.pkg:9`、`bench/diag_probe/moon.pkg:17`、`bench/p02-t009-perf-probe/moon.pkg:19` 三处 `import "hahh9527/moonhttp/fixtures"` 会随迁移失效——三包属 owner 2026-10-16 处置的一次性归档件（source="src" 外、不入构建图、不参与门禁），本轮不改；P10 于 src 下重建正式基准时改用新路径
- [x] T003 迁移回归门：T002 后重跑六门（命令同 T001），`raw_peer_test.mbt` ①–⑦ 双 target 全绿；`.mbti` diff 审视——本步出现的路径性变化必须**唯一归因于 C1 裁决**（research.md R1.3），core 公开 `.mbti` 期望零 diff；与 T001 快照逐项对照并记录
- [x] T004 B-14 + B-15 驱动辅助（先红后绿）：新增生命周期/端口元测试于 `src/internal/fixtures/raw_peer_test.mbt`（红：`close()` 幂等、close 后新操作在超时上限内立即返回、`port()` 恒 > 0、stop 后不再接受新连接）→ 实现 `src/internal/fixtures/raw_peer.mbt` 共享辅助（bind `127.0.0.1:0` 回填 + 冲突自动重试 ≤3 次（FR-011）；每操作 `@async.with_timeout_opt` 保护（FR-004）；优雅关闭语义 = 关监听不再 accept、在途连接由其操作超时上限收尾）；重试分支若实现期证明不可驱动（bind :0 冲突几乎不可达），在任务产出中**显式记录「防御性分支未测」**，不得静默

**Checkpoint**: 迁移完成、基线恢复、驱动辅助就绪——US 行为任务可以开始

---

## Phase 3: User Story 1 — 脚本化 HTTP 场景（Priority: P1）🎯 MVP

**Goal**: 测试编写者用声明式 `ResponseScript` 编排路由级行为（延迟/重定向/echo/帧形态/连接关闭/挑战），`@http.Client` 直连可观测（B-01～B-06、B-08）

**Independent Test**: `moon test -p hahh9527/moonhttp/internal/fixtures --target native|wasm`（`scripted_server_test.mbt`）——夹具元测试 + `@http.Client` 原语直连验证（spec US-1 独立测试口径）

### Implementation for User Story 1（每任务 = 元测试先红 → 实现转绿）

- [x] T005 [US1] 创建声明式类型与句柄骨架：`src/internal/fixtures/scripted_server.mbt` 实现 `ResponseScript`/`Framing`/`BodyPlan`（data-model.md 实体 1）与 `ScriptedServer::start/port/mount/close`（contracts/fixtures-api.md §1；路由仅 `Listening` 态可 mount，FR-012 声明式）；配套元测试（红：mount 后 `serve_once` 能按脚本应答一次 `BodyPlan::Static` 的 200 响应）→ 转绿；复用 T004 辅助（B-14/B-15 server 侧）
- [x] T006 [US1] B-01 + B-02 延迟与滴流（先红后绿）：`scripted_server_test.mbt` 写 US-1 验收场景 1 元测试（`GET /slow`：头延迟 300ms、体 3 块每块间隔 100ms；`@async.now()`（async 根包 mbti:26）观测头时延与块间隔符合编排，容差 ±50ms）→ `scripted_server.mbt` 实现 `head_delay_ms` 与 `BodyPlan::Drip`（`send_response` 后逐块 write + `@async.sleep(interval)` + `end_response`）——**本任务是首个示踪弹垂直切片**（声明→服务端→客户端观测贯通）
- [x] T007 [US1] B-03 重定向链（先红后绿）：`scripted_server_test.mbt` 写 US-1 验收场景 2 元测试（`301→/a`、`302→相对 ../b`、`303→绝对 http://127.0.0.1:PORT/c` 逐跳状态码与 Location 逐项符合；补 307/308 与畸形 Location 各一例）→ 实现多路由 Location 互指编排（status + headers 原样下发）
- [x] T008 [US1] B-04 echo 唯一 id（先红后绿，FR-013）：`scripted_server_test.mbt` 写 US-1 验收场景 3 元测试（并发 N≥8 个带唯一 id 请求经 task group，响应体 = `<单调id>:<请求体原样>`，id↔请求体一一对应、无串号无重复）→ 实现 `BodyPlan::Echo`
- [x] T009 [US1] B-05 定长/chunked 帧形态（先红后绿；**风险 R3 落点**）：`scripted_server_test.mbt` 用捕获对端/原始字节读断言线上帧形态（**一律以线上字节为准，不信任调用序**——`@http.ServerConnection::write` 有缓冲语义，server.mbt:128-129「MAY be buffered, call flush」）：`Framing::Fixed` ⇒ 线上含 `Content-Length: n` 且体恰 n 字节；`Framing::Chunked` ⇒ 不含 CL、块边界经 flush 保真 → 实现 framing 分派（`extra_headers` 契约见 server.mbt:190-197）
- [x] T010 [US1] B-06 + B-08（先红后绿）：`scripted_server_test.mbt` 元测试（`close_after_response=true` ⇒ 响应携带 `Connection: close` 且应答后连接实际关闭；`status=401/407` + 对应 Authenticate 头按声明下发）→ 实现；B-07 gzip **不排任务**（D4 已裁 M1 缺口，仅映射表标注）

**Checkpoint**: US-1 独立可用——编写者可纯声明式编排 B-01～B-06/B-08 全部行为（SC-002 的零改库用证即本阶段测试本身）

---

## Phase 4: User Story 2 — 裸 TCP 故障注入（Priority: P1)

**Goal**: 测试编写者用 `ScriptedPeer` 程序化注入网络级故障（accept 后 close、半截响应头、慢速接收）并产出 FR-015 观测清单（B-09～B-12）

**Independent Test**: `moon test -p hahh9527/moonhttp/internal/fixtures --target native|wasm`（`scripted_peer_test.mbt` + `fr015_observation_test.mbt`）

### Implementation for User Story 2

- [x] T011 [US2] RawPeer → ScriptedPeer 演进：`src/internal/fixtures/raw_peer.mbt` 引入 `PeerProgram`/`CutPoint`（data-model.md 实体 3）与 `ScriptedPeer::start/port/mount/run/close`（contracts/fixtures-api.md §2；**返回值语义：仅 `Capture` 程序的 `CapturedRequest` 承载捕获断言，其余程序返回值不承载断言语义**）；`src/core/wire_form_test.mbt` 同步（`RawPeer` → `ScriptedPeer` + `Capture` 程序）；既有 ①–⑦ 元测试保持双 target 全绿（红绿对：演进后全绿即通过，行为实现为既有底座搬运）
- [x] T012 [US2] B-09 accept 后立即 close（先红后绿）：`scripted_peer_test.mbt` 写 US-2 验收场景 1 元测试（复用连接上发请求 → 客户端收到 EOF/ReaderClosed 类错误，为 P07 提供判据）→ 实现 `AcceptClose` 程序。实现注记：本任务元测试以「已建立连接上写入后对端 close」等价驱动；真正的连接池复用判据归 P07
- [x] T013 [US2] B-11 半截响应头三截断点参数化（先红后绿；**风险 R2 落点**）：`scripted_peer_test.mbt` 按 `CutPoint = Nothing | MidStatusLine(n) | AfterStatusLine | MidHeaderLine(n)` **穷举三截断点**（US-2 场景 2 用 `MidStatusLine(15)`），逐点断言客户端错误落在钉死集合 **{BadRequest, ReaderClosed}**（spec D3/E4；**出现集合外形态即为 spec 变更信号，停手回报，不得扩集或放宽**）；P07 的「不可重试」分支不得以「客户端能观测到状态行已解析」为判据 → 实现 `PartialResponse`（canned 响应字节前缀来自 frames.mbt 头注的写出形态取证）
- [x] T014 [US2] B-12 慢速接收滴流（先红后绿）：`scripted_peer_test.mbt` 元测试（accept 后按声明节奏读、不读满，写侧可观测停滞）→ 实现 `SlowReceive(read_bytes, interval_ms)`
- [x] T015 [US2] B-10/FR-015 观测清单生成：新增 `src/internal/fixtures/fr015_observation_test.mbt`——矩阵 = target×在途未读数据{有,无}，每行跑「accept →(按前置条件写 0/N 字节)→ close」，裸 socket 客户端读并分类；**断言仅「结局 ∈ {@io.ReaderClosed, @os_error.OSError}」**（E5），真实结局 `println("[FR-015 观测] target=… pending_unread=… outcome=…")` 打点；**禁止手写断言代替实测**；native 与 wasm/moonrun 各跑一份（命令见 quickstart §3），格式与失败口径按 contracts/wire-observations.md；不得把 RST 写成可稳定断言的交付行为（D2/E3）

**Checkpoint**: US-2 独立可用——四类故障注入可编排、观测清单可生成

---

## Phase 5: User Story 3 — 原始字节捕获（Priority: P1)

**Goal**: 捕获对端两判据完整可断言（B-13 底座既有，本阶段补齐 spec 场景缺口并作 US-5 重写的回归锚点）

**Independent Test**: `moon test -p hahh9527/moonhttp/internal/fixtures --target native|wasm`（按包运行；需收窄用测试名 glob `-f "P03-B13*"`，旗标语义见 Notes）

- [x] T016 [US3] US-3 两判据补全（`src/internal/fixtures/raw_peer_test.mbt`）：① 定长 POST ⇒ 捕获可解析出 `Content-Length` 且**显式断言不含 `Transfer-Encoding`**（spec US-3 场景 1，P02 US-2 判据源）；② 同一请求重放两次 ⇒ 两次捕获字节逐字节相同（spec US-3 场景 2）。性质为**回归锚点**：底座已交付（spec 既定事实登记），预期落笔即绿；若出现红即为底座回归，修复归本任务（与实现同任务成对的口径在本任务体现为「判据补全 + 缺口即修」）

**Checkpoint**: US-3 判据面闭合，为 Phase 6 重写提供护栏

---

## Phase 6: User Story 5 — 大负载与畸形帧的确定性判定（继承缺陷回归，Priority: P1）

**Goal**: 五处继承缺陷逐条消除（FR-006～FR-010），判定相位无关、超限即时归一、平方成本消除、重复头检出、断言辅助参数化

**Independent Test**: `moon test -p hahh9527/moonhttp/internal/fixtures --target native|wasm`（`frames_scan_wbtest.mbt` + `sc003_sc004_test.mbt`）——构造字节流（多相位/超大数值/重复头/非 POST 形态）二值断言

### Implementation for User Story 5（顺序执行，后者依赖前者）

- [ ] T017 [US5] 上限校准（显式决策任务）：`src/internal/fixtures/frames.mbt:40/43` 常量按 data-model.md 调整——`max_head_bytes` 保持 64KiB（无场景需要更大，夹具上限非客户端特性）；`max_body_bytes` 8MiB → **16MiB**（SC-003 需 8MB 级捕获留余量，贴边测试脆弱，仍 ≪2^31 封顶安全）；**新增** `max_size_line_bytes = 1KiB`（chunk 大小行自身长度上界，RFC 9112 允许 chunk-ext，1KiB 对测试足够宽——FR-006 判定支点）。**回滚口径**：三常量独立命名、集中一处，任一引发意外失败可单独回退旧值而不牵连状态机结构
- [x] T018 [US5] FrameScanner 增量状态机重写（缺陷 1＋3，先红后绿）：新增 `src/internal/fixtures/frames_scan_wbtest.mbt` 白盒元测试——①相位矩阵：同一 >64KiB chunked 字节流按 {1,7,100,8191,8192,8193} 字节切分（含劈中大小行的相位）喂入 `feed`，判定/负载/原始字节 100% 一致（FR-006/SC-004，**红：现行绝对偏移上界在这些相位下假 Broken**）；②垃圾/畸形输入不 panic 不无限累加（FR-014）→ 重写 `src/internal/fixtures/frames.mbt` 为 `feed(bytes) -> Signal` 纯推进状态机（data-model.md 实体 5：头增量查找 3 字节跨块重叠、大小行行缓冲受 `max_size_line_bytes`、数据块按剩余计数、trailer 找 CRLFCRLF），`raw_peer.mbt` 读循环改喂进式（每字节处理一次，废弃全量 `to_bytes()` 重扫，raw 仅终态一次复制，FR-005/FR-010）；既有 ①–⑦ 与 T016 全程保持绿（回归护栏）
- [ ] T019 [US5] FR-007 数值封顶累加（先红后绿）：`frames_scan_wbtest.mbt` 元测试（红：`Content-Length: 99999999999` 与 chunk 大小行 `FFFFFFFF` 在现行实现出现回绕三型症状之一）→ 实现「累加中 >`max_body_bytes` 即时 `Broken("超出夹具上限")`」（data-model.md 实体 4 不变量），断言即时返回（耗时 ≪ 外层超时）且不出现空负载假收完
- [ ] T020 [US5] FR-008 重复 Content-Length 判畸形（先红后绿）：`frames_scan_wbtest.mbt` + `raw_peer_test.mbt` 元测试（红：现行只取首个同名头）→ 实现头解析收集全部 `content-length`，≥2 即 `Broken("重复 Content-Length")`（与 TE 在场无关，TE 分派前判定；单 CL + TE:chunked 的既有优先序不变），断言同值/异值双头均畸形、note 可辨认、raw/head 全留存
- [ ] T021 [US5] FR-009 断言辅助参数化（先红后绿）：`src/internal/fixtures/` 新增 `RequestLineExpect{method, target}` 与 `CapturedRequest::assert_matches`（contracts/fixtures-api.md §3；手法参考上游 `#callsite(autofill(loc))` 范式，代码自建，D8）——`scripted/sc003` 测试以 GET /、PUT /x、POST /p?a=b 三形态经同一辅助断言（红：现行 core 辅助硬编码 `POST / HTTP/1.1` 前提）→ `src/core/wire_form_test.mbt:129-142` 的 `assert_captured_frame` 切换为参数化辅助并显式传入期望形态
- [ ] T022 [US5] SC-003 性能元测试（先红后绿）：新增 `src/internal/fixtures/sc003_sc004_test.mbt`——`@async.now()` 实测 2MB 与 8MB chunked 捕获（构造 >`max_body_bytes` 余量内的 8MiB 负载），断言 `t8 ≤ 5×t2` 且 `t8 ≤ 2s`（红：旧引擎 8MB 实测约 10.2s 超阈 → T018 后转绿）；常驻默认套（修复后自缚上界不拖门，取舍理由见 plan「SC-003/SC-004 执行设计」）；SC-004 黑盒端到端同文件补真实 socket 不同写片重放一轮

**Checkpoint**: 五缺陷全消除；FR-006～FR-010 元测试双 target 全绿；US-3/US-2 护栏无回归

---

## Phase 7: User Story 4 — 慢速滴流参数化（Priority: P2）

**Goal**: P08 超时语义预验证场景（持续慢速滴 body vs 按操作 read 超时不触发）

**Independent Test**: `moon test -p hahh9527/moonhttp/internal/fixtures --target native|wasm`（按包运行；需收窄用测试名 glob `-f "P03-B01*"` 等，旗标语义见 Notes）

- [ ] T023 [US4] US-4 场景元测试（先红后绿）：`scripted_server_test.mbt` 写场景元测试（每 200ms 滴 1KB、总时长 3s 即 15 块的 body；`read_ms=1000` 按操作超时下**不触发超时**——每块间隔 < 超时阈值；用原生 `@http.Client` 预验证，spec US-4 口径）→ 实现侧仅需组合 T006 的 `BodyPlan::Drip(1024, 15, 200)`（若组合暴露 Drip 参数缺口，在本任务内补齐，不另立设计）

**Checkpoint**: 全部用户故事（US-1～US-5）独立可用

---

## Phase 8: Polish & Cross-Cutting（收口）

**Purpose**: 风险验证、门禁收口、文档与对账

- [ ] T024 风险 R1 验证：SC-003 的 2s 绝对阈值在 **wasm/moonrun** 上实测（运行 `sc003_sc004_test.mbt --target wasm` 记录 t2/t8）；超限处置顺序＝先查算法回归，确因宿主吞吐则**走 spec 变更流程附双 target 数据**（不得静默放宽判据）；结论记入任务产出
- [ ] T025 `.mbti` diff 审视 + 格式门：`moon info` 后逐条审 diff——**因迁移/公开面产生的 diff 必须唯一归因于 C1 裁决**（`src/fixtures → src/internal/fixtures`，internal 包 `.mbti` 非对外承诺；core 等公开包期望零 diff，违零即查）；`moon fmt --check` 通过
- [ ] T026 收口六门（最终轮先 `moon clean` 再全量）：`moon clean` → `moon check --target native --deny-warn` → `moon check --target wasm --deny-warn` → `moon test --target native --deny-warn` → `moon test --target wasm --deny-warn` → `moon fmt --check` → `moon info` 后审 diff；随后按「B-01～B-15 ↔ 任务 ↔ 元测试映射表」对账包级 DoD-2（B-07 标缺口），并核对 FR/SC 覆盖核对表（下两表）无缺项；另确认 T004 已产出「防御性分支未测」的显式记录（若适用，analyze F6 对账点）
- [ ] T027 文档收口：`src/internal/fixtures/frames.mbt` 文件头判停口径注释更新为新状态机口径（含新上限与大小行行缓冲）；FR-015 两份观测清单（native/wasm 各一份）随交付归档（quickstart §3 命令产出）
- [ ] T028 T009 回勾（**整包收口的最后一项**）：回勾 `specs/002-m1-p02-request-response/tasks.md:207-237` 的 T009 条目。**owner 2026-10-18 常设授权：满足判据即可回勾，无需再次请示**——下列三条须同时成立：① T026 六门全绿（含 `moon clean` 后全量重跑）；② 包级 DoD 全通过，含「B-01～B-15 ↔ 任务 ↔ 元测试」映射表对账（B-07 按缺口显式标注口径满足）；③ FR/SC 覆盖核对表无缺项。**反例约束**：仅「002 T009 的技术内容已在 P02 交付并通过」（2026-10-16 native+wasm 126/126）**不足以**触发回勾——owner 2026-10-16 裁决把勾与 P03 整包交付绑定，两者都要满足；判据不全时不得自主勾选。回勾时必须在本包留一行证据（六门结果 + 对账结论；引用位置：002 tasks.md T009 条目、本条、plan.md「收尾事项」第 2 条、quickstart §6）

---

## B-01～B-15 ↔ 任务 ↔ 元测试映射表（包级 DoD-2 对账面）

| 行为 | 任务 | 元测试（文件） | 状态 |
| --- | --- | --- | --- |
| B-01 延迟响应头 | T006 | scripted_server_test.mbt（US-1 场景 1） | 计划 |
| B-02 滴流（块数/间隔可调） | T006、T023 | scripted_server_test.mbt（场景 1 + US-4 场景） | 计划 |
| B-03 重定向链 | T007 | scripted_server_test.mbt（US-1 场景 2 + 307/308/畸形） | 计划 |
| B-04 echo 唯一 id | T008 | scripted_server_test.mbt（US-1 场景 3 并发 N） | 计划 |
| B-05 定长/chunked 可选 | T009 | scripted_server_test.mbt（线上字节断帧） | 计划 |
| B-06 Connection: close | T010 | scripted_server_test.mbt | 计划 |
| **B-07 gzip** | — | — | **M1 缺口·推迟（裁决 D4），不排任务** |
| B-08 401/407 挑战 | T010 | scripted_server_test.mbt | 计划 |
| B-09 accept 后 close | T012 | scripted_peer_test.mbt（US-2 场景 1） | 计划 |
| B-10 关闭形态观测清单 | T015 | fr015_observation_test.mbt（双 target 各一份） | 计划 |
| B-11 半截响应头（截断点参数化） | T013 | scripted_peer_test.mbt（三截断点穷举，US-2 场景 2） | 计划 |
| B-12 慢速接收滴流 | T014 | scripted_peer_test.mbt | 计划 |
| B-13 原始字节捕获 | T016、T018 | raw_peer_test.mbt ①–⑦ + frames_scan_wbtest.mbt | 计划（底座既有，本包回归） |
| B-14 端口分配/冲突重试 | T004 | raw_peer_test.mbt（生命周期组） | 计划 |
| B-15 生命周期/超时保护 | T004、T005 | raw_peer_test.mbt + scripted_server_test.mbt | 计划 |

## FR-001～FR-015 覆盖核对表

| FR | 覆盖任务 | 核对口径 |
| --- | --- | --- |
| FR-001 公开 API 零侵入 | 全部实现任务（约束）+ T026 | 仅 import `moonbitlang/async`（http/socket 根包）；无 native-stub；无上游资产搬运 |
| FR-002 每行为自证元测试 | 上映射表全行 + T026 | B-01～B-15（B-07 除外）逐行有元测试 |
| FR-003 仅 loopback | T004/T005 实现 + T026 | `127.0.0.1:0` 单点收口；审计无外部地址 |
| FR-004 超时保护/优雅关闭 | T004、T005、T011 | 每操作 `with_timeout_opt`；close 幂等；在途连接语义有元测试 |
| FR-005 捕获保序保完整 | T016、T018 | raw 逐字节断言贯穿既有 ①–⑦ 与新相位矩阵 |
| FR-006 相位无关判定 | T018 | 白盒相位矩阵（≥5 相位）+ 黑盒端到端 |
| FR-007 超上限归一 | T019 | 超大十进制/十六进制即时 Broken 三断言 |
| FR-008 重复 CL 判畸形 | T020 | 同值/异值双头 |
| FR-009 断言辅助参数化 | T021 | GET/PUT/查询路径三形态 |
| FR-010 耗时不平方增长 | T018、T022 | SC-003 判据 |
| FR-011 端口回填/冲突重试 | T004 | port()>0 主路径；重试分支按「防御性分支未测」显式记录（若不可驱动） |
| FR-012 声明式编排 | T005（mount 设计）+ T026 | 审计测试代码无手写服务端循环 |
| FR-013 echo 唯一 id | T008 | 并发 N 一一对应 |
| FR-014 畸形不 panic | T018 | 白盒垃圾输入用例 + 既有 ⑦ 保持 |
| FR-015 wasm 差异观测留痕 | T015、T024、T027 | 观测清单双 target 归档；宿主双套符号事实（E2）入文档 |

## SC-001～SC-006 覆盖核对表

| SC | 覆盖任务 | 缺项标注 |
| --- | --- | --- |
| SC-001 清单 100% 覆盖 + 双绿 | T026（映射表对账 + 四门） | 无 |
| SC-002 零改库编排骨 | T006–T010 用法即证 + T026 审计 | 无 |
| SC-003 2MB/8MB ≤5× 且 ≤2s | T022（native/wasm）+ T024（wasm 实测裁决） | 无（wasm 超限走 spec 变更流程，不得静默放宽） |
| SC-004 ≥5 相位 100% 一致 | T018（白盒矩阵）+ T022（端到端） | 无 |
| SC-005 外部网络依赖 0 | T026（FR-003 审计佐证） | 无 |
| SC-006 无泄漏/必返回 | T004（close 幂等/超时）+ T026（全套连续运行） | 无 |

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1（T001）**：立即可做
- **Phase 2（T002–T004）**：依赖 T001 基线；**阻塞全部 US 任务**（T002→T003→T004 严格顺序）
- **Phase 3（US-1）**：依赖 T004；T005 先行，T006–T010 依赖 T005（同文件演进，建议顺序执行）
- **Phase 4（US-2）**：依赖 T004；T011 先行（演进底座），T012–T014 依赖 T011，T015 依赖 T011
- **Phase 5（US-3）**：依赖 T004（与 Phase 3/4 无文件冲突，可并行）
- **Phase 6（US-5）**：依赖 T016（回归护栏）与 T017；T018 依赖 T017，T019/T020/T021 依赖 T018，T022 依赖 T018
- **Phase 7（US-4）**：依赖 T006（Drip 组合）
- **Phase 8**：依赖全部前序阶段

### User Story Dependencies

- US-1/US-2/US-3 在 Phase 2 完成后**互相独立**、可并行（不同文件：scripted_server / scripted_peer+raw_peer / raw_peer_test 判据补全）
- US-5 必须晚于 US-3（护栏先行）与 US-2（ScriptedPeer 演进定型后再重写内核，公开 API 稳定）
- US-4 依赖 US-1 的 B-02；为 P2 后置

### Parallel Opportunities

- Phase 2 完成后：US-1（T005–T010）与 US-2（T011–T015）、US-3（T016）三线可由不同执行者并行
- Phase 6 内 T019/T020/T021 理论可并行但共改 `frames.mbt`/相邻文件——顺序执行更稳，不建议并行
- T015（fr015_observation_test.mbt）与 T012–T014 若 CloseObservation 程序已由 T011 落入枚举，可并行（不同测试文件）

---

## Implementation Strategy

### MVP First（US-1 为最小增量）

1. Phase 1 → Phase 2（迁移+辅助，阻塞项）
2. Phase 3（US-1 全部）→ **STOP & VALIDATE**：`scripted_server_test.mbt` 双 target 全绿，US-1 三验收场景独立可演示
3. 逐 Story 递增：US-2 → US-3 → US-5 → US-4，每个 Checkpoint 独立验证
4. Phase 8 收口（风险验证 → 门禁 → 对账 → T009 回勾待 owner 复核）

### 红绿纪律（宪法 IV）

- 每个标注「先红后绿」的任务：先落元测试并**观察其失败原因符合预期**，再实现最小转绿；红不了的判据（防御性分支）必须显式记录而非静默
- US-5 重写期间，Phase 4/5 的既有套件是持续回归护栏——任何一步转绿不得以破坏护栏为代价

## Notes

- [P] 任务 = 不同文件、无未完成依赖
- `[USx]` 与 spec 用户故事 1～5 一一对应（US-5 为继承缺陷回归故事）
- `moon test` 的 `-f, --filter` 为**按测试名 glob 过滤**（2026-10-18 本机
  moon 0.1.20261012 实测 `moon test --help`：Run only tests whose name
  matches the given glob pattern），**不是按文件过滤**（analyze V1 定谳）；
  分场景收窄一律用测试名 glob（例：`-f "P03-B05*"`，命名遵循 P03-Bxxⓝ
  约定），按包运行（`-p`）为主；六门命令不使用 `-f`，零影响
- T028 的 002 T009 回勾**授权口径已更新**（owner 2026-10-18 常设授权）：
  三判据（六门全绿 / DoD 全通过对账 / FR-SC 核对无缺项）同时成立即可回勾、
  无需再次请示；反例约束＝仅「P02 已交付 T009 技术内容」不足以触发（勾与
  P03 整包交付绑定）；判据不全不得自主勾选。全文见 T028／plan 收尾事项 2／
  quickstart §6（三处同口径）
- 禁止排入任何本项目自有 C/FFI 绑定工作项（RST/SO_LINGER/shutdown 缺口已按 D2 处置，仅存「需人工批准的候选方案」）
- 每任务或逻辑组完成后 commit（Conventional Commits 中文描述）；push/合并须人工批准
